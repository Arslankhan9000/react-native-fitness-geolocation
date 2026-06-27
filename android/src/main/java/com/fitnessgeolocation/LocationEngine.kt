package com.fitnessgeolocation

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.Manifest
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import com.google.android.gms.location.*

data class StoredLocation(
  val id: String,
  val latitude: Double,
  val longitude: Double,
  val accuracy: Float,
  val speed: Float,
  val heading: Float,
  val altitude: Double,
  val timestamp: Long,
  val sessionId: String,
  val deliveredToJs: Boolean = false,
  val motionState: String = "unknown",
  val signalStrength: String = "medium",
  val batteryLevel: Double = -1.0,
  val distanceFromPrev: Double = 0.0,
  val cumulativeDistance: Double = 0.0,
  val qualityJson: String? = null,
) {
  fun toPositionMap(): WritableMap {
    val coords = Arguments.createMap()
    coords.putDouble("latitude", latitude)
    coords.putDouble("longitude", longitude)
    if (altitude != 0.0) coords.putDouble("altitude", altitude) else coords.putNull("altitude")
    coords.putDouble("accuracy", accuracy.toDouble())
    if (heading > 0) coords.putDouble("heading", heading.toDouble()) else coords.putNull("heading")
    if (speed > 0) coords.putDouble("speed", speed.toDouble()) else coords.putNull("speed")
    coords.putNull("altitudeAccuracy")
    val map = Arguments.createMap()
    map.putMap("coords", coords)
    map.putDouble("timestamp", timestamp.toDouble())
    return map
  }

  fun toPayloadMap(): WritableMap {
    val map = Arguments.createMap()
    map.putString("id", id)
    map.putDouble("latitude", latitude)
    map.putDouble("longitude", longitude)
    map.putDouble("timestamp", timestamp.toDouble())
    map.putDouble("accuracy", accuracy.toDouble())
    map.putDouble("speed", speed.toDouble())
    map.putDouble("heading", heading.toDouble())
    map.putDouble("altitude", altitude)
    map.putDouble("distanceFromPrev", distanceFromPrev)
    map.putDouble("cumulativeDistance", cumulativeDistance)
    map.putString("gpsStrength", signalStrength)
    if (qualityJson != null) map.putString("quality", qualityJson) else map.putNull("quality")
    return map
  }

  fun toTimeBasedMap(): WritableMap {
    val map = Arguments.createMap()
    val coords = Arguments.createMap()
    coords.putDouble("latitude", latitude)
    coords.putDouble("longitude", longitude)
    if (altitude != 0.0) coords.putDouble("altitude", altitude) else coords.putNull("altitude")
    coords.putDouble("accuracy", accuracy.toDouble())
    if (heading > 0) coords.putDouble("heading", heading.toDouble()) else coords.putNull("heading")
    if (speed > 0) coords.putDouble("speed", speed.toDouble()) else coords.putNull("speed")
    map.putMap("coords", coords)
    map.putDouble("timestamp", timestamp.toDouble())
    map.putString("gpsStrength", signalStrength)
    map.putBoolean("isStationary", motionState == "stationary")
    map.putDouble("distanceFromPrev", distanceFromPrev)
    map.putDouble("cumulativeDistance", cumulativeDistance)
    map.putDouble("batteryLevel", batteryLevel)
    map.putString("motionState", motionState)
    return map
  }
}

enum class TrackingMode(val distanceM: Float, val priority: Int) {
  navigation(3f, Priority.PRIORITY_HIGH_ACCURACY),
  fitness(5f, Priority.PRIORITY_HIGH_ACCURACY),
  balanced(8f, Priority.PRIORITY_BALANCED_POWER_ACCURACY),
  low_power(15f, Priority.PRIORITY_LOW_POWER),
  stationary(25f, Priority.PRIORITY_LOW_POWER),
}

class LocationEngine private constructor(
  private val context: Context,
) {
  interface Listener {
    fun onLocationPersisted(location: StoredLocation, watchIds: List<Int>, deliverLive: Boolean)
    fun onLocationError(message: String, watchIds: List<Int>)
    fun onEnterForeground()
    fun onDiagnostic(event: WritableMap)
    fun onTimeBasedTick(location: StoredLocation)
    fun onGpsStrengthChange(strength: String, accuracy: Double)
    fun onStationaryChange(isStationary: Boolean)
  }

  companion object {
    @Volatile private var instance: LocationEngine? = null
    private const val TAG = "FitnessGeoEngine"

    fun getInstance(context: Context): LocationEngine {
      return instance ?: synchronized(this) {
        instance ?: LocationEngine(context.applicationContext).also { instance = it }
      }
    }
  }

  private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
  private val database = LocationDatabase(context)
  private val filter = LocationFilter()
  private val geofenceManager = GeofenceManager(context)
  private val scheduleManager = ScheduleManager()
  private val nativeLogger = NativeLogger(database)
  private val providerMonitor = ProviderMonitor(context)
  private var currentActivityType = "running"
  private val listeners = linkedSetOf<Listener>()
  private val diagnostics = ArrayDeque<Map<String, Any?>>()
  private val liveActivityManager = LiveActivityManager.getInstance(context)

  // Watch state
  private var callback: LocationCallback? = null
  private var isWatching = false
  private var isPaused = false
  private var mode = TrackingMode.fitness
  private val watchIds = mutableSetOf<Int>()
  private var nextWatchId = 1
  private var lastLocation: android.location.Location? = null
  private var intervalMs = 3000L
  private var fastestIntervalMs = 1000L
  private var distanceMeters = 5f
  private var highAccuracy = true

  // Time-based tracking state
  private var timeBasedWatchId: Int? = null
  private var timeBasedIntervalMs: Long = 3000
  private var timeBasedStationaryIntervalMs: Long = 30000
  private var timeBasedAdaptive: Boolean = true
  private var timeBasedMaxAccuracy: Float = 50f
  private var timeBasedPaused: Boolean = false
  private var timeBasedLastLocation: StoredLocation? = null
  private var timeBasedStationarySince: Long = 0
  private var timeBasedIsStationary: Boolean = false
  private var timeBasedHandler: android.os.Handler? = null
  private var timeBasedRunnable: Runnable? = null

  // Session state
  private var currentSessionId: String? = null
  private var currentSessionStartTime: Long = 0L
  private var cumulativeDistance: Double = 0.0
  private var lastProcessedLocation: Location? = null

  // Battery-conscious GPS management (GPS off when stationary, motion-triggered resume)
  private var gpsSuspended = false
  private var motionAutoPauseEnabled = true
  private var motionAutoResumeEnabled = true
  private var stopTimeoutMs: Long = 5 * 60 * 1000  // 5 min
  private var stationarySinceMs: Long = 0L
  private var stopTimerRunnable: Runnable? = null
  private val mainHandler = android.os.Handler(Looper.getMainLooper())

  private val prefs by lazy {
    context.getSharedPreferences("fitness_geolocation", Context.MODE_PRIVATE)
  }

  init {
    reconcileWatchStateOnColdLaunch()
  }

  // ─── Listener management ───────────────────────────────────────────────────

  fun addListener(listener: Listener) {
    synchronized(listeners) { listeners.add(listener) }
  }

  fun removeListener(listener: Listener) {
    synchronized(listeners) { listeners.remove(listener) }
  }

  private fun listenerSnapshot(): List<Listener> {
    return synchronized(listeners) { listeners.toList() }
  }

  private var hostInForeground = true

  private fun isAppActive(): Boolean = hostInForeground

  fun onHostResume() {
    hostInForeground = true
    Log.d(TAG, "foreground pending=${database.pendingCount()}")
    log("foreground", mapOf("pending" to database.pendingCount()))
    listenerSnapshot().forEach { it.onEnterForeground() }
  }

  fun onHostPause() {
    hostInForeground = false
  }

  // ─── Options ───────────────────────────────────────────────────────────────

  private fun applyOptions(options: ReadableMap?) {
    if (options == null) return
    if (options.hasKey("interval")) intervalMs = options.getDouble("interval").toLong().coerceAtLeast(500)
    if (options.hasKey("locationUpdateInterval")) {
      intervalMs = options.getDouble("locationUpdateInterval").toLong().coerceAtLeast(500)
    }
    if (options.hasKey("fastestInterval")) {
      fastestIntervalMs = options.getDouble("fastestInterval").toLong().coerceAtLeast(500)
    }
    if (options.hasKey("fastestLocationUpdateInterval")) {
      fastestIntervalMs = options.getDouble("fastestLocationUpdateInterval").toLong().coerceAtLeast(500)
    }
    if (options.hasKey("distanceFilter")) distanceMeters = options.getDouble("distanceFilter").toFloat()
    if (options.hasKey("enableHighAccuracy")) highAccuracy = options.getBoolean("enableHighAccuracy")
    if (options.hasKey("desiredAccuracy")) highAccuracy = options.getDouble("desiredAccuracy") <= 25.0
    if (options.hasKey("trackingMode")) {
      mode = TrackingMode.entries.find { it.name == options.getString("trackingMode") } ?: mode
    }
    if (!options.hasKey("distanceFilter")) distanceMeters = mode.distanceM
  }

  // ─── Single Position ───────────────────────────────────────────────────────

  @SuppressLint("MissingPermission")
  fun getCurrentPosition(options: ReadableMap?, onResult: (Result<StoredLocation>) -> Unit) {
    val maximumAge = if (options?.hasKey("maximumAge") == true) options.getDouble("maximumAge").toLong() else 0L
    lastLocation?.let { cached ->
      if (maximumAge <= 0 || (System.currentTimeMillis() - cached.time) <= maximumAge) {
        val stored = cached.toStored(delivered = true)
        database.insert(stored)
        onResult(Result.success(stored))
        return
      }
    }

    fusedClient.lastLocation.addOnSuccessListener { loc ->
      if (loc != null) {
        if (maximumAge <= 0 || (System.currentTimeMillis() - loc.time) <= maximumAge) {
          lastLocation = loc
          val stored = loc.toStored(delivered = true)
          database.insert(stored)
          onResult(Result.success(stored))
          return@addOnSuccessListener
        }
      }
      requestSingleUpdate(onResult)
    }.addOnFailureListener { requestSingleUpdate(onResult) }
  }

  @SuppressLint("MissingPermission")
  private fun requestSingleUpdate(onResult: (Result<StoredLocation>) -> Unit) {
    val request = LocationRequest.Builder(
      if (highAccuracy) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY,
      1000,
    ).setMaxUpdates(1).build()

    val singleCallback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        fusedClient.removeLocationUpdates(this)
        val loc = result.lastLocation
        if (loc == null) {
          onResult(Result.failure(Exception("No location available")))
          return
        }
        lastLocation = loc
        val stored = loc.toStored(delivered = true)
        database.insert(stored)
        onResult(Result.success(stored))
      }
    }
    try {
      fusedClient.requestLocationUpdates(request, singleCallback, Looper.getMainLooper())
    } catch (e: SecurityException) {
      onResult(Result.failure(e))
    }
  }

  // ─── Watch Position (Distance-Based) ───────────────────────────────────────

  @SuppressLint("MissingPermission")
  fun watchPosition(options: ReadableMap): Int {
    applyOptions(options)
    val id = nextWatchId++
    watchIds.add(id)
    Log.d(TAG, "watch_add id=$id count=${watchIds.size}")
    log("watch-add", mapOf("watchId" to id, "watchCount" to watchIds.size))
    startUpdates()
    prefs.edit()
      .putBoolean("watch_active", true)
      .putBoolean("session_active", true)
      .putString("watch_mode", mode.name)
      .putLong("watch_interval", intervalMs)
      .putFloat("watch_distance", distanceMeters)
      .apply()
    // Schedule watchdog to recover from OS-kill or crash
    TrackingRestartWorker.schedule(context)
    return id
  }

  fun setTrackingMode(modeStr: String) {
    mode = TrackingMode.entries.find { it.name == modeStr } ?: mode
    distanceMeters = mode.distanceM
    log("mode-change", mapOf("mode" to mode.name, "distanceFilter" to distanceMeters))
    if (isWatching) restartUpdates()
  }

  fun setPaused(paused: Boolean) {
    isPaused = paused
    log(if (paused) "pause" else "resume", mapOf("mode" to mode.name))
    if (paused) {
      setTrackingMode("stationary")
      pauseGpsHardware()
    } else {
      setTrackingMode("fitness")
      resumeGpsHardwareIfWatching()
    }
  }

  /** Stop fused updates while keeping watch registrations (manual or auto pause). */
  private fun pauseGpsHardware() {
    cancelStopTimeout()
    callback?.let { fusedClient.removeLocationUpdates(it) }
    isWatching = false
    log("gps-pause", mapOf("watchCount" to watchIds.size))
  }

  /** Restart fused updates after pause if watches are still registered. */
  @SuppressLint("MissingPermission")
  private fun resumeGpsHardwareIfWatching() {
    when {
      watchIds.isNotEmpty() -> startUpdates()
      timeBasedWatchId != null -> {
        startTimeBasedUpdates()
        startTimeBasedTimer()
      }
    }
  }

  // ─── Time-Based Tracking ──────────────────────────────────────────────────

  @SuppressLint("MissingPermission")
  fun startTimeBasedTracking(options: ReadableMap): Int {
    val id = nextWatchId++
    timeBasedWatchId = id

    timeBasedIntervalMs = if (options.hasKey("intervalMs")) {
      options.getDouble("intervalMs").toLong().coerceAtLeast(500)
    } else 3000
    timeBasedStationaryIntervalMs = if (options.hasKey("stationaryIntervalMs")) {
      options.getDouble("stationaryIntervalMs").toLong().coerceAtLeast(5000)
    } else 30000
    timeBasedAdaptive = if (options.hasKey("adaptiveInterval")) options.getBoolean("adaptiveInterval") else true
    timeBasedMaxAccuracy = if (options.hasKey("maxAccuracy")) options.getDouble("maxAccuracy").toFloat() else 50f
    timeBasedPaused = false
    timeBasedIsStationary = false
    timeBasedStationarySince = 0
    timeBasedLastLocation = null
    cumulativeDistance = 0.0
    lastProcessedLocation = null

    // Start continuous location updates at high frequency
    val priority = if (highAccuracy) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
    val request = LocationRequest.Builder(priority, timeBasedIntervalMs)
      .setMinUpdateIntervalMillis(timeBasedIntervalMs.coerceAtMost(1000))
      .setMinUpdateDistanceMeters(0f) // Every point, regardless of distance
      .build()

    callback?.let { fusedClient.removeLocationUpdates(it) }
    callback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        if (timeBasedPaused) return
        val loc = result.lastLocation ?: return
        processTimeBasedLocation(loc)
      }
    }

    try {
      fusedClient.requestLocationUpdates(request, callback!!, Looper.getMainLooper())
    } catch (e: SecurityException) {
      log("location-error", mapOf("message" to "Location permission not granted"))
      callback = null
      return id
    }

    isWatching = true
    startTimeBasedTimer()

    Log.d(TAG, "timebased_start id=$id interval=${timeBasedIntervalMs}ms adaptive=$timeBasedAdaptive")
    log("timebased-start", mapOf(
      "watchId" to id,
      "intervalMs" to timeBasedIntervalMs,
      "adaptive" to timeBasedAdaptive,
    ))
    devLog("info", "TimeBasedTracker", "native_started", mapOf(
      "intervalMs" to timeBasedIntervalMs,
      "adaptive" to timeBasedAdaptive,
      "maxAccuracy" to timeBasedMaxAccuracy,
    ))

    return id
  }

  fun stopTimeBasedTracking(watchId: Int) {
    if (timeBasedWatchId != watchId) return
    timeBasedWatchId = null
    timeBasedHandler?.removeCallbacksAndMessages(null)
    timeBasedRunnable = null
    timeBasedLastLocation = null

    if (watchIds.isEmpty()) stopUpdates()
    Log.d(TAG, "timebased_stop id=$watchId")
    log("timebased-stop", mapOf("watchId" to watchId))
    devLog("info", "TimeBasedTracker", "native_stopped", emptyMap())
  }

  fun pauseTimeBasedTracking(watchId: Int) {
    if (timeBasedWatchId != watchId) return
    timeBasedPaused = true
    timeBasedHandler?.removeCallbacksAndMessages(null)
    timeBasedRunnable = null
    callback?.let { fusedClient.removeLocationUpdates(it) }
    log("timebased-pause", mapOf("watchId" to watchId))
  }

  fun resumeTimeBasedTracking(watchId: Int) {
    if (timeBasedWatchId != watchId) return
    timeBasedPaused = false
    startTimeBasedUpdates()
    startTimeBasedTimer()
    log("timebased-resume", mapOf("watchId" to watchId))
  }

  fun setTimeBasedInterval(watchId: Int, intervalMs: Double) {
    if (timeBasedWatchId != watchId) return
    timeBasedIntervalMs = (intervalMs.toLong()).coerceAtLeast(500)
    if (isWatching) {
      startTimeBasedUpdates()
      startTimeBasedTimer()
    }
  }

  @SuppressLint("MissingPermission")
  private fun startTimeBasedUpdates() {
    val priority = if (highAccuracy) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
    val effectiveInterval = if (timeBasedAdaptive && timeBasedIsStationary) {
      timeBasedStationaryIntervalMs
    } else {
      timeBasedIntervalMs
    }

    callback?.let { fusedClient.removeLocationUpdates(it) }
    val request = LocationRequest.Builder(priority, effectiveInterval)
      .setMinUpdateIntervalMillis(1000) // Collect regardless of frequency
      .setMinUpdateDistanceMeters(0f)
      .build()

    callback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        if (timeBasedPaused) return
        val loc = result.lastLocation ?: return
        processTimeBasedLocation(loc)
      }
    }

    try {
      fusedClient.requestLocationUpdates(request, callback!!, Looper.getMainLooper())
    } catch (e: SecurityException) {
      log("location-error", mapOf("message" to "Permission not granted"))
    }
  }

  private fun startTimeBasedTimer() {
    timeBasedHandler?.removeCallbacksAndMessages(null)
    if (timeBasedHandler == null) {
      timeBasedHandler = android.os.Handler(Looper.getMainLooper())
    }

    val currentInterval = if (timeBasedAdaptive && timeBasedIsStationary) {
      timeBasedStationaryIntervalMs.coerceAtMost(60000)
    } else {
      timeBasedIntervalMs.coerceAtMost(60000)
    }

    timeBasedRunnable = Runnable { flushTimeBasedTick() }
    timeBasedRunnable?.let { timeBasedHandler?.postDelayed(it, currentInterval) }
  }

  private fun flushTimeBasedTick() {
    val loc = timeBasedLastLocation ?: return
    val watchId = timeBasedWatchId ?: return

    // Assess GPS strength
    val strength = signalStrength(loc.accuracy)

    // Update cumulative distance
    loc.cumulativeDistance.let { cumulativeDistance = it }

    // Check stationary state
    val speed = loc.speed
    val now = System.currentTimeMillis()
    if (speed < 0.5f) {
      if (timeBasedStationarySince == 0L) timeBasedStationarySince = now
      if (now - timeBasedStationarySince >= 10_000) timeBasedIsStationary = true
    } else {
      timeBasedStationarySince = 0L
      timeBasedIsStationary = false
    }

    // If adaptive and stationary state changed, restart timer
    if (timeBasedAdaptive) {
      startTimeBasedUpdates()
      startTimeBasedTimer()
    } else {
      timeBasedRunnable?.let { timeBasedHandler?.postDelayed(it, timeBasedIntervalMs) }
    }

    // Update Live Activity with current workout data (if session active).
    // Issue #8: Guard with isUserEnabled() + isActivityActive() before calling update
    // so we don't create unnecessary work when Live Activity isn't running.
    // Wrapped in try/catch so a notification failure never kills the tick loop.
    if (currentSessionId != null && currentSessionStartTime > 0
      && liveActivityManager.isUserEnabled()
      && liveActivityManager.isActivityActive()
    ) {
      val durationSeconds = (now - currentSessionStartTime) / 1000
      val paceFormatted = liveActivityManager.formatPace(speed.toDouble())
      val sessionActivityType = currentActivityType

      try {
        liveActivityManager.updateActivity(
          distance = cumulativeDistance,
          duration = durationSeconds,
          pace = paceFormatted,
          speed = speed.toDouble() * 3.6,
          calories = liveActivityManager.estimateCalories(cumulativeDistance, sessionActivityType),
          heartRate = null,
          gpsStatus = strength,
          isPaused = timeBasedPaused
        )
      } catch (e: Exception) {
        // Non-fatal: Live Activity update must never break GPS tracking.
        Log.w(TAG, "flushTimeBasedTick live_activity_update_error: ${e.message}")
      }
    }

    // Notify listeners
    for (l in listenerSnapshot()) {
      l.onTimeBasedTick(loc)
      l.onGpsStrengthChange(strength, loc.accuracy.toDouble())
      l.onStationaryChange(timeBasedIsStationary)
    }

    // DEV logcat
    Log.d(TAG, "tick lat=${loc.latitude} lng=${loc.longitude} acc=${loc.accuracy} spd=${loc.speed} gps=$strength stationary=$timeBasedIsStationary dist=$cumulativeDistance")
  }

  private fun processTimeBasedLocation(loc: Location) {
    if (timeBasedPaused) return
    val acc = if (loc.hasAccuracy()) loc.accuracy else 999f
    if (acc <= 0 || acc > timeBasedMaxAccuracy) return

    // Filter
    when (val filtered = filter.process(loc)) {
      is LocationFilter.Result.Reject -> return
      is LocationFilter.Result.Accept -> {
        lastLocation = filtered.location

        val dist = computeDistance(filtered.location)
        val stored = filtered.location.toStored(delivered = false).withRouteMetrics(
          distanceFromPrev = dist,
          cumulativeDistance = cumulativeDistance,
        )

        if (database.insert(stored)) {
          timeBasedLastLocation = stored
          Log.v(TAG, "timebased_collect lat=${stored.latitude} lng=${stored.longitude} dist=$dist cumulative=$cumulativeDistance")
        }
      }
    }
  }

  // ─── Updates ───────────────────────────────────────────────────────────────

  @SuppressLint("MissingPermission")
  private fun startUpdates() {
    if (callback != null && isWatching) return
    isWatching = true
    val priority = if (highAccuracy) mode.priority else Priority.PRIORITY_BALANCED_POWER_ACCURACY
    val request = LocationRequest.Builder(priority, intervalMs)
      .setMinUpdateIntervalMillis(fastestIntervalMs)
      .setMinUpdateDistanceMeters(distanceMeters)
      .build()

    callback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        if (isPaused) {
          log("location-drop", mapOf("reason" to "paused"))
          return
        }
        val loc = result.lastLocation ?: return
        processLocation(loc)
      }
    }
    try {
      fusedClient.requestLocationUpdates(request, callback!!, Looper.getMainLooper())
      Log.d(TAG, "watch_start mode=${mode.name} df=$distanceMeters interval=$intervalMs")
    } catch (e: SecurityException) {
      val ids = watchIds.toList()
      log("location-error", mapOf("message" to "Location permission not granted"))
      listenerSnapshot().forEach { it.onLocationError("Location permission not granted", ids) }
      callback = null
      isWatching = false
    }
  }

  private fun restartUpdates() {
    stopUpdatesInternal(keepWatchState = true)
    startUpdates()
  }

  fun clearWatch(watchId: Int) {
    watchIds.remove(watchId)
    log("watch-clear", mapOf("watchId" to watchId, "watchCount" to watchIds.size))
    if (watchIds.isEmpty()) stopUpdates()
  }

  fun activeWatchCount(): Int = watchIds.size

  fun stopObserving() {
    watchIds.clear()
    log("stop-observing")
    stopUpdates()
  }

  private fun stopUpdates() {
    stopUpdatesInternal(keepWatchState = false)
  }

  private fun stopUpdatesInternal(keepWatchState: Boolean) {
    isWatching = false
    gpsSuspended = false
    cancelStopTimeout()
    callback?.let { fusedClient.removeLocationUpdates(it) }
    callback = null
    filter.reset()
    timeBasedHandler?.removeCallbacksAndMessages(null)
    timeBasedRunnable = null
    if (!keepWatchState) {
      prefs.edit()
        .putBoolean("watch_active", false)
        .putBoolean("session_active", false)
        .apply()
    }
    // Cancel watchdog when tracking stops
    TrackingRestartWorker.cancel(context)
    log("watch-stop", mapOf("pending" to database.pendingCount()))
    devLog("info", "LocationEngine", "watch_stopped", mapOf("pending" to database.pendingCount()))
  }

  @SuppressLint("MissingPermission")
  private fun restoreWatchIfNeeded() {
    if (!prefs.getBoolean("watch_active", false)) return
    if (!prefs.getBoolean("session_active", false)) {
      prefs.edit()
        .putBoolean("watch_active", false)
        .putBoolean("session_active", false)
        .apply()
      return
    }
    mode = TrackingMode.entries.find { it.name == prefs.getString("watch_mode", "fitness") } ?: TrackingMode.fitness
    intervalMs = prefs.getLong("watch_interval", 3000L)
    distanceMeters = prefs.getFloat("watch_distance", 5f)
    isWatching = true
    Log.d(TAG, "watch_restore mode=${mode.name}")
    startUpdates()
  }

  /** Cold launch: restore only for a legitimate in-flight workout; otherwise hard-idle. */
  private fun reconcileWatchStateOnColdLaunch() {
    val hadWatch = prefs.getBoolean("watch_active", false)
    val sessionActive = prefs.getBoolean("session_active", false)
    if (hadWatch && sessionActive) {
      restoreWatchIfNeeded()
      return
    }
    watchIds.clear()
    stopUpdatesInternal(keepWatchState = false)
  }

  /**
   * Restore watch state after app crash or device reboot.
   * Called by BootCompletedReceiver and TrackingRestartWorker.
   */
  @SuppressLint("MissingPermission")
  fun restoreWatchFromCrash(modeStr: String, intervalMs: Long, distanceM: Float) {
    this.mode = TrackingMode.entries.find { it.name == modeStr } ?: TrackingMode.fitness
    this.intervalMs = intervalMs
    this.distanceMeters = distanceM
    this.isWatching = true
    Log.i(TAG, "restoreWatchFromCrash mode=${mode.name} interval=${intervalMs}ms")
    startUpdates()
    prefs.edit()
      .putBoolean("watch_active", true)
      .putBoolean("session_active", true)
      .apply()
    // Re-arm watchdog for continued crash recovery
    TrackingRestartWorker.schedule(context)
  }

  /**
   * Write a diagnostic event to the internal log buffer.
   * Used by BootCompletedReceiver and TrackingRestartWorker for audit trails.
   */
  fun logDiagnostic(event: Map<String, Any?>) {
    val mutableEvent = event.toMutableMap()
    mutableEvent["platform"] = "android"
    log(event["event"] as? String ?: "diagnostic", mutableEvent - "event")
  }

  // ─── Session Management ────────────────────────────────────────────────────

  fun createSession(name: String, activityType: String, extras: String?): String {
    val id = database.createSession(name, activityType, extras)
    currentSessionId = id
    currentActivityType = activityType
    currentSessionStartTime = System.currentTimeMillis()
    cumulativeDistance = 0.0
    lastProcessedLocation = null
    // Persist session ID so BootCompletedReceiver / watchdog can reference it
    prefs.edit().putString("active_session_id", id).apply()
    Log.d(TAG, "session_created id=$id name=$name")
    
    // Start Live Activity if enabled
    liveActivityManager.startActivity(
      workoutName = name,
      activityType = activityType
    )
    
    return id
  }

  fun endSession(sessionId: String, data: Map<String, Any?>) {
    database.endSession(sessionId, data)
    if (currentSessionId == sessionId) currentSessionId = null
    Log.d(TAG, "session_ended id=$sessionId dist=${data["totalDistance"]} pts=${data["pointCount"]}")
    
    // End Live Activity if active
    liveActivityManager.endActivity(
      finalDistance = (data["totalDistance"] as? Double) ?: 0.0,
      finalDuration = ((data["totalDuration"] as? Double)?.toLong() ?: 0L) / 1000, // Convert ms to seconds
      finalCalories = (data["calories"] as? Int) ?: 0
    )
  }

  fun discardSession(sessionId: String) {
    database.discardSession(sessionId)
    if (currentSessionId == sessionId) currentSessionId = null
  }

  fun getUnuploadedSessions(): List<Map<String, Any?>> = database.getUnuploadedSessions()
  fun getSessionForUpload(sessionId: String): Map<String, Any?>? = database.getSessionForUpload(sessionId)
  fun markSessionUploaded(sessionId: String) = database.markSessionUploaded(sessionId)

  // ─── Location Processing ───────────────────────────────────────────────────

  private fun processLocation(loc: Location) {
    if (isPaused) {
      log("location-drop", mapOf("reason" to "paused"))
      return
    }

    when (val filtered = filter.process(loc)) {
      is LocationFilter.Result.Reject -> {
        log("location-drop", mapOf("reason" to filtered.reason, "accuracy" to loc.accuracy))
        return
      }
      is LocationFilter.Result.Accept -> {
        lastLocation = filtered.location
        val dist = computeDistance(filtered.location)
        val deliverLive = isAppActive() && watchIds.isNotEmpty()
        val stored = filtered.location.toStored(delivered = false).withRouteMetrics(
          distanceFromPrev = dist,
          cumulativeDistance = cumulativeDistance,
        )

        if (!database.insert(stored)) {
          log("persist-failed", mapOf("accuracy" to filtered.location.accuracy))
          return
        }

        // Update heartbeat so TrackingRestartWorker can detect GPS stalls
        prefs.edit().putLong("last_location_heartbeat", System.currentTimeMillis()).apply()

        Log.v(TAG, "persist lat=${stored.latitude} lng=${stored.longitude} acc=${stored.accuracy} spd=${stored.speed} dist=$dist cumulative=$cumulativeDistance")

        log("location-persist", mapOf(
          "id" to stored.id,
          "accuracy" to stored.accuracy,
          "speed" to stored.speed,
          "distance" to dist,
          "cumulative" to cumulativeDistance,
          "pending" to database.pendingCount(),
          "deliverLive" to deliverLive,
        ))

        if (deliverLive) {
          val ids = watchIds.toList()
          listenerSnapshot().forEach { it.onLocationPersisted(stored, ids, true) }
        }

        emitDiagnostic(mapOf("event" to "location", "location" to stored.toHttpMap()))
        geofenceManager.updateDeviceLocation(stored.latitude, stored.longitude)
        geofenceManager.evaluatePolygons(stored.latitude, stored.longitude)
        scheduleManager.evaluate()
        triggerAutoSyncIfNeeded()
      }
    }
  }

  private fun computeDistance(loc: Location): Double {
    val prev = lastProcessedLocation ?: run {
      lastProcessedLocation = loc
      return 0.0
    }
    val dist = loc.distanceTo(prev).toDouble()
    if (dist > 0) cumulativeDistance += dist
    lastProcessedLocation = loc
    return dist
  }

  // ─── Battery-Conscious GPS Management ──────────────────────────────────────

  /** Configure motion-based GPS auto-pause/resume (reference: transistorsoft) */
  fun configureMotionAutoPause(enabled: Boolean, delaySeconds: Long, stopTimeoutMinutes: Long) {
    motionAutoPauseEnabled = enabled
    motionAutoResumeEnabled = enabled
    stopTimeoutMs = stopTimeoutMinutes.coerceAtLeast(1) * 60 * 1000
  }

  /** Feed a motion activity change from MotionEngine for GPS suspend/resume */
  fun feedMotionActivity(activity: String) {
    if (MotionEngine.isMovingActivity(activity)) {
      resumeGps()
    }
  }

  /** Called when speed data suggests the device is stationary for a while */
  fun onStationaryAutoPause() {
    if (!motionAutoPauseEnabled || (!isWatching && timeBasedWatchId == null)) return
    if (gpsSuspended) return

    Log.d(TAG, "motion_auto_pause: starting_stop_timeout=${stopTimeoutMs}ms")
    startStopTimeout()
  }

  /** Called when motion is detected — resume GPS immediately */
  fun onMotionResume() {
    if (!motionAutoResumeEnabled) return
    cancelStopTimeout()
    stationarySinceMs = 0L

    if (gpsSuspended) {
      resumeGps()
    }
  }

  private fun startStopTimeout() {
    cancelStopTimeout()
    val r = Runnable {
      stopTimerRunnable = null
      suspendGps()
    }
    stopTimerRunnable = r
    mainHandler.postDelayed(r, stopTimeoutMs)
  }

  private fun cancelStopTimeout() {
    stopTimerRunnable?.let { mainHandler.removeCallbacks(it) }
    stopTimerRunnable = null
  }

  @SuppressLint("MissingPermission")
  private fun suspendGps() {
    if (gpsSuspended) return
    gpsSuspended = true

    callback?.let { fusedClient.removeLocationUpdates(it) }
    callback = null

    Log.d(TAG, "gps_suspended: motion_wake_enabled=true")
    log("gps-suspend", mapOf("reason" to "stationary_timeout", "stopTimeoutMs" to stopTimeoutMs))
  }

  @SuppressLint("MissingPermission")
  private fun resumeGps() {
    if (!gpsSuspended) return
    gpsSuspended = false

    if (isWatching || timeBasedWatchId != null) {
      restartUpdatesInternal()
    }

    Log.d(TAG, "gps_resumed: motion_detected")
    log("gps-resume", mapOf("reason" to "motion_detected"))
  }

  /** Restart location updates without clearing watch state */
  @SuppressLint("MissingPermission")
  private fun restartUpdatesInternal() {
    // Simplified restart — used when resuming from GPS suspend
    val priority = if (highAccuracy) mode.priority else Priority.PRIORITY_BALANCED_POWER_ACCURACY
    val request = LocationRequest.Builder(priority, intervalMs)
      .setMinUpdateIntervalMillis(fastestIntervalMs)
      .setMinUpdateDistanceMeters(distanceMeters)
      .build()

    val cb = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        if (isPaused) return
        val loc = result.lastLocation ?: return
        processLocation(loc)
      }
    }
    callback = cb
    try {
      fusedClient.requestLocationUpdates(request, cb, Looper.getMainLooper())
    } catch (e: SecurityException) {
      // Issue #9: Log and notify listeners — silent swallow hid GPS permission loss.
      Log.e(TAG, "restartUpdatesInternal: location permission revoked — ${e.message}")
      callback = null
      val ids = watchIds.toList()
      log("location-error", mapOf("message" to "Location permission revoked during GPS resume"))
      listenerSnapshot().forEach {
        it.onLocationError("Location permission revoked", ids)
      }
    }
  }

  /** Feed speed for GPS resume detection (used from LocationFilter processing) */
  fun feedSpeedForGpsResume(speed: Float) {
    if (!gpsSuspended) return
    if (speed > 0.5f) {
      onMotionResume()
    }
  }

  // ─── Odometer ──────────────────────────────────────────────────────────────

  fun getOdometer(): Double = cumulativeDistance

  fun resetOdometer() {
    cumulativeDistance = 0.0
    lastProcessedLocation = null
    log("odometer-reset")
  }

  fun setOdometer(value: Double) {
    cumulativeDistance = value
    log("odometer-set", mapOf("value" to value))
  }

  // ─── Getters ───────────────────────────────────────────────────────────────

  fun getEngineState(): WritableMap {
    val map = Arguments.createMap()
    map.putBoolean("isWatching", isWatching)
    map.putBoolean("isPaused", isPaused)
    map.putString("mode", mode.name)
    map.putInt("pendingQueue", database.pendingCount())
    map.putString("motionState", "unknown")
    map.putString("signalStrength", signalStrength(lastLocation))
    map.putInt("diagnosticCount", diagnostics.size)
    map.putDouble("odometer", cumulativeDistance)
    map.putBoolean("timeBasedActive", timeBasedWatchId != null)
    return map
  }

  private fun signalStrength(loc: android.location.Location?): String {
    val acc = loc?.accuracy ?: return "weak"
    return signalStrength(acc)
  }

  private fun signalStrength(accuracy: Float): String {
    return when {
      accuracy <= 0f -> "none"
      accuracy <= 10f -> "strong"
      accuracy <= 30f -> "medium"
      accuracy <= 50f -> "weak"
      else -> "none"
    }
  }

  // ─── Database Access ───────────────────────────────────────────────────────

  fun getPendingForJs(limit: Int): WritableArray {
    val arr = Arguments.createArray()
    database.getPendingForJs(limit).forEach { arr.pushMap(it.toPayloadMap()) }
    return arr
  }

  fun markDelivered(ids: List<String>): Int {
    val count = database.markDelivered(ids)
    log("location-ack", mapOf("requested" to ids.size, "updated" to count))
    return count
  }

  fun acknowledge(ids: List<String>): Int = database.acknowledge(ids)
  fun purgeDelivered(): Int {
    val count = database.purgeDelivered()
    log("location-purge", mapOf("deleted" to count))
    return count
  }

  fun pendingCount(): Int = database.pendingCount()

  fun getDiagnostics(): WritableArray {
    val arr = Arguments.createArray()
    synchronized(diagnostics) {
      diagnostics.forEach { arr.pushMap(Arguments.makeNativeMap(it)) }
    }
    return arr
  }

  // ─── Logging ───────────────────────────────────────────────────────────────

  private fun log(event: String, data: Map<String, Any?> = emptyMap()) {
    val row = data.toMutableMap()
    row["event"] = event
    row["platform"] = "android"
    row["timestamp"] = System.currentTimeMillis().toDouble()
    synchronized(diagnostics) {
      diagnostics.addLast(row)
      while (diagnostics.size > 300) diagnostics.removeFirst()
    }
    listenerSnapshot().forEach { it.onDiagnostic(Arguments.makeNativeMap(row)) }
  }

  fun devLog(level: String, tag: String, message: String, data: Map<String, Any?> = emptyMap()) {
    when (level) {
      "error" -> Log.e(tag, "$message $data")
      "warn" -> Log.w(tag, "$message $data")
      "info" -> Log.i(tag, "$message $data")
      else -> Log.d(tag, "$message $data")
    }
  }

  // ─── Location Extension ────────────────────────────────────────────────────

  private fun android.location.Location.toStored(delivered: Boolean): StoredLocation {
    val acc = if (hasAccuracy()) accuracy else 999f
    val bat = batteryLevel()
    val positionConfidence = (1.0 - (acc / 100.0)).coerceIn(0.0, 1.0)
    val motionConfidence = (currentConfidence / 100.0).coerceIn(0.0, 1.0)
    val qualityJson = "{\"positionConfidence\":$positionConfidence,\"motionConfidence\":$motionConfidence,\"headingConfidence\":0.5,\"activityConfidence\":$motionConfidence}"
    return StoredLocation(
      id = java.util.UUID.randomUUID().toString(),
      latitude = latitude,
      longitude = longitude,
      accuracy = acc,
      speed = if (hasSpeed()) speed else 0f,
      heading = if (hasBearing()) bearing else 0f,
      altitude = altitude,
      timestamp = time,
      sessionId = currentSessionId ?: "default",
      deliveredToJs = delivered,
      signalStrength = signalStrength(acc),
      batteryLevel = bat,
      qualityJson = qualityJson,
    )
  }

  private var lastBatteryCheck = 0L
  private fun batteryLevel(): Double {
    // Check battery every 10s to avoid excessive reads
    val now = System.currentTimeMillis()
    if (now - lastBatteryCheck < 10_000) return -1.0
    lastBatteryCheck = now

    return try {
      val intent = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
      val level = intent?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
      val scale = intent?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
      if (level > 0 && scale > 0) level.toDouble() / scale.toDouble() else -1.0
    } catch (_: Exception) { -1.0 }
  }

  // ─── HTTP Auto-Sync ────────────────────────────────────────────────────────

  var httpConfigured: Boolean = false
  var httpUrl: String? = null
  var httpMethod: String = "POST"
  var httpHeaders: Map<String, String> = emptyMap()
  var httpAutoSync: Boolean = true
  var httpBatchSync: Boolean = true
  var httpBatchSize: Int = 100
  var httpRetryCount: Int = 3
  var httpListenerEnabled: Boolean = false
  var httpAutoSyncThreshold: Int = 0
  private var httpPendingSinceSync = 0

  // Background engine state
  var isEngineEnabled = false
  var geofencesOnlyMode = false
  var isMoving = true
  var scheduleRecords: List<String> = emptyList()
  private var heartbeatHandler: android.os.Handler? = null
  private var heartbeatRunnable: Runnable? = null

  init {
    geofenceManager.onGeofenceEvent = { id, action, data ->
      emitGeofenceEvent(id, action, data)
    }
    geofenceManager.onGeofencesChange = { on, off ->
      emitGeofencesChange(on, off)
    }
    scheduleManager.onScheduleChange = { enabled, mode ->
      geofencesOnlyMode = mode == ScheduleManager.TrackingMode.geofence
      if (enabled && mode == ScheduleManager.TrackingMode.location && !isWatching) {
        watchPosition(emptyMap())
      } else if (!enabled) {
        stopObserving()
      }
      emitDiagnostic(mapOf("event" to "schedule", "enabled" to enabled, "mode" to mode.name.lowercase()))
    }
    providerMonitor.onEvent = { event -> listenerSnapshot().forEach { it.onDiagnostic(event) } }
    providerMonitor.start()
  }

  /** Trigger HTTP sync of all pending locations */
  fun httpSync(): List<Map<String, Any?>> {
    val url = httpUrl ?: return emptyList()
    val points = database.getPendingForJs(httpBatchSize)
    if (points.isEmpty()) return emptyList()

    try {
      val body = if (httpBatchSync) {
        // Batch: single POST with array of points
        org.json.JSONArray(points.map { it.toHttpMap() }).toString()
      } else {
        // Individual: POST each point separately (REST-style)
        points.forEach { point ->
          uploadSingle(httpUrl!!, point)
        }
        return points.map { it.toHttpMap() }
      }

      val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
      conn.requestMethod = httpMethod
      conn.doOutput = true
      conn.setRequestProperty("Content-Type", "application/json")
      httpHeaders.forEach { (key, value) -> conn.setRequestProperty(key, value) }
      conn.connectTimeout = 15000
      conn.readTimeout = 15000

      conn.outputStream.use { os ->
        os.write(body.toByteArray())
      }

      val responseCode = conn.responseCode
      val responseText = if (responseCode in 200..299) {
        conn.inputStream.bufferedReader().readText()
      } else {
        conn.errorStream?.bufferedReader()?.readText() ?: "HTTP $responseCode"
      }
      conn.disconnect()

      if (responseCode in 200..299) {
        val ids = points.map { it.id }
        database.markDelivered(ids)
        Log.d(TAG, "http_sync_success: ${points.size} points, status=$responseCode")

        if (httpListenerEnabled) {
          val event = Arguments.createMap().apply {
            putString("event", "httpResponse")
            putBoolean("success", true)
            putInt("status", responseCode)
            putString("responseText", responseText)
            putInt("locationCount", points.size)
          }
          listenerSnapshot().forEach { it.onDiagnostic(event) }
        }

        return points.map { it.toHttpMap() }
      } else {
        Log.w(TAG, "http_sync_failed: status=$responseCode")
        return emptyList()
      }
    } catch (e: Exception) {
      Log.e(TAG, "http_sync_error: ${e.message}")
      return emptyList()
    }
  }

  private fun uploadSingle(url: String, point: StoredLocation) {
    try {
      val body = point.toHttpMap().let { org.json.JSONObject(it as Map<*, *>).toString() }
      val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
      conn.requestMethod = httpMethod
      conn.doOutput = true
      conn.setRequestProperty("Content-Type", "application/json")
      httpHeaders.forEach { (key, value) -> conn.setRequestProperty(key, value) }
      conn.connectTimeout = 15000
      conn.readTimeout = 15000
      conn.outputStream.use { os -> os.write(body.toByteArray()) }
      val code = conn.responseCode
      conn.disconnect()
      if (code in 200..299) database.markDelivered(listOf(point.id))
    } catch (_: Exception) {}
  }

  fun clearAll() {
    database.clearAll()
  }

  private fun StoredLocation.toHttpMap(): Map<String, Any?> = mapOf(
    "latitude" to latitude,
    "longitude" to longitude,
    "accuracy" to accuracy,
    "speed" to speed,
    "altitude" to altitude,
    "timestamp" to timestamp,
    "heading" to heading,
    "distanceFromPrev" to distanceFromPrev,
    "cumulativeDistance" to cumulativeDistance,
    "signalStrength" to signalStrength,
    "motionState" to motionState,
    "batteryLevel" to batteryLevel,
  )

  // ─── Geofencing (GeofencingClient) ─────────────────────────────────────────

  fun addGeofence(data: Map<String, Any?>): Boolean = geofenceManager.addGeofence(data)

  fun addGeofences(list: List<Map<String, Any?>>): Boolean = geofenceManager.addGeofences(list)

  fun removeGeofence(identifier: String): Boolean = geofenceManager.removeGeofence(identifier)

  fun removeGeofences(identifiers: List<String>?): Boolean {
    geofenceManager.removeGeofences(identifiers)
    return true
  }

  fun getGeofences(): List<Map<String, Any?>> = geofenceManager.getGeofences()

  fun geofenceExists(identifier: String): Boolean = geofenceManager.exists(identifier)

  fun handleGeofenceTransition(identifier: String, transition: Int) {
    geofenceManager.handleTransition(identifier, transition)
  }

  private fun emitGeofenceEvent(id: String, action: String, data: Map<String, Any?>) {
    emitDiagnostic(mapOf(
      "event" to "geofence",
      "identifier" to id,
      "action" to action,
      "latitude" to data["latitude"],
      "longitude" to data["longitude"],
      "radius" to data["radius"],
      "timestamp" to System.currentTimeMillis(),
    ))
  }

  private fun emitGeofencesChange(on: List<String>, off: List<String>) {
    emitDiagnostic(mapOf("event" to "geofencesChange", "on" to on, "off" to off))
  }

  private fun emitDiagnostic(data: Map<String, Any?>) {
    listenerSnapshot().forEach { it.onDiagnostic(Arguments.makeNativeMap(data)) }
  }

  // ─── Background Lifecycle ──────────────────────────────────────────────────

  fun ready(config: Map<String, Any?>): Map<String, Any> {
    mergeConfig(config)
    return getState()
  }

  fun mergeConfig(config: Map<String, Any?>) {
    (config["trackingMode"] as? String)?.let { setModeString(it) }
    applyLoggerFromConfig(config)
    (config["url"] as? String)?.let { url ->
      httpUrl = url
      httpMethod = config["method"] as? String ?: "POST"
      @Suppress("UNCHECKED_CAST")
      httpHeaders = (config["headers"] as? Map<String, String>) ?: emptyMap()
      httpAutoSync = config["autoSync"] as? Boolean ?: true
      httpBatchSync = config["batchSync"] as? Boolean ?: true
      httpBatchSize = (config["batchSize"] as? Number)?.toInt()
        ?: (config["maxBatchSize"] as? Number)?.toInt() ?: 100
      httpAutoSyncThreshold = (config["autoSyncThreshold"] as? Number)?.toInt() ?: 0
      httpConfigured = true
    }
    (config["schedule"] as? List<*>)?.let { list ->
      scheduleRecords = list.mapNotNull { it as? String }
      scheduleManager.configure(scheduleRecords)
    }
  }

  fun getState(): Map<String, Any> {
    val state = mutableMapOf<String, Any>(
      "enabled" to isEngineEnabled,
      "isMoving" to isMoving,
      "tracking" to isWatching,
      "mode" to mode.name,
      "pending" to database.pendingCount(),
      "odometer" to cumulativeDistance,
    )
    state.putAll(scheduleManager.stateMap())
    return state
  }

  fun startEngine() {
    if (!isWatching) watchPosition(emptyMap())
    isEngineEnabled = true
    emitDiagnostic(mapOf("event" to "enabledchange", "enabled" to true))
  }

  fun stopEngine() {
    stopObserving()
    emitDiagnostic(mapOf("event" to "enabledchange", "enabled" to false))
  }

  fun changePace(moving: Boolean) {
    isMoving = moving
    if (moving) onMotionResume() else onStationaryAutoPause()
    emitDiagnostic(mapOf("event" to "motionchange", "isMoving" to moving))
  }

  fun startSchedule() {
    scheduleManager.configure(scheduleRecords)
    scheduleManager.start()
  }

  fun stopSchedule() = scheduleManager.stop()

  fun startGeofencesMode() {
    geofencesOnlyMode = true
    stopObserving()
    nativeLogger.log("INFO", "geofences-only mode started")
  }

  fun getLocations(limit: Int = 1000): List<Map<String, Any?>> =
    database.getAllLocations(limit).map { it.toHttpMap() }

  fun destroyLocation(uuid: String): Boolean = database.destroyLocation(uuid)

  fun insertLocation(params: Map<String, Any?>): String? {
    val lat = (params["latitude"] as? Number)?.toDouble() ?: return null
    val lng = (params["longitude"] as? Number)?.toDouble() ?: return null
    val stored = StoredLocation(
      id = java.util.UUID.randomUUID().toString(),
      latitude = lat,
      longitude = lng,
      accuracy = (params["accuracy"] as? Number)?.toFloat() ?: 10f,
      speed = (params["speed"] as? Number)?.toFloat() ?: 0f,
      heading = (params["heading"] as? Number)?.toFloat() ?: 0f,
      altitude = (params["altitude"] as? Number)?.toDouble() ?: 0.0,
      timestamp = (params["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis(),
      sessionId = currentSessionId ?: "default",
    )
    if (!database.insert(stored)) return null
    triggerAutoSyncIfNeeded()
    return stored.id
  }

  fun getNativeLog(query: Map<String, Any?>): String {
    val start = (query["start"] as? Number)?.toLong()
    val end = (query["end"] as? Number)?.toLong()
    val order = (query["order"] as? Number)?.toInt() ?: 1
    val limit = (query["limit"] as? Number)?.toInt() ?: 1000
    return nativeLogger.getLog(start, end, order, limit)
  }

  fun destroyNativeLog() = nativeLogger.destroyLog()

  fun nativeLog(level: String, message: String) = nativeLogger.log(level, message)

  fun configureLogger(logLevel: Int, logMaxDays: Int) = nativeLogger.configure(logLevel, logMaxDays)

  @Suppress("UNCHECKED_CAST")
  private fun applyLoggerFromConfig(config: Map<String, Any?>) {
    val source = (config["logger"] as? Map<String, Any?>) ?: config
    val level = (source["logLevel"] as? Number)?.toInt()
    val maxDays = (source["logMaxDays"] as? Number)?.toInt()
    if (level != null || maxDays != null) {
      configureLogger(level ?: 0, maxDays ?: 3)
    }
    val debug = (source["debug"] as? Boolean) ?: (config["debug"] as? Boolean) ?: false
    if (debug) nativeLogger.log("INFO", "SDK ready (debug)")
  }

  fun uploadLog(url: String, query: Map<String, Any?>): Boolean {
    val body = getNativeLog(query)
    return try {
      val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
      conn.requestMethod = "POST"
      conn.doOutput = true
      conn.setRequestProperty("Content-Type", "text/plain")
      conn.outputStream.use { it.write(body.toByteArray()) }
      val ok = conn.responseCode in 200..299
      conn.disconnect()
      ok
    } catch (_: Exception) { false }
  }

  fun httpSyncAll(): List<Map<String, Any?>> {
    val all = mutableListOf<Map<String, Any?>>()
    repeat(20) {
      val batch = httpSync()
      if (batch.isEmpty()) return@repeat
      all.addAll(batch)
    }
    return all
  }

  private fun triggerAutoSyncIfNeeded() {
    if (!httpConfigured || !httpAutoSync || httpUrl == null) return
    httpPendingSinceSync++
    if (httpAutoSyncThreshold > 0 && httpPendingSinceSync < httpAutoSyncThreshold) return
    httpPendingSinceSync = 0
    Thread { httpSyncAll() }.start()
  }

  // ─── Provider State & Power Save ──────────────────────────────────────────

  fun getProviderState(): WritableMap {
    val map = Arguments.createMap()
    map.putBoolean("enabled", isLocationEnabled())
    map.putString("status", if (hasFineLocation(context)) "granted" else "denied")
    map.putBoolean("gps", isLocationEnabled())
    map.putBoolean("network", false)
    return map
  }

  private fun isLocationEnabled(): Boolean {
    try {
      val locManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
      return locManager.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) ||
        locManager.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)
    } catch (_: Exception) { return false }
  }

  fun isPowerSaveMode(): Boolean {
    try {
      val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
      return pm.isPowerSaveMode
    } catch (_: Exception) { return false }
  }

  fun getSensors(): WritableMap {
    val map = Arguments.createMap()
    val pm = context.getPackageManager()
    map.putBoolean("accelerometer", pm.hasSystemFeature(PackageManager.FEATURE_SENSOR_ACCELEROMETER))
    map.putBoolean("gyroscope", pm.hasSystemFeature(PackageManager.FEATURE_SENSOR_GYROSCOPE))
    map.putBoolean("magnetometer", pm.hasSystemFeature(PackageManager.FEATURE_SENSOR_COMPASS))
    map.putBoolean("significantMotion", pm.hasSystemFeature("android.hardware.sensor.significant_motion"))
    return map
  }

  private fun hasFineLocation(ctx: Context): Boolean {
    return androidx.core.content.ContextCompat.checkSelfPermission(
      ctx, Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun StoredLocation.withRouteMetrics(
    distanceFromPrev: Double = this.distanceFromPrev,
    cumulativeDistance: Double = this.cumulativeDistance,
  ): StoredLocation {
    return copy(
      distanceFromPrev = distanceFromPrev,
      cumulativeDistance = cumulativeDistance,
    )
  }

  // ─── Live Activity Management ──────────────────────────────────────────────

  /**
   * Enable or disable Live Activity feature (user setting).
   * Live Activity is OFF by default for security and privacy.
   */
  fun setLiveActivityEnabled(enabled: Boolean) {
    liveActivityManager.setEnabled(enabled)
    Log.d(TAG, "live_activity_enabled=$enabled")
  }

  /**
   * Check if Live Activity is enabled by user.
   */
  fun isLiveActivityEnabled(): Boolean = liveActivityManager.isUserEnabled()

  /**
   * Check if Live Activity is currently active (showing).
   */
  fun isLiveActivityActive(): Boolean = liveActivityManager.isActivityActive()

  /**
   * Check if device supports Live Activity feature.
   */
  fun isLiveActivitySupported(): Boolean = liveActivityManager.isSupported()
}
