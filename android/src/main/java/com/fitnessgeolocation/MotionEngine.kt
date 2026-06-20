package com.fitnessgeolocation

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityRecognitionResult
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

  companion object {
    private const val TAG = "FitnessGeoMotion"
    private const val ACTION_ACTIVITY_DETECTED =
      "com.fitnessgeolocation.ACTION_ACTIVITY_DETECTED"

    fun activityName(type: Int): String = when (type) {
      DetectedActivity.ON_FOOT -> "walking"
      DetectedActivity.WALKING -> "walking"
      DetectedActivity.RUNNING -> "running"
      DetectedActivity.ON_BICYCLE -> "cycling"
      DetectedActivity.IN_VEHICLE -> "driving"
      DetectedActivity.STILL -> "stationary"
      DetectedActivity.TILTING -> "unknown"
      else -> "unknown"
    }

    fun isMovingActivity(activity: String): Boolean = when (activity) {
      "walking", "running", "cycling", "driving" -> true
      else -> false
    }
  }

  private val client = ActivityRecognition.getClient(context)
  private var pendingIntent: PendingIntent? = null
  private var receiverRegistered = false
  private val receiver = ActivityBroadcastReceiver()

  var autoPauseEnabled = true
  var autoPauseDelayMs: Long = 45_000
  private var stationarySince: Long = 0L
  private var currentActivity = "unknown"
  private var currentConfidence = 0
  private val handler = Handler(Looper.getMainLooper())
  private var autoPauseRunnable: Runnable? = null

  fun start() {
    registerReceiver()
    requestActivityUpdates()
    Log.d(TAG, "motion_tracking_started")
  }

  fun stop() {
    unregisterReceiver()
    pendingIntent?.let {
      client.removeActivityUpdates(it)
    }
    pendingIntent = null
    cancelAutoPauseTimer()
    Log.d(TAG, "motion_tracking_stopped")
  }

  fun currentActivityType(): String = currentActivity

  private fun onActivityDetected(activity: String, confidence: Int) {
    currentActivity = activity
    currentConfidence = confidence
    listener.onActivityChange(activity, confidence)

    if (activity == "stationary") {
      startAutoPauseTimer()
    } else if (isMovingActivity(activity)) {
      cancelAutoPauseTimer()
      stationarySince = 0L
      listener.onAutoResume()
    }
  }

  private fun startAutoPauseTimer() {
    cancelAutoPauseTimer()
    if (!autoPauseEnabled) return
    if (stationarySince == 0L) stationarySince = System.currentTimeMillis()

    val elapsed = System.currentTimeMillis() - stationarySince
    if (elapsed >= autoPauseDelayMs) {
      listener.onAutoPause()
      return
    }

    val remaining = autoPauseDelayMs - elapsed
    val r = Runnable {
      autoPauseRunnable = null
      listener.onAutoPause()
    }
    autoPauseRunnable = r
    handler.postDelayed(r, remaining)
  }

  private fun cancelAutoPauseTimer() {
    autoPauseRunnable?.let { handler.removeCallbacks(it) }
    autoPauseRunnable = null
  }

  @Suppress("InlinedApi")
  private fun registerReceiver() {
    if (receiverRegistered) return
    val filter = IntentFilter(ACTION_ACTIVITY_DETECTED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      context.registerReceiver(receiver, filter)
    }
    receiverRegistered = true
  }

  private fun unregisterReceiver() {
    if (!receiverRegistered) return
    try {
      context.unregisterReceiver(receiver)
    } catch (_: Exception) {}
    receiverRegistered = false
  }

  private fun requestActivityUpdates() {
    val intent = Intent(ACTION_ACTIVITY_DETECTED).apply {
      `package` = context.packageName
    }

    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    } else {
      PendingIntent.FLAG_UPDATE_CURRENT
    }

    pendingIntent = PendingIntent.getBroadcast(context, 0, intent, flags)

    pendingIntent?.let { pi ->
      client.requestActivityUpdates(3000, pi)
        .addOnSuccessListener { Log.d(TAG, "activity_updates_requested") }
        .addOnFailureListener { e -> Log.w(TAG, "activity_updates_failed: ${e.message}") }
    }
  }

  // ─── Broadcast Receiver ──────────────────────────────────────────────────

  inner class ActivityBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
      if (intent.action != ACTION_ACTIVITY_DETECTED) return

      val result = ActivityRecognitionResult.extractResult(intent) ?: return
      val activities = result.probableActivities
      if (activities.isNotEmpty()) {
        val mostProbable = activities[0]
        val name = activityName(mostProbable.type)
        val confidence = mostProbable.confidence
        onActivityDetected(name, confidence)
      }
    }
  }
}

/** Extension to check if activity name is stationary */
fun String.isStationaryActivity(): Boolean = this == "stationary"
