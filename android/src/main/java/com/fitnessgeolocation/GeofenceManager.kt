package com.fitnessgeolocation

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

/**
 * Hybrid geofencing: OS circular regions + in-app polygon evaluation.
 */
class GeofenceManager(private val context: Context) {
  companion object {
    const val ACTION_GEOFENCE = "com.fitnessgeolocation.GEOFENCE_EVENT"
    private const val TAG = "GeofenceManager"
    private const val MAX_ACTIVE_CIRCULAR = 100
  }

  private data class PolygonFence(
    val id: String,
    val data: Map<String, Any?>,
    val vertices: List<GeoMath.Point>,
    val bbox: DoubleArray,
    var inside: Boolean = false,
    var dwellStartMs: Long = 0L,
  )

  private val client: GeofencingClient = LocationServices.getGeofencingClient(context)
  private val store = linkedMapOf<String, Map<String, Any?>>()
  private val polygons = linkedMapOf<String, PolygonFence>()
  private var deviceLat: Double? = null
  private var deviceLng: Double? = null
  private var activeCircularIds = linkedSetOf<String>()

  var onGeofenceEvent: ((String, String, Map<String, Any?>) -> Unit)? = null
  var onGeofencesChange: ((List<String>, List<String>) -> Unit)? = null

  fun addGeofence(data: Map<String, Any?>): Boolean {
    val id = data["identifier"] as? String ?: return false
    val wasNew = !store.containsKey(id) && !polygons.containsKey(id)

    @Suppress("UNCHECKED_CAST")
    val verticesRaw = data["vertices"] as? List<Map<String, Any?>>
    if (verticesRaw != null && verticesRaw.size >= 3) {
      store.remove(id)
      client.removeGeofences(listOf(id))
      val verts = GeoMath.parseVertices(verticesRaw)
      val bbox = GeoMath.boundingBox(verts) ?: return false
      polygons[id] = PolygonFence(id, data, verts, bbox)
    } else {
      polygons.remove(id)
      store[id] = data
      refreshActiveCircular()
    }
    if (wasNew) onGeofencesChange?.invoke(listOf(id), emptyList())
    return true
  }

  fun addGeofences(list: List<Map<String, Any?>>): Boolean {
    list.forEach { addGeofence(it) }
    return true
  }

  fun removeGeofence(identifier: String): Boolean {
    store.remove(identifier)
    polygons.remove(identifier)
    client.removeGeofences(listOf(identifier))
    activeCircularIds.remove(identifier)
    refreshActiveCircular()
    onGeofencesChange?.invoke(emptyList(), listOf(identifier))
    return true
  }

  fun removeGeofences(identifiers: List<String>?) {
    if (identifiers != null) identifiers.forEach { removeGeofence(it) }
    else {
      val ids = (store.keys + polygons.keys).toList()
      store.clear(); polygons.clear()
      activeCircularIds.clear()
      if (ids.isNotEmpty()) client.removeGeofences(ids)
      onGeofencesChange?.invoke(emptyList(), ids)
    }
  }

  fun getGeofences(): List<Map<String, Any?>> = store.values.toList() + polygons.values.map { it.data }
  fun exists(identifier: String): Boolean = store.containsKey(identifier) || polygons.containsKey(identifier)

  fun handleTransition(identifier: String, transition: Int) {
    val data = store[identifier] ?: return
    val action = when (transition) {
      Geofence.GEOFENCE_TRANSITION_ENTER -> "ENTER"
      Geofence.GEOFENCE_TRANSITION_EXIT -> "EXIT"
      Geofence.GEOFENCE_TRANSITION_DWELL -> "DWELL"
      else -> return
    }
    onGeofenceEvent?.invoke(identifier, action, data)
  }

  /** Call on each GPS fix — O(P×V) with bbox reject; typical P≤20, V≤12. */
  fun evaluatePolygons(lat: Double, lng: Double) {
    val now = System.currentTimeMillis()
    for ((_, fence) in polygons) {
      if (!GeoMath.inBoundingBox(lat, lng, fence.bbox)) {
        if (fence.inside) {
          fence.inside = false
          if (fence.data["notifyOnExit"] as? Boolean != false) {
            onGeofenceEvent?.invoke(fence.id, "EXIT", fence.data)
          }
        }
        continue
      }
      val inside = GeoMath.pointInPolygon(lat, lng, fence.vertices)
      if (inside && !fence.inside) {
        fence.inside = true
        fence.dwellStartMs = now
        if (fence.data["notifyOnEntry"] as? Boolean != false) {
          onGeofenceEvent?.invoke(fence.id, "ENTER", fence.data)
        }
      } else if (!inside && fence.inside) {
        fence.inside = false
        if (fence.data["notifyOnExit"] as? Boolean != false) {
          onGeofenceEvent?.invoke(fence.id, "EXIT", fence.data)
        }
      } else if (inside && fence.inside && fence.data["notifyOnDwell"] as? Boolean == true) {
        val delay = (fence.data["loiteringDelayMs"] as? Number)?.toLong() ?: 30_000L
        if (now - fence.dwellStartMs >= delay) {
          onGeofenceEvent?.invoke(fence.id, "DWELL", fence.data)
          fence.dwellStartMs = now + delay // throttle dwell repeats
        }
      }
    }
  }

  /** Update device location (used for active-set selection). */
  fun updateDeviceLocation(lat: Double, lng: Double) {
    deviceLat = lat
    deviceLng = lng
    refreshActiveCircular()
  }

  private fun refreshActiveCircular() {
    if (store.isEmpty()) return
    val desired = linkedSetOf<String>()

    val lat0 = deviceLat
    val lng0 = deviceLng
    val scored = if (lat0 != null && lng0 != null) {
      store.mapNotNull { (id, data) ->
        val lat = (data["latitude"] as? Number)?.toDouble()
        val lng = (data["longitude"] as? Number)?.toDouble()
        if (lat == null || lng == null) return@mapNotNull null
        val d = GeoMath.haversineMeters(lat0, lng0, lat, lng)
        id to d
      }.sortedBy { it.second }
    } else {
      store.keys.mapIndexed { idx, id -> id to idx.toDouble() }
    }

    for ((id, _) in scored.take(MAX_ACTIVE_CIRCULAR)) desired.add(id)

    // remove stale
    val toStop = activeCircularIds.filter { !desired.contains(it) }
    if (toStop.isNotEmpty()) client.removeGeofences(toStop)

    // add new
    val toStart = desired.filter { !activeCircularIds.contains(it) }
    toStart.forEach { id ->
      val data = store[id] ?: return@forEach
      registerCircular(id, data)
    }

    activeCircularIds = desired
  }

  private fun registerCircular(id: String, data: Map<String, Any?>) {
    val lat = (data["latitude"] as? Number)?.toDouble() ?: return
    val lng = (data["longitude"] as? Number)?.toDouble() ?: return
    val radius = ((data["radius"] as? Number)?.toFloat() ?: 200f).coerceAtLeast(100f)
    var transition = 0
    if (data["notifyOnEntry"] as? Boolean != false) transition = transition or Geofence.GEOFENCE_TRANSITION_ENTER
    if (data["notifyOnExit"] as? Boolean != false) transition = transition or Geofence.GEOFENCE_TRANSITION_EXIT
    if (data["notifyOnDwell"] as? Boolean == true) transition = transition or Geofence.GEOFENCE_TRANSITION_DWELL
    val loitering = (data["loiteringDelayMs"] as? Number)?.toInt() ?: 0

    val geofence = Geofence.Builder()
      .setRequestId(id)
      .setCircularRegion(lat, lng, radius)
      .setTransitionTypes(transition)
      .setExpirationDuration(Geofence.NEVER_EXPIRE)
      .apply { if (loitering > 0) setLoiteringDelay(loitering) }
      .build()

    client.addGeofences(
      GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER).addGeofence(geofence).build(),
      pendingIntent(),
    ).addOnFailureListener { e -> Log.e(TAG, "addGeofence failed: ${e.message}") }
  }

  private fun pendingIntent(): PendingIntent {
    val intent = Intent(context, GeofenceBroadcastReceiver::class.java).apply { action = ACTION_GEOFENCE }
    return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
  }
}
