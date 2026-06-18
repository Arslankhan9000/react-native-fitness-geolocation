package com.micim.geolocation

import android.annotation.SuppressLint
import android.app.Application
import android.content.Context
import android.os.Looper
import com.facebook.react.bridge.Arguments
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
    coords.putDouble("altitude", altitude)
    coords.putDouble("accuracy", accuracy.toDouble())
    coords.putDouble("heading", heading.toDouble())
    coords.putDouble("speed", speed.toDouble())
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

class LocationEngine(
  private val context: Context,
  private val listener: Listener,
) {
  interface Listener {
    fun onLocationPersisted(location: StoredLocation, watchIds: List<Int>, deliverLive: Boolean)
    fun onLocationError(message: String, watchIds: List<Int>)
  }

  private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
  private val database = LocationDatabase(context)
  private var callback: LocationCallback? = null
  private var isWatching = false
  private val watchIds = mutableSetOf<Int>()
  private var nextWatchId = 1

  private val prefs by lazy {
    context.getSharedPreferences("micim_geolocation", Context.MODE_PRIVATE)
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

  @SuppressLint("MissingPermission")
  fun getCurrentPosition(onResult: (Result<StoredLocation>) -> Unit) {
    fusedClient.lastLocation.addOnSuccessListener { loc ->
      if (loc == null) {
        onResult(Result.failure(Exception("No location available")))
        return@addOnSuccessListener
      }
      val stored = loc.toStored(delivered = true)
      database.insert(stored)
      onResult(Result.success(stored))
    }.addOnFailureListener { onResult(Result.failure(it)) }
  }

  @SuppressLint("MissingPermission")
  fun watchPosition(options: com.facebook.react.bridge.ReadableMap): Int {
    val id = nextWatchId++
    watchIds.add(id)
    startUpdates()
    prefs.edit().putBoolean("watch_active", true).apply()
    return id
  }

  @SuppressLint("MissingPermission")
  private fun startUpdates() {
    if (callback != null) return
    isWatching = true
    val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 3000)
      .setMinUpdateIntervalMillis(1000)
      .setMinUpdateDistanceMeters(5f)
      .build()

    callback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        val loc = result.lastLocation ?: return
        val deliverLive = isAppActive() && watchIds.isNotEmpty()
        val stored = loc.toStored(delivered = deliverLive)
        if (!database.insert(stored)) {
          listener.onLocationError("Failed to persist", watchIds.toList())
          return
        }
        if (deliverLive) {
          database.markDelivered(listOf(stored.id))
        }
        listener.onLocationPersisted(stored, watchIds.toList(), deliverLive)
      }
    }
    fusedClient.requestLocationUpdates(request, callback!!, Looper.getMainLooper())
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
    isWatching = false
    callback?.let { fusedClient.removeLocationUpdates(it) }
    callback = null
    prefs.edit().putBoolean("watch_active", false).apply()
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
