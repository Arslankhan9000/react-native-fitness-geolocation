package com.fitnessgeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot Completed Receiver - Auto-restart tracking after device reboot.
 * 
 * Industry standard (Strava, Garmin, Apple Fitness all implement this):
 * - Listens for BOOT_COMPLETED broadcast
 * - Checks if tracking was active before reboot
 * - Restarts tracking automatically
 * - Critical for multi-day activities (ultra-marathons, bike tours)
 * 
 * Required permission:
 * <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
 */
class BootCompletedReceiver : BroadcastReceiver() {

  companion object {
    private const val TAG = "BootCompletedRx"
  }

  override fun onReceive(context: Context, intent: Intent?) {
    if (intent?.action != Intent.ACTION_BOOT_COMPLETED) {
      return
    }

    Log.i(TAG, "Device rebooted - checking if tracking should resume")

    val prefs = context.getSharedPreferences("fitness_geolocation", Context.MODE_PRIVATE)
    val wasTracking = prefs.getBoolean("watch_active", false)
    val sessionId = prefs.getString("active_session_id", null)

    if (!wasTracking) {
      Log.d(TAG, "No active tracking before reboot")
      return
    }

    Log.i(TAG, "⚡ Auto-resuming tracking after reboot (session=$sessionId)")

    try {
      // Start foreground service
      val serviceIntent = Intent(context, FitnessLocationService::class.java)
      serviceIntent.action = FitnessLocationService.ACTION_START
      
      // Must use startForegroundService on Android O+
      context.startForegroundService(serviceIntent)

      // Restore tracking state
      val engine = LocationEngine.getInstance(context)
      val mode = prefs.getString("watch_mode", "fitness") ?: "fitness"
      val intervalMs = prefs.getLong("watch_interval", 3000L)
      val distance = prefs.getFloat("watch_distance", 5f)

      engine.restoreWatchFromCrash(mode, intervalMs, distance)

      // Update notification
      val notification = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
      
      // Log diagnostic
      val event = mapOf(
        "event" to "tracking_resumed_after_boot",
        "session_id" to (sessionId ?: "unknown"),
        "timestamp" to System.currentTimeMillis()
      )
      engine.logDiagnostic(event)

      // Schedule watchdog
      TrackingRestartWorker.schedule(context)

      Log.i(TAG, "✓ Tracking successfully resumed after reboot")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to resume tracking after reboot", e)
      
      // Critical: Don't fail silently - show notification
      showResumeFailed(context, e.message)
    }
  }

  /**
   * Show notification if tracking resume failed.
   * User needs to know their workout tracking didn't auto-resume.
   */
  private fun showResumeFailed(context: Context, error: String?) {
    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) 
      as android.app.NotificationManager

    // Create notification channel if needed (Android O+)
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      val channel = android.app.NotificationChannel(
        "fitness_errors",
        "Tracking Errors",
        android.app.NotificationManager.IMPORTANCE_HIGH
      )
      notificationManager.createNotificationChannel(channel)
    }

    val notification = androidx.core.app.NotificationCompat.Builder(context, "fitness_errors")
      .setSmallIcon(android.R.drawable.ic_dialog_alert)
      .setContentTitle("Workout Tracking Paused")
      .setContentText("Device rebooted. Please open the app to resume tracking.")
      .setStyle(
        androidx.core.app.NotificationCompat.BigTextStyle()
          .bigText("Your device rebooted and automatic tracking resume failed. Please open the app and manually resume your workout.\n\nError: $error")
      )
      .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .build()

    notificationManager.notify(48293, notification)  // 48292 is reserved for LiveActivityManager
  }
}
