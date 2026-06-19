package com.fitnessgeolocation

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.os.Looper
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
  }

  companion object {
    @Volatile private var instance: LocationEngine? = null

    fun getInstance(context: Context): LocationEngine {
      return instance ?: synchronized(this) {
        instance ?: LocationEngine(context.applicationContext).also { instance = it }
      }
    }
  }

  private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
  private val database = LocationDatabase(context)
  private val filter = LocationFilter()
  private val listeners = linkedSetOf<Listener>()
  private val diagnostics = ArrayDeque<Map<String, Any?>>()
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

  private val prefs by lazy {
    context.getSharedPreferences("fitness_geolocation", Context.MODE_PRIVATE)
  }

  init {
    restoreWatchIfNeeded()
  }

  fun addListener(listener: Listener) {
    synchronized(listeners) { listeners.add(listener) }
  }

  fun removeListener(listener: Listener) {
    synchronized(listeners) { listeners.remove(listener) }
  }

  private fun listenerSnapshot(): List<Listener> {
    return synchronized(listeners) { listeners.toList() }
  }

  private fun isAppActive(): Boolean {
    val app = context.applicationContext as? Application ?: return true
    val activityManager = app.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
    val processes = activityManager.runningAppProcesses ?: return true
    for (proc in processes) {
      if (proc.processName == app.packageName) {
        return proc.importance <= android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
      }
    }
    return false
  }

  fun onHostResume() {
    log("foreground", mapOf("pending" to database.pendingCount()))
    listenerSnapshot().forEach { it.onEnterForeground() }
  }

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

  @SuppressLint("MissingPermission")
  fun watchPosition(options: ReadableMap): Int {
    applyOptions(options)
    val id = nextWatchId++
    watchIds.add(id)
    log("watch-add", mapOf("watchId" to id, "watchCount" to watchIds.size))
    startUpdates()
    prefs.edit()
      .putBoolean("watch_active", true)
      .putString("watch_mode", mode.name)
      .putLong("watch_interval", intervalMs)
      .putFloat("watch_distance", distanceMeters)
      .apply()
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
    if (paused) setTrackingMode("stationary") else setTrackingMode("fitness")
  }

  @SuppressLint("MissingPermission")
  private fun startUpdates() {
    if (callback != null) return
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
        log("location-raw", mapOf("count" to result.locations.size, "accuracy" to loc.accuracy))
        when (val filtered = filter.process(loc)) {
          is LocationFilter.Result.Reject -> {
            log("location-drop", mapOf("reason" to filtered.reason, "accuracy" to loc.accuracy))
            return
          }
          is LocationFilter.Result.Accept -> {
            lastLocation = filtered.location
            val deliverLive = isAppActive() && watchIds.isNotEmpty()
            val stored = filtered.location.toStored(delivered = false)
            if (!database.insert(stored)) {
              val ids = watchIds.toList()
              log("persist-failed", mapOf("accuracy" to filtered.location.accuracy))
              listenerSnapshot().forEach { it.onLocationError("Failed to persist", ids) }
              return
            }
            log(
              "location-persist",
              mapOf(
                "id" to stored.id,
                "accuracy" to stored.accuracy,
                "pending" to database.pendingCount(),
                "deliverLive" to deliverLive,
              ),
            )
            val ids = watchIds.toList()
            listenerSnapshot().forEach { it.onLocationPersisted(stored, ids, deliverLive) }
          }
        }
      }
    }
    try {
      fusedClient.requestLocationUpdates(request, callback!!, Looper.getMainLooper())
      log(
        "watch-start",
        mapOf(
          "mode" to mode.name,
          "distanceFilter" to distanceMeters,
          "interval" to intervalMs,
          "fastestInterval" to fastestIntervalMs,
          "highAccuracy" to highAccuracy,
        ),
      )
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
    callback?.let { fusedClient.removeLocationUpdates(it) }
    callback = null
    filter.reset()
    if (!keepWatchState) {
      prefs.edit().putBoolean("watch_active", false).apply()
    }
    log("watch-stop", mapOf("pending" to database.pendingCount()))
  }

  @SuppressLint("MissingPermission")
  private fun restoreWatchIfNeeded() {
    if (!prefs.getBoolean("watch_active", false)) return
    mode = TrackingMode.entries.find { it.name == prefs.getString("watch_mode", "fitness") } ?: TrackingMode.fitness
    intervalMs = prefs.getLong("watch_interval", 3000L)
    distanceMeters = prefs.getFloat("watch_distance", 5f)
    isWatching = true
    log("watch-restore", mapOf("mode" to mode.name, "distanceFilter" to distanceMeters))
    startUpdates()
  }

  fun getEngineState(): WritableMap {
    val map = Arguments.createMap()
    map.putBoolean("isWatching", isWatching)
    map.putBoolean("isPaused", isPaused)
    map.putString("mode", mode.name)
    map.putInt("pendingQueue", database.pendingCount())
    map.putString("motionState", "unknown")
    map.putString("signalStrength", signalStrength(lastLocation))
    map.putInt("diagnosticCount", diagnostics.size)
    return map
  }

  private fun signalStrength(loc: android.location.Location?): String {
    val acc = loc?.accuracy ?: return "weak"
    return when {
      acc <= 10f -> "strong"
      acc <= 30f -> "medium"
      else -> "weak"
    }
  }

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

  private fun android.location.Location.toStored(delivered: Boolean): StoredLocation {
    val acc = if (hasAccuracy()) accuracy else 999f
    return StoredLocation(
      id = java.util.UUID.randomUUID().toString(),
      latitude = latitude,
      longitude = longitude,
      accuracy = acc,
      speed = if (hasSpeed()) speed else 0f,
      heading = if (hasBearing()) bearing else 0f,
      altitude = altitude,
      timestamp = time,
      sessionId = "default",
      deliveredToJs = delivered,
    )
  }
}
