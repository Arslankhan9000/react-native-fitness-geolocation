package com.fitnessgeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceBroadcastReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val event = GeofencingEvent.fromIntent(intent)
    if (event == null || event.hasError()) {
      Log.e("GeofenceReceiver", "geofence error: ${event?.errorCode}")
      return
    }
    val transition = event.geofenceTransition
    event.triggeringGeofences?.forEach { geofence ->
      LocationEngine.getInstance(context).handleGeofenceTransition(geofence.requestId, transition)
    }
  }
}
