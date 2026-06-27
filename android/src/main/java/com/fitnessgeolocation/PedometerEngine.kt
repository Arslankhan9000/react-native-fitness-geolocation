package com.fitnessgeolocation

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import kotlin.math.sqrt

/**
 * Passive step session — hardware STEP_COUNTER baseline + accelerometer fallback.
 *
 * No foreground service: TYPE_STEP_COUNTER is a low-power hardware counter that survives
 * process death. On resume we read the cumulative counter delta since session baseline.
 */
class PedometerEngine(private val context: Context) : SensorEventListener {

  interface Listener {
    fun onPedometerUpdate(payload: Map<String, Any?>)
  }

  companion object {
    private const val TAG = "FitnessGeoPedometer"
    private const val PREFS = "fitness_geo_pedometer"
    private const val KEY_SESSION = "session_v1"
    private const val KEY_NEEDS_RECONCILE = "session_v1_needs_reconcile"

    @Volatile
    private var instance: PedometerEngine? = null

    fun getInstance(context: Context): PedometerEngine {
      return instance ?: synchronized(this) {
        instance ?: PedometerEngine(context.applicationContext).also { instance = it }
      }
    }
  }

  var listener: Listener? = null

  private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
  private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  private var stepCounter: Sensor? = null
  private var stepDetector: Sensor? = null
  private var accelerometer: Sensor? = null

  private var isRunning = false
  private var sessionId: String? = null
  private var sessionStartMs = 0L
  private var sessionSteps = 0
  private var sessionDistanceM = 0.0
  private var counterType = "STEP_COUNTER"
  private var lastEventMs = 0L

  // Hardware counter baseline (since boot)
  private var baselineCounter: Float? = null
  private var lastRawCounter: Float? = null

  // Accelerometer fallback (peak detection — stepUp / Navigine inspired)
  private var accelLast = 0.0
  private var accelPeak = false
  private var lastStepTs = 0L
  private val minStepIntervalMs = 280L
  private val accelThreshold = 11.2

  init {
    stepCounter = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    stepDetector = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
    accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    restorePersistedSession()
  }

  fun isSupported(): Boolean {
    return stepCounter != null || stepDetector != null || accelerometer != null
  }

  fun isAuthorized(): Boolean {
    if (Build.VERSION.SDK_INT < 29) return true
    return ContextCompat.checkSelfPermission(
      context, Manifest.permission.ACTIVITY_RECOGNITION,
    ) == PackageManager.PERMISSION_GRANTED
  }

  fun authorizationStatus(): String = when {
    Build.VERSION.SDK_INT < 29 -> "granted"
    isAuthorized() -> "granted"
    else -> "denied"
  }

  fun start(sessionId: String?): Map<String, Any?> {
    if (!isSupported()) {
      throw IllegalStateException("No step sensors available on this device")
    }
    if (Build.VERSION.SDK_INT >= 29 && !isAuthorized()) {
      throw SecurityException("ACTIVITY_RECOGNITION permission not granted")
    }

    if (isRunning && this.sessionId != null) {
      reconcileHardwareCounter()
      registerSensors()
      return snapshot()
    }

    val sid = sessionId ?: java.util.UUID.randomUUID().toString()
    this.sessionId = sid
    sessionStartMs = System.currentTimeMillis()
    sessionSteps = 0
    sessionDistanceM = 0.0
    baselineCounter = null
    lastRawCounter = null
    isRunning = true
    counterType = when {
      stepCounter != null -> "STEP_COUNTER"
      stepDetector != null -> "STEP_DETECTOR"
      else -> "ACCELEROMETER"
    }
    registerSensors()
    persistSession()
    return snapshot()
  }

  fun stop(): Map<String, Any?> {
    unregisterSensors()
    isRunning = false
    clearPersistedSession()
    return snapshot()
  }

  fun snapshot(): Map<String, Any?> = mapOf(
    "sessionId" to sessionId,
    "isRunning" to isRunning,
    "steps" to sessionSteps,
    "distance" to sessionDistanceM,
    "startDate" to sessionStartMs.toDouble(),
    "endDate" to (if (lastEventMs > 0) lastEventMs else System.currentTimeMillis()).toDouble(),
    "floorsAscended" to 0,
    "floorsDescended" to 0,
    "counterType" to counterType,
    "cadenceSpm" to null,
    "averageSpeedMps" to null,
  )

  fun onAppForeground() {
    if (!isRunning) return
    if (prefs.getBoolean(KEY_NEEDS_RECONCILE, false)) {
      prefs.edit().putBoolean(KEY_NEEDS_RECONCILE, false).apply()
      Log.i(TAG, "foreground: applying boot reconcile flag")
    }
    registerSensors(fastSample = true)
    reconcileHardwareCounter()
    emitUpdate("foreground_reconcile")
  }

  fun markReconcileOnBoot() {
    if (!isRunning) return
    prefs.edit().putBoolean(KEY_NEEDS_RECONCILE, true).apply()
    reconcileHardwareCounter()
    emitUpdate("boot_reconcile")
  }

  fun getDiagnostics(): Map<String, Any?> {
    val oem = OemProfiles
    return mapOf(
      "manufacturer" to Build.MANUFACTURER,
      "model" to Build.MODEL,
      "platform" to "android",
      "counterType" to counterType,
      "isRunning" to isRunning,
      "hasStepCounter" to (stepCounter != null),
      "hasStepDetector" to (stepDetector != null),
      "hasAccelerometerFallback" to (accelerometer != null && stepCounter == null && stepDetector == null),
      "oemRestrictionLevel" to oem.restrictionLevel().name.lowercase(),
      "oemAggressiveBackground" to oem.hasAggressiveBackgroundKill(),
      "oemSettingsLabel" to oem.oemSettingsLabel(),
      "oemPedometerNote" to oem.pedometerRationale(),
      "sessionSteps" to sessionSteps,
      "needsReconcile" to prefs.getBoolean(KEY_NEEDS_RECONCILE, false),
    )
  }

  // ─── Sensor registration ───────────────────────────────────────────────────

  private fun registerSensors(fastSample: Boolean = false) {
    unregisterSensors()
    val rate = when {
      fastSample && OemProfiles.prefersFastSensorSampling() -> SensorManager.SENSOR_DELAY_GAME
      fastSample -> SensorManager.SENSOR_DELAY_UI
      else -> SensorManager.SENSOR_DELAY_NORMAL
    }
    val registered = when {
      stepCounter != null -> sensorManager.registerListener(this, stepCounter, rate)
      stepDetector != null -> sensorManager.registerListener(this, stepDetector, rate)
      accelerometer != null -> sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
      else -> false
    }
    if (!registered) {
      Log.w(TAG, "sensor_register_failed type=$counterType")
    }
  }

  private fun unregisterSensors() {
    sensorManager.unregisterListener(this)
  }

  override fun onSensorChanged(event: SensorEvent) {
    if (!isRunning) return
    when (event.sensor.type) {
      Sensor.TYPE_STEP_COUNTER -> handleStepCounter(event.values[0])
      Sensor.TYPE_STEP_DETECTOR -> handleStepDetector()
      Sensor.TYPE_ACCELEROMETER -> handleAccelerometer(event.values)
    }
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

  private fun handleStepCounter(raw: Float) {
    if (!raw.isFinite()) return

    if (baselineCounter == null) {
      baselineCounter = raw
      lastRawCounter = raw
      persistSession()
      return
    }

    val last = lastRawCounter ?: raw
    // Reboot / sensor reset: counter wrapped or decreased
    if (raw < last) {
      Log.i(TAG, "step_counter_reset raw=$raw last=$last — re-baselining")
      baselineCounter = raw
      lastRawCounter = raw
      persistSession()
      emitUpdate("counter_reset")
      return
    }

    val delta = (raw - (baselineCounter ?: raw)).toInt().coerceAtLeast(0)
    if (delta > sessionSteps) {
      sessionSteps = delta
      sessionDistanceM = estimateDistance(sessionSteps)
      lastEventMs = System.currentTimeMillis()
      lastRawCounter = raw
      persistSession()
      emitUpdate("live")
    }
  }

  private fun reconcileHardwareCounter() {
    stepCounter ?: return
    if (baselineCounter != null && lastRawCounter != null) {
      val raw = lastRawCounter!!
      if (raw.isFinite() && raw >= (baselineCounter ?: raw)) {
        val delta = (raw - baselineCounter!!).toInt().coerceAtLeast(0)
        if (delta > sessionSteps) {
          sessionSteps = delta
          sessionDistanceM = estimateDistance(sessionSteps)
          lastEventMs = System.currentTimeMillis()
          persistSession()
        }
      }
    }
  }

  private fun handleStepDetector() {
    val now = System.currentTimeMillis()
    if (now - lastStepTs < minStepIntervalMs) return
    lastStepTs = now
    sessionSteps += 1
    sessionDistanceM = estimateDistance(sessionSteps)
    lastEventMs = now
    persistSession()
    emitUpdate("live")
  }

  private fun handleAccelerometer(values: FloatArray) {
    if (stepCounter != null || stepDetector != null) return
    val magnitude = sqrt(
      (values[0] * values[0] + values[1] * values[1] + values[2] * values[2]).toDouble(),
    )
    val now = System.currentTimeMillis()

    if (!accelPeak && magnitude > accelThreshold && magnitude > accelLast) {
      accelPeak = true
    } else if (accelPeak && magnitude < accelThreshold * 0.92) {
      if (now - lastStepTs >= minStepIntervalMs) {
        lastStepTs = now
        sessionSteps += 1
        sessionDistanceM = estimateDistance(sessionSteps)
        lastEventMs = now
        persistSession()
        emitUpdate("live")
      }
      accelPeak = false
    }
    accelLast = magnitude
  }

  private fun estimateDistance(steps: Int): Double = steps * 0.762 // ~avg stride 76cm

  private fun emitUpdate(source: String) {
    val payload = snapshot().toMutableMap()
    payload["source"] = source
    listener?.onPedometerUpdate(payload)
  }

  private fun persistSession() {
    if (!isRunning || sessionId == null) return
    prefs.edit()
      .putString("${KEY_SESSION}_id", sessionId)
      .putLong("${KEY_SESSION}_start", sessionStartMs)
      .putInt("${KEY_SESSION}_steps", sessionSteps)
      .putFloat("${KEY_SESSION}_baseline", baselineCounter ?: -1f)
      .putFloat("${KEY_SESSION}_lastRaw", lastRawCounter ?: -1f)
      .putString("${KEY_SESSION}_type", counterType)
      .putBoolean("${KEY_SESSION}_running", true)
      .apply()
  }

  private fun clearPersistedSession() {
    prefs.edit()
      .remove("${KEY_SESSION}_id")
      .remove("${KEY_SESSION}_start")
      .remove("${KEY_SESSION}_steps")
      .remove("${KEY_SESSION}_baseline")
      .remove("${KEY_SESSION}_lastRaw")
      .remove("${KEY_SESSION}_type")
      .putBoolean("${KEY_SESSION}_running", false)
      .apply()
  }

  private fun restorePersistedSession() {
    if (!prefs.getBoolean("${KEY_SESSION}_running", false)) return
    sessionId = prefs.getString("${KEY_SESSION}_id", null)
    sessionStartMs = prefs.getLong("${KEY_SESSION}_start", 0L)
    sessionSteps = prefs.getInt("${KEY_SESSION}_steps", 0)
    val base = prefs.getFloat("${KEY_SESSION}_baseline", -1f)
    val last = prefs.getFloat("${KEY_SESSION}_lastRaw", -1f)
    if (base >= 0) baselineCounter = base
    if (last >= 0) lastRawCounter = last
    counterType = prefs.getString("${KEY_SESSION}_type", "STEP_COUNTER") ?: "STEP_COUNTER"
    isRunning = true
    if (prefs.getBoolean(KEY_NEEDS_RECONCILE, false)) {
      Log.i(TAG, "restored session with pending boot reconcile")
    }
  }
}
