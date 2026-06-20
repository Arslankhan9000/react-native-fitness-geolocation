package com.fitnessgeolocation

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class FitnessLocationService : Service() {
  private lateinit var engine: LocationEngine
  private val tag = "FitnessGeoService"

  override fun onCreate() {
    super.onCreate()
    engine = LocationEngine.getInstance(applicationContext)
    Log.d(tag, "service_created")
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == ACTION_STOP) {
      stopForegroundService()
      return START_NOT_STICKY
    }

    try {
      startForegroundService()
    } catch (e: java.lang.Exception) {
      // Android 12+ ForegroundServiceStartNotAllowedException or similar
      Log.w(tag, "foreground_service_start_failed: ${e.message}")
      // The service will retry when startForegroundTrackingService() is called again
      // (each watchPosition/startTimeBasedTracking triggers it)
    }

    // START_STICKY is critical — Android will recreate the service if killed
    return START_STICKY
  }

  override fun onBind(intent: Intent?): IBinder? = null

  /**
   * Update the notification text dynamically (called from DebugMonitor
   * or ActivityManager when activity state changes).
   */
  fun updateNotificationText(title: String, text: String) {
    val builder = NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(resolveSmallIcon())
      .setContentTitle(title)
      .setContentText(text)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .setPriority(NotificationCompat.PRIORITY_LOW)

    val notification = builder.build()
    val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(NOTIFICATION_ID, notification)
  }

  override fun onDestroy() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
    Log.d(tag, "service_destroyed")
    super.onDestroy()
  }

  private fun startForegroundService() {
    ensureChannel()
    val prefs = getSharedPreferences("fitness_geolocation", MODE_PRIVATE)
    val notification = NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(resolveSmallIcon())
      .setContentTitle(prefs.getString("notification_title", "Tracking activity") ?: "Tracking activity")
      .setContentText(
        prefs.getString("notification_text", "Recording your route")
          ?: "Recording your route",
      )
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .build()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }

    Log.d(tag, "foreground_service_started")
  }

  private fun stopForegroundService() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
    stopSelf()
    Log.d(tag, "foreground_service_stopped")
  }

  private fun ensureChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(NotificationManager::class.java)
    if (manager.getNotificationChannel(CHANNEL_ID) != null) return

    val channel = NotificationChannel(
      CHANNEL_ID,
      "Activity tracking",
      NotificationManager.IMPORTANCE_LOW,
    )
    channel.description = "Keeps GPS active while a workout is being tracked"
    manager.createNotificationChannel(channel)
  }

  private fun resolveSmallIcon(): Int {
    val icon = applicationInfo.icon
    return if (icon != 0) icon else android.R.drawable.ic_menu_mylocation
  }

  companion object {
    const val ACTION_START = "com.fitnessgeolocation.action.START"
    const val ACTION_STOP = "com.fitnessgeolocation.action.STOP"
    private const val CHANNEL_ID = "fitness_geolocation_tracking"
    private const val NOTIFICATION_ID = 48291
  }
}
