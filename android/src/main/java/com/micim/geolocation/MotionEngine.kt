package com.micim.geolocation

import android.content.Context
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.DetectedActivity

class MotionEngine(
  private val context: Context,
  private val listener: Listener,
) {
  interface Listener {
    fun onActivityChange(activity: String, confidence: Int)
    fun onAutoPause()
    fun onAutoResume()
  }

  private val client = ActivityRecognition.getClient(context)
  private var pendingIntent: android.app.PendingIntent? = null

  var autoPauseEnabled = true
  var autoPauseDelayMs = 45_000L
  private var stationarySince = 0L

  fun start() {
    // Activity transitions handled via broadcast receiver in full impl
    // For V2 scaffold, motion state derived from GPS speed in LocationEngine
  }

  fun stop() {
    pendingIntent?.let { client.removeActivityUpdates(it) }
    pendingIntent = null
  }

  companion object {
    fun activityName(type: Int): String = when (type) {
      DetectedActivity.ON_FOOT -> "walking"
      DetectedActivity.WALKING -> "walking"
      DetectedActivity.RUNNING -> "running"
      DetectedActivity.ON_BICYCLE -> "cycling"
      DetectedActivity.IN_VEHICLE -> "driving"
      DetectedActivity.STILL -> "stationary"
      else -> "unknown"
    }
  }
}
