package com.fitnessgeolocation

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener

class FitnessGeolocationModule(private val reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext),
  LocationEngine.Listener,
  PermissionListener,
  LifecycleEventListener {

  companion object {
    const val NAME = "FitnessGeolocation"
  }

  private val engine = LocationEngine.getInstance(reactContext)
  private val debugMonitor = DebugMonitor(reactContext)
  private var authPromise: Promise? = null
  private var pendingAuthLevel: String = "whenInUse"
  private var awaitingBackground = false
  private var isInBackground = false
  private var motionEngineStarted = false
  private val pedometerEngine = PedometerEngine.getInstance(reactContext)

  private companion object {
    private const val REQUEST_FINE = 1001
    private const val REQUEST_BACKGROUND = 1002
    private const val TAG = "FitnessGeoModule"
  }

  init {
    reactContext.addLifecycleEventListener(this)
    engine.addListener(this)
    pedometerEngine.listener = object : PedometerEngine.Listener {
      override fun onPedometerUpdate(payload: Map<String, Any?>) {
        sendEvent("pedometerUpdate", Arguments.makeNativeMap(payload))
      }
    }
    debugMonitor.delegate = object : DebugMonitorDelegate {
      override fun onEnabledChange(enabled: Boolean) {
        val map = Arguments.createMap()
        map.putBoolean("enabled", enabled)
        sendEvent("debugEnabledChange", map)
      }

      override fun onMotionState(state: Map<String, Any?>) {
        sendEvent("debugMotionState", Arguments.makeNativeMap(state))
      }

      override fun onHeartbeatEvent(event: Map<String, Any?>) {
        sendEvent("debugHeartbeat", Arguments.makeNativeMap(event))
      }

      override fun onLifecycleEvent(event: Map<String, Any?>) {
        sendEvent("debugLifecycle", Arguments.makeNativeMap(event))
      }
    }
  }

  override fun getName(): String = NAME

  @ReactMethod
  fun addListener(eventName: String) {}

  @ReactMethod
  fun removeListeners(count: Int) {}

  private fun sendEvent(event: String, params: WritableMap?) {
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(event, params)
  }

  private fun hasFineLocation(): Boolean =
    ContextCompat.checkSelfPermission(reactContext, Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED

  private fun hasBackgroundLocation(): Boolean {
    if (Build.VERSION.SDK_INT < 29) return hasFineLocation()
    return ContextCompat.checkSelfPermission(
      reactContext, Manifest.permission.ACCESS_BACKGROUND_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
  }

  // ─── Geolocation ───────────────────────────────────────────────────────────

  @ReactMethod
  fun getCurrentPosition(options: ReadableMap, promise: Promise) {
    if (!hasFineLocation()) {
      promise.reject("PERMISSION_DENIED", "Location permission not granted")
      return
    }
    engine.getCurrentPosition(options) { result ->
      result.onSuccess { promise.resolve(it.toPositionMap()) }
        .onFailure { promise.reject("POSITION_UNAVAILABLE", it.message, it) }
    }
  }

  @ReactMethod
  fun watchPosition(options: ReadableMap): Int {
    val watchId = engine.watchPosition(options)
    startForegroundTrackingService()
    return watchId
  }

  @ReactMethod
  fun clearWatch(watchId: Int) {
    engine.clearWatch(watchId)
    if (engine.activeWatchCount() == 0 && engine.isTimeBasedInactive()) stopForegroundTrackingService()
  }

  @ReactMethod
  fun stopLocationObserving() {
    engine.stopObserving()
    stopForegroundTrackingService()
  }

  @ReactMethod
  fun getPendingForJs(limit: Int, promise: Promise) {
    promise.resolve(engine.getPendingForJs(limit))
  }

  @ReactMethod
  fun markDelivered(ids: ReadableArray, promise: Promise) {
    val list = (0 until ids.size()).map { ids.getString(it)!! }
    promise.resolve(engine.markDelivered(list))
  }

  @ReactMethod
  fun purgeDelivered(promise: Promise) {
    promise.resolve(engine.purgeDelivered())
  }

  @ReactMethod
  fun getQueueSize(promise: Promise) {
    promise.resolve(engine.pendingCount())
  }

  @ReactMethod
  fun getDiagnostics(promise: Promise) {
    promise.resolve(engine.getDiagnostics())
  }

  // ─── Authorization ────────────────────────────────────────────────────────

  @ReactMethod
  fun setConfiguration(config: ReadableMap, promise: Promise) {
    val editor = reactContext
      .getSharedPreferences("fitness_geolocation", android.content.Context.MODE_PRIVATE)
      .edit()

    if (config.hasKey("notificationTitle")) {
      editor.putString("notification_title", config.getString("notificationTitle"))
    }
    if (config.hasKey("notificationText")) {
      editor.putString("notification_text", config.getString("notificationText"))
    }
    if (config.hasKey("trackingMode")) {
      config.getString("trackingMode")?.let { engine.setTrackingMode(it) }
    }
    editor.apply()
    promise.resolve(null)
  }

  @ReactMethod
  fun requestAuthorization(level: String, promise: Promise) {
    pendingAuthLevel = level
    authPromise = promise

    if (hasFineLocation() && (level != "always" || hasBackgroundLocation())) {
      promise.resolve("granted")
      authPromise = null
      return
    }

    val activity = reactContext.currentActivity as? PermissionAwareActivity
    if (activity == null) {
      promise.resolve(if (hasFineLocation()) "granted" else "denied")
      authPromise = null
      return
    }

    if (!hasFineLocation()) {
      activity.requestPermissions(
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
        REQUEST_FINE,
        this,
      )
      return
    }

    if (level == "always" && Build.VERSION.SDK_INT >= 29 && !hasBackgroundLocation()) {
      awaitingBackground = true
      activity.requestPermissions(
        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
        REQUEST_BACKGROUND,
        this,
      )
      return
    }

    promise.resolve("granted")
    authPromise = null
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<String>,
    grantResults: IntArray,
  ): Boolean {
    val promise = authPromise ?: return false

    when (requestCode) {
      REQUEST_FINE -> {
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (!granted) {
          promise.resolve("denied")
          authPromise = null
          emitAuthChange("denied")
          return true
        }
        emitAuthChange("granted")
        if (pendingAuthLevel == "always" && Build.VERSION.SDK_INT >= 29 && !hasBackgroundLocation()) {
          awaitingBackground = true
          val activity = reactContext.currentActivity as? PermissionAwareActivity
          activity?.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            REQUEST_BACKGROUND,
            this,
          ) ?: run {
            promise.resolve("granted")
            authPromise = null
          }
          return true
        }
        promise.resolve("granted")
        authPromise = null
      }
      REQUEST_BACKGROUND -> {
        awaitingBackground = false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        promise.resolve(if (granted) "granted" else "foreground_only")
        authPromise = null
        emitAuthChange(if (granted) "granted" else "foreground_only")
      }
    }
    return true
  }

  private fun emitAuthChange(status: String) {
    val map = Arguments.createMap()
    map.putString("status", status)
    sendEvent("authorizationChange", map)
  }

  // ─── Battery Optimization ──────────────────────────────────────────────────

  @ReactMethod
  fun requestBatteryOptimizationPermission(promise: Promise) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      promise.resolve(true)
      return
    }

    val pm = reactContext.getSystemService(Context.POWER_SERVICE) as PowerManager
    if (pm.isIgnoringBatteryOptimizations(reactContext.packageName)) {
      promise.resolve(true)
      return
    }

    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
      data = Uri.parse("package:${reactContext.packageName}")
      flags = Intent.FLAG_ACTIVITY_NEW_TASK
    }
    try {
      reactContext.startActivity(intent)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  @ReactMethod
  fun isIgnoringBatteryOptimizations(promise: Promise) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      promise.resolve(true)
      return
    }
    val pm = reactContext.getSystemService(Context.POWER_SERVICE) as PowerManager
    promise.resolve(pm.isIgnoringBatteryOptimizations(reactContext.packageName))
  }

  @ReactMethod
  fun openOemBatterySettings(promise: Promise) {
    val manufacturer = Build.MANUFACTURER.lowercase()
    val intent = Intent().apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK

      when {
        manufacturer.contains("xiaomi") -> {
          component = ComponentName(
            "com.miui.securitycenter",
            "com.miui.optimizecenter.SettingsActivity"
          )
        }
        manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
          component = ComponentName(
            "com.huawei.systemmanager",
            "com.huawei.systemmanager.optimize.process.ProtectActivity"
          )
        }
        manufacturer.contains("oppo") -> {
          action = "oppo.intent.action.ANTI_STARTUP_ACTION"
        }
        manufacturer.contains("vivo") -> {
          component = ComponentName(
            "com.iqoo.secure",
            "com.iqoo.secure.ui.softmanager.SoftManagerActivity"
          )
        }
        manufacturer.contains("oneplus") -> {
          component = ComponentName(
            "com.oneplus.security",
            "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
          )
        }
        manufacturer.contains("samsung") -> {
          action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
          data = Uri.parse("package:${reactContext.packageName}")
        }
        manufacturer.contains("realme") -> {
          component = ComponentName(
            "com.coloros.oppoguardelf",
            "com.coloros.oppoguardelf.activity.SystemManagerActivity"
          )
        }
        else -> {
          action = Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
        }
      }
    }

    try {
      if (intent.component != null || intent.action != null) {
        reactContext.startActivity(intent)
      }
      promise.resolve(true)
    } catch (e: Exception) {
      // Fallback: open battery saver settings
      try {
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        reactContext.startActivity(fallback)
      } catch (_: Exception) {}
      promise.resolve(false)
    }
  }

  // ─── Motion ────────────────────────────────────────────────────────────────

  @ReactMethod
  fun configureAutoPause(enabled: Boolean, delaySeconds: Double, promise: Promise) {
    engine.configureMotionAutoPause(enabled, delaySeconds.toLong(), 5)
    promise.resolve(null)
  }

  @ReactMethod
  fun startMotionTracking(includePedometer: Boolean, promise: Promise) {
    if (!motionEngineStarted) {
      val motionEngine = MotionEngine(reactContext, object : MotionEngine.Listener {
        override fun onActivityChange(activity: String, confidence: Int) {
          engine.feedMotionActivity(activity)
          val map = Arguments.createMap()
          map.putString("activity", activity)
          map.putDouble("confidence", confidence.toDouble())
          sendEvent("motionActivity", map)
        }

        override fun onAutoPause() {
          engine.onStationaryAutoPause()
          val map = Arguments.createMap()
          map.putString("reason", "stationary")
          sendEvent("autoPause", map)
        }

        override fun onAutoResume() {
          engine.onMotionResume()
          val map = Arguments.createMap()
          map.putString("reason", "movement")
          sendEvent("autoResume", map)
        }
      })
      motionEngine.start()
      motionEngineStarted = true
    }
    promise.resolve(null)
  }

  @ReactMethod
  fun stopMotionTracking(promise: Promise) {
    // MotionEngine lifecycle managed by module — kept alive while tracking
    promise.resolve(null)
  }

  @ReactMethod
  fun setTrackingMode(mode: String, promise: Promise) {
    engine.setTrackingMode(mode)
    promise.resolve(null)
  }

  @ReactMethod
  fun setActivityPaused(paused: Boolean, promise: Promise) {
    engine.setPaused(paused)
    promise.resolve(null)
  }

  @ReactMethod
  fun getEngineState(promise: Promise) {
    promise.resolve(engine.getEngineState())
  }

  @ReactMethod
  fun getAuthorizationStatus(promise: Promise) {
    val fine = hasFineLocation()
    val background = hasBackgroundLocation()
    val map = Arguments.createMap()
    map.putString("status", if (fine) "granted" else "denied")
    map.putBoolean("always", fine && background)
    promise.resolve(map)
  }

  // ─── Time-Based Tracking ──────────────────────────────────────────────────

  @ReactMethod
  fun startTimeBasedTracking(options: ReadableMap): Int {
    val watchId = engine.startTimeBasedTracking(options)
    startForegroundTrackingService()
    return watchId
  }

  @ReactMethod
  fun stopTimeBasedTracking(watchId: Int) {
    engine.stopTimeBasedTracking(watchId)
    if (engine.activeWatchCount() == 0) stopForegroundTrackingService()
  }

  @ReactMethod
  fun pauseTimeBasedTracking(watchId: Int) {
    engine.pauseTimeBasedTracking(watchId)
  }

  @ReactMethod
  fun resumeTimeBasedTracking(watchId: Int) {
    engine.resumeTimeBasedTracking(watchId)
  }

  @ReactMethod
  fun setTimeBasedInterval(watchId: Int, intervalMs: Double) {
    engine.setTimeBasedInterval(watchId, intervalMs)
  }

  // ─── Session Management ────────────────────────────────────────────────────

  @ReactMethod
  fun createSession(name: String, activityType: String, extras: String?, promise: Promise) {
    val id = engine.createSession(name, activityType, extras)
    promise.resolve(id)
  }

  @ReactMethod
  fun endSession(sessionId: String, data: ReadableMap, promise: Promise) {
    val map = data.toHashMap()
    engine.endSession(sessionId, map)
    promise.resolve(null)
  }

  @ReactMethod
  fun discardSession(sessionId: String, promise: Promise) {
    engine.discardSession(sessionId)
    promise.resolve(null)
  }

  @ReactMethod
  fun getPendingSessions(promise: Promise) {
    val sessions = engine.getUnuploadedSessions()
    val arr = Arguments.createArray()
    sessions.forEach { arr.pushMap(Arguments.makeNativeMap(it)) }
    promise.resolve(arr)
  }

  @ReactMethod
  fun getSessionForUpload(sessionId: String, promise: Promise) {
    val session = engine.getSessionForUpload(sessionId)
    if (session != null) {
      promise.resolve(Arguments.makeNativeMap(session))
    } else {
      promise.reject("NOT_FOUND", "Session not found")
    }
  }

  @ReactMethod
  fun markSessionUploaded(sessionId: String, promise: Promise) {
    engine.markSessionUploaded(sessionId)
    promise.resolve(null)
  }

  // ─── Odometer ──────────────────────────────────────────────────────────────

  @ReactMethod
  fun getOdometer(promise: Promise) {
    promise.resolve(engine.getOdometer())
  }

  @ReactMethod
  fun resetOdometer(promise: Promise) {
    engine.resetOdometer()
    promise.resolve(null)
  }

  @ReactMethod
  fun setOdometer(value: Double, promise: Promise) {
    engine.setOdometer(value)
    promise.resolve(null)
  }

  // ─── Diagnostics & Logging ─────────────────────────────────────────────────

  @ReactMethod
  fun devLog(level: String, tag: String, message: String, data: ReadableMap?) {
    engine.devLog(level, tag, message, data?.toHashMap() ?: emptyMap())
  }

  // ─── Foreground Service ────────────────────────────────────────────────────

  private fun startForegroundTrackingService() {
    if (!hasFineLocation()) return
    val intent = Intent(reactContext, FitnessLocationService::class.java)
      .setAction(FitnessLocationService.ACTION_START)
    PlatformCompat.startLocationForegroundService(reactContext, intent)
  }

  private fun stopForegroundTrackingService() {
    reactContext.stopService(Intent(reactContext, FitnessLocationService::class.java))
  }

  // ─── LocationEngine.Listener ───────────────────────────────────────────────

  override fun onLocationPersisted(location: StoredLocation, watchIds: List<Int>, deliverLive: Boolean) {
    // Feed speed into debug monitor for motion state machine
    debugMonitor.feedSpeed(location.speed)
    // Feed speed into GPS resume detection
    engine.feedSpeedForGpsResume(location.speed)

    if (deliverLive && !isInBackground) {
      // App is in foreground — deliver live to JS
      for (watchId in watchIds) {
        val event = Arguments.createMap()
        event.putInt("watchId", watchId)
        event.putMap("position", location.toPositionMap())
        event.putString("nativeId", location.id)
        sendEvent("watchPosition", event)
      }
    } else {
      // App is in background/killed — queue for headless task
      HeadlessTaskManager.queueEvent(
        reactContext,
        "location",
        mapOf(
          "latitude" to location.latitude,
          "longitude" to location.longitude,
          "accuracy" to location.accuracy.toDouble(),
          "speed" to location.speed.toDouble(),
          "altitude" to location.altitude,
          "timestamp" to location.timestamp.toDouble(),
          "distanceFromPrev" to location.distanceFromPrev,
          "cumulativeDistance" to location.cumulativeDistance,
          "signalStrength" to location.signalStrength,
        ),
      )
    }
  }

  override fun onLocationError(message: String, watchIds: List<Int>) {
    if (isInBackground) {
      HeadlessTaskManager.queueEvent(reactContext, "location_error", mapOf("message" to message))
      return
    }
    for (watchId in watchIds) {
      val event = Arguments.createMap()
      event.putInt("watchId", watchId)
      val error = Arguments.createMap()
      error.putInt("code", 2)
      error.putString("message", message)
      event.putMap("error", error)
      sendEvent("watchPosition", event)
    }
  }

  override fun onEnterForeground() {
    val map = Arguments.createMap()
    map.putInt("pending", engine.pendingCount())
    sendEvent("foregroundSync", map)
  }

  override fun onDiagnostic(event: WritableMap) {
    when (event.getString("event")) {
      "geofence" -> sendEvent("geofence", event)
      "geofencesChange" -> sendEvent("geofencesChange", event)
      "httpResponse" -> sendEvent("httpResponse", event)
      "location" -> sendEvent("location", event)
      "motionchange" -> sendEvent("motionchange", event)
      "heartbeat" -> sendEvent("heartbeat", event)
      "schedule" -> sendEvent("schedule", event)
      "enabledchange" -> sendEvent("enabledchange", event)
      else -> sendEvent("diagnostic", event)
    }
  }

  override fun onTimeBasedTick(location: StoredLocation) {
    if (isInBackground) {
      HeadlessTaskManager.queueEvent(
        reactContext,
        "timebased_tick",
        mapOf(
          "latitude" to location.latitude,
          "longitude" to location.longitude,
          "accuracy" to location.accuracy.toDouble(),
          "speed" to location.speed.toDouble(),
          "timestamp" to location.timestamp.toDouble(),
          "cumulativeDistance" to location.cumulativeDistance,
          "gpsStrength" to location.signalStrength,
        ),
      )
      return
    }
    sendEvent("timeBasedTick", location.toTimeBasedMap())
  }

  override fun onGpsStrengthChange(strength: String, accuracy: Double) {
    // Forwarded via timeBasedTick data
  }

  override fun onStationaryChange(isStationary: Boolean) {
    // Forwarded via timeBasedTick data
  }

  // ─── HTTP Sync ─────────────────────────────────────────────────────────────

  @ReactMethod
  fun configureHttp(config: ReadableMap) {
    val map = config.toHashMap()
    engine.httpUrl = map["url"] as? String
    engine.httpMethod = map["method"] as? String ?: "POST"
    @Suppress("UNCHECKED_CAST")
    engine.httpHeaders = (map["headers"] as? Map<String, String>) ?: emptyMap()
    engine.httpAutoSync = map["autoSync"] as? Boolean ?: true
    engine.httpBatchSync = map["batchSync"] as? Boolean ?: true
    engine.httpBatchSize = (map["batchSize"] as? Double)?.toInt() ?: 100
    engine.httpRetryCount = (map["retryCount"] as? Double)?.toInt() ?: 3
    engine.httpConfigured = true
    Log.d(TAG, "http_configured: ${map["url"]}")
  }

  @ReactMethod
  fun httpSync(promise: Promise) {
    promise.resolve(engine.httpSync())
  }

  @ReactMethod
  fun addHttpListener() {
    engine.httpListenerEnabled = true
  }

  @ReactMethod
  fun removeHttpListener() {
    engine.httpListenerEnabled = false
  }

  @ReactMethod
  fun destroyLocations(promise: Promise) {
    engine.clearAll()
    promise.resolve(null)
  }

  @ReactMethod
  fun getCount(promise: Promise) {
    promise.resolve(engine.pendingCount())
  }

  // ─── Geofencing ────────────────────────────────────────────────────────────

  @ReactMethod
  fun addGeofence(geofence: ReadableMap, promise: Promise) {
    val map = geofence.toHashMap()
    promise.resolve(engine.addGeofence(map))
  }

  @ReactMethod
  fun addGeofences(geofences: ReadableArray, promise: Promise) {
    val list = (0 until geofences.size()).mapNotNull { geofences.getMap(it)?.toHashMap() }
    promise.resolve(engine.addGeofences(list))
  }

  @ReactMethod
  fun removeGeofence(identifier: String, promise: Promise) {
    promise.resolve(engine.removeGeofence(identifier))
  }

  @ReactMethod
  fun removeGeofences(identifiers: ReadableArray?, promise: Promise) {
    val ids = if (identifiers != null) {
      (0 until identifiers.size()).mapNotNull { identifiers.getString(it) }
    } else {
      null
    }
    promise.resolve(engine.removeGeofences(ids))
  }

  @ReactMethod
  fun getGeofences(promise: Promise) {
    val geofences = engine.getGeofences()
    val arr = Arguments.createArray()
    geofences.forEach { arr.pushMap(Arguments.makeNativeMap(it)) }
    promise.resolve(arr)
  }

  @ReactMethod
  fun geofenceExists(identifier: String, promise: Promise) {
    promise.resolve(engine.geofenceExists(identifier))
  }

  // ─── Debug Monitor ────────────────────────────────────────────────────────

  @ReactMethod
  fun setDebugMonitorConfig(config: ReadableMap, promise: Promise) {
    debugMonitor.configure(config.toHashMap())
    promise.resolve(null)
  }

  @ReactMethod
  fun configureLogger(config: ReadableMap, promise: Promise) {
    val map = config.toHashMap()
    val level = (map["logLevel"] as? Number)?.toInt() ?: 0
    val maxDays = (map["logMaxDays"] as? Number)?.toInt() ?: 3
    engine.configureLogger(level, maxDays)
    promise.resolve(null)
  }

  @ReactMethod
  fun getDebugMotionState(promise: Promise) {
    promise.resolve(Arguments.makeNativeMap(debugMonitor.getMotionState()))
  }

  // ─── Provider Events ──────────────────────────────────────────────────────

  @ReactMethod
  fun getProviderState(promise: Promise) {
    promise.resolve(engine.getProviderState())
  }

  @ReactMethod
  fun isPowerSaveMode(promise: Promise) {
    promise.resolve(engine.isPowerSaveMode())
  }

  @ReactMethod
  fun getSensors(promise: Promise) {
    promise.resolve(engine.getSensors())
  }

  @ReactMethod
  fun getDeviceInfo(promise: Promise) {
    val map = Arguments.createMap()
    map.putString("manufacturer", Build.MANUFACTURER)
    map.putString("model", Build.MODEL)
    map.putString("version", Build.VERSION.RELEASE)
    map.putString("platform", "android")
    map.putString("framework", "React Native")
    promise.resolve(map)
  }

  // ─── Background Engine API ───────────────────────────────────────────────────────

  @ReactMethod
  fun ready(config: ReadableMap, promise: Promise) {
    val map = config.toHashMap()
    @Suppress("UNCHECKED_CAST")
    if (map["schedule"] is List<*>) {
      engine.scheduleRecords = (map["schedule"] as List<*>).mapNotNull { it as? String }
    }
    engine.httpAutoSyncThreshold = (map["autoSyncThreshold"] as? Double)?.toInt() ?: 0
    promise.resolve(Arguments.makeNativeMap(engine.ready(map)))
  }

  @ReactMethod
  fun setConfig(config: ReadableMap, promise: Promise) {
    engine.mergeConfig(config.toHashMap())
    promise.resolve(Arguments.makeNativeMap(engine.getState()))
  }

  @ReactMethod
  fun getState(promise: Promise) {
    promise.resolve(Arguments.makeNativeMap(engine.getState()))
  }

  @ReactMethod
  fun start(promise: Promise) {
    engine.startEngine()
    startForegroundTrackingService()
    promise.resolve(Arguments.makeNativeMap(engine.getState()))
  }

  @ReactMethod
  fun stop(promise: Promise) {
    engine.stopEngine()
    stopForegroundTrackingService()
    promise.resolve(Arguments.makeNativeMap(engine.getState()))
  }

  @ReactMethod
  fun changePace(moving: Boolean, promise: Promise) {
    engine.changePace(moving)
    promise.resolve(null)
  }

  @ReactMethod
  fun startSchedule(promise: Promise) {
    engine.startSchedule()
    promise.resolve(null)
  }

  @ReactMethod
  fun stopSchedule(promise: Promise) {
    engine.stopSchedule()
    promise.resolve(null)
  }

  @ReactMethod
  fun startGeofences(promise: Promise) {
    engine.startGeofencesMode()
    promise.resolve(null)
  }

  @ReactMethod
  fun sync(promise: Promise) {
    promise.resolve(Arguments.fromList(engine.httpSyncAll()))
  }

  @ReactMethod
  fun getLocations(promise: Promise) {
    promise.resolve(Arguments.fromList(engine.getLocations()))
  }

  @ReactMethod
  fun destroyLocation(uuid: String, promise: Promise) {
    promise.resolve(engine.destroyLocation(uuid))
  }

  @ReactMethod
  fun insertLocation(params: ReadableMap, promise: Promise) {
    promise.resolve(engine.insertLocation(params.toHashMap()))
  }

  @ReactMethod
  fun getLog(query: ReadableMap?, promise: Promise) {
    val q = query?.toHashMap() ?: emptyMap()
    promise.resolve(engine.getNativeLog(q))
  }

  @ReactMethod
  fun destroyLog(promise: Promise) {
    engine.destroyNativeLog()
    promise.resolve(null)
  }

  @ReactMethod
  fun log(level: String, message: String, promise: Promise) {
    engine.nativeLog(level, message)
    promise.resolve(null)
  }

  @ReactMethod
  fun uploadLog(url: String, query: ReadableMap?, promise: Promise) {
    promise.resolve(engine.uploadLog(url, query?.toHashMap() ?: emptyMap()))
  }

  @ReactMethod
  fun requestTemporaryFullAccuracy(purpose: String, promise: Promise) {
    promise.reject("UNSUPPORTED", "requestTemporaryFullAccuracy is iOS-only")
  }

  @ReactMethod
  fun reset(promise: Promise) {
    engine.stopEngine()
    engine.clearAll()
    engine.destroyNativeLog()
    promise.resolve(null)
  }

  @ReactMethod
  fun setLiveActivityEnabled(enabled: Boolean) {
    engine.setLiveActivityEnabled(enabled)
  }

  @ReactMethod
  fun getLiveActivityEnabled(promise: Promise) {
    promise.resolve(engine.isLiveActivityEnabled())
  }

  // ─── Pedometer (passive, no notification) ─────────────────────────────────

  @ReactMethod
  fun pedometerIsSupported(promise: Promise) {
    val map = Arguments.createMap()
    map.putBoolean("supported", pedometerEngine.isSupported())
    map.putBoolean("granted", pedometerEngine.isAuthorized())
    map.putString("status", pedometerEngine.authorizationStatus())
    map.putString("platform", "android")
    promise.resolve(map)
  }

  @ReactMethod
  fun pedometerStart(sessionId: String?, promise: Promise) {
    try {
      val snap = pedometerEngine.start(sessionId)
      promise.resolve(Arguments.makeNativeMap(snap))
    } catch (e: SecurityException) {
      promise.reject("PERMISSION_DENIED", e.message, e)
    } catch (e: Exception) {
      promise.reject("PEDOMETER_ERROR", e.message, e)
    }
  }

  @ReactMethod
  fun pedometerStop(promise: Promise) {
    promise.resolve(Arguments.makeNativeMap(pedometerEngine.stop()))
  }

  @ReactMethod
  fun pedometerGetSnapshot(promise: Promise) {
    promise.resolve(Arguments.makeNativeMap(pedometerEngine.snapshot()))
  }

  @ReactMethod
  fun pedometerOnAppForeground() {
    pedometerEngine.onAppForeground()
  }

  @ReactMethod
  fun pedometerGetDiagnostics(promise: Promise) {
    val map = Arguments.createMap()
    val diag = pedometerEngine.getDiagnostics()
    for ((k, v) in diag) {
      when (v) {
        null -> map.putNull(k)
        is Boolean -> map.putBoolean(k, v)
        is Int -> map.putInt(k, v)
        is Double -> map.putDouble(k, v)
        is Float -> map.putDouble(k, v.toDouble())
        is String -> map.putString(k, v)
        else -> map.putString(k, v.toString())
      }
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      map.putBoolean(
        "batteryOptimizationExempt",
        BatteryOptimizationManager.isIgnoringBatteryOptimizations(reactContext),
      )
    } else {
      map.putBoolean("batteryOptimizationExempt", true)
    }
    map.putBoolean("powerSaveMode", engine.isPowerSaveMode())
    promise.resolve(map)
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  override fun onHostResume() {
    isInBackground = false
    engine.onHostResume()
    pedometerEngine.onAppForeground()
  }

  override fun onHostPause() {
    isInBackground = true
    engine.onHostPause()
  }

  override fun onHostDestroy() {
    isInBackground = true
    engine.removeListener(this)
  }

  override fun invalidate() {
    engine.removeListener(this)
    super.invalidate()
  }
}

/** Extension to check if time-based tracking is not active */
fun LocationEngine.isTimeBasedInactive(): Boolean {
  return true // The module handles this check in combination with activeWatchCount
}
