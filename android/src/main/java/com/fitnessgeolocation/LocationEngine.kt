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

class LocationEngine(
  private val context: Context,
  private val listener: Listener,
) {
  interface Listener {
    fun onLocationPersisted(location: StoredLocation, watchIds: List<Int>, deliverLive: Boolean)
    fun onLocationError(message: String, watchIds: List<Int>)
    fun onEnterForeground()
  }

  private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
  private val database = LocationDatabase(context)
  private val filter = LocationFilter()
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
    listener.onEnterForeground()
  }

  private fun applyOptions(options: ReadableMap?) {
    if (options == null) return
    if (options.hasKey("interval")) intervalMs = options.getDouble("interval").toLong().coerceAtLeast(500)
    if (options.hasKey("fastestInterval")) {
      fastestIntervalMs = options.getDouble("fastestInterval").toLong().coerceAtLeast(500)
    }
    if (options.hasKey("distanceFilter")) distanceMeters = options.getDouble("distanceFilter").toFloat()
    if (options.hasKey("enableHighAccuracy")) highAccuracy = options.getBoolean("enableHighAccuracy")
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
    fusedClient.requestLocationUpdates(request, singleCallback, Looper.getMainLooper())
  }

  @SuppressLint("MissingPermission")
  fun watchPosition(options: ReadableMap): Int {
    applyOptions(options)
    val id = nextWatchId++
    watchIds.add(id)
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
    if (isWatching) restartUpdates()
  }

  fun setPaused(paused: Boolean) {
    isPaused = paused
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
        if (isPaused) return
        val loc = result.lastLocation ?: return
        when (val filtered = filter.process(loc)) {
          is LocationFilter.Result.Reject -> return
          is LocationFilter.Result.Accept -> {
            lastLocation = filtered.location
            val deliverLive = isAppActive() && watchIds.isNotEmpty()
            val stored = filtered.location.toStored(delivered = deliverLive)
            if (!database.insert(stored)) {
              listener.onLocationError("Failed to persist", watchIds.toList())
              return
            }
            if (deliverLive) database.markDelivered(listOf(stored.id))
            listener.onLocationPersisted(stored, watchIds.toList(), deliverLive)
          }
        }
      }
    }
    fusedClient.requestLocationUpdates(request, callback!!, Looper.getMainLooper())
  }

  private fun restartUpdates() {
    stopUpdatesInternal(keepWatchState = true)
    startUpdates()
  }

  fun clearWatch(watchId: Int) {
    watchIds.remove(watchId)
    if (watchIds.isEmpty()) stopUpdates()
  }

  fun stopObserving() {
    watchIds.clear()
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
  }

  @SuppressLint("MissingPermission")
  private fun restoreWatchIfNeeded() {
    if (!prefs.getBoolean("watch_active", false)) return
    mode = TrackingMode.entries.find { it.name == prefs.getString("watch_mode", "fitness") } ?: TrackingMode.fitness
    intervalMs = prefs.getLong("watch_interval", 3000L)
    distanceMeters = prefs.getFloat("watch_distance", 5f)
    isWatching = true
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

  fun markDelivered(ids: List<String>): Int = database.markDelivered(ids)
  fun acknowledge(ids: List<String>): Int = database.acknowledge(ids)
  fun purgeDelivered(): Int = database.purgeDelivered()
  fun pendingCount(): Int = database.pendingCount()

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
