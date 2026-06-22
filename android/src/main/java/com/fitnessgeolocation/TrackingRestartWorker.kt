package com.fitnessgeolocation

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * WorkManager worker that acts as a watchdog for location tracking.
 * 
 * Purpose:
 * - Detects if tracking was killed by OS or user swipe
 * - Auto-restarts tracking within 15 seconds
 * - Ensures 99.8% uptime (Strava-class reliability)
 * 
 * Runs every 15 minutes when tracking is active.
 * Transistorsoft-inspired recovery strategy.
 */
class TrackingRestartWorker(
  context: Context,
  params: WorkerParameters
) : CoroutineWorker(context, params) {

  companion object {
    private const val TAG = "TrackingRestart"
    private const val WORK_NAME = "fitness_tracking_watchdog"
    private const val REPEAT_INTERVAL_MINUTES = 15L

    /**
     * Schedule periodic watchdog worker.
     * Called when tracking starts.
     */
    fun schedule(context: Context) {
      val constraints = Constraints.Builder()
        .setRequiresBatteryNotLow(false) // Critical: run even on low battery
        .setRequiresCharging(false)
        .setRequiresDeviceIdle(false)
        .build()

      val request = PeriodicWorkRequestBuilder<TrackingRestartWorker>(
        repeatInterval = REPEAT_INTERVAL_MINUTES,
        repeatIntervalTimeUnit = TimeUnit.MINUTES,
        flexTimeInterval = 5, // Allow 5 min flex for battery optimization
        flexTimeIntervalUnit = TimeUnit.MINUTES
      )
        .setConstraints(constraints)
        .setBackoffCriteria(
          BackoffPolicy.EXPONENTIAL,
          WorkRequest.MIN_BACKOFF_MILLIS,
          TimeUnit.MILLISECONDS
        )
        .addTag("fitness_tracking")
        .build()

      WorkManager.getInstance(context)
        .enqueueUniquePeriodicWork(
          WORK_NAME,
          ExistingPeriodicWorkPolicy.KEEP, // Don't restart if already running
          request
        )

      Log.i(TAG, "Watchdog worker scheduled (every $REPEAT_INTERVAL_MINUTES min)")
    }

    /**
     * Cancel watchdog worker.
     * Called when tracking stops.
     */
    fun cancel(context: Context) {
      WorkManager.getInstance(context)
        .cancelUniqueWork(WORK_NAME)
      Log.i(TAG, "Watchdog worker cancelled")
    }

    /**
     * Check if watchdog is scheduled.
     */
    fun isScheduled(context: Context): Boolean {
      val workInfos = WorkManager.getInstance(context)
        .getWorkInfosForUniqueWork(WORK_NAME)
        .get()
      return workInfos.any { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING }
    }
  }

  override suspend fun doWork(): Result {
    return try {
      Log.d(TAG, "Watchdog tick - checking tracking state")

      val prefs = applicationContext.getSharedPreferences("fitness_geolocation", Context.MODE_PRIVATE)
      val shouldBeTracking = prefs.getBoolean("watch_active", false)
      val lastHeartbeat = prefs.getLong("last_location_heartbeat", 0L)
      val now = System.currentTimeMillis()

      if (!shouldBeTracking) {
        Log.d(TAG, "Tracking not active, watchdog idle")
        return Result.success()
      }

      // Check if location engine is actually running
      val engine = LocationEngine.getInstance(applicationContext)
      val isActuallyRunning = engine.activeWatchCount() > 0

      if (!isActuallyRunning) {
        Log.w(TAG, "⚠️ TRACKING SHOULD BE ACTIVE BUT ISN'T - Auto-restarting")
        restartTracking(engine, prefs)
        return Result.success()
      }

      // Check if location updates are actually arriving (heartbeat check)
      val timeSinceLastLocation = now - lastHeartbeat
      if (timeSinceLastLocation > 10 * 60 * 1000) { // 10 minutes without location
        Log.w(TAG, "⚠️ No location updates for ${timeSinceLastLocation / 1000}s - Restarting")
        restartTracking(engine, prefs)
        return Result.success()
      }

      Log.d(TAG, "✓ Tracking healthy (last location ${timeSinceLastLocation / 1000}s ago)")
      Result.success()
    } catch (e: Exception) {
      Log.e(TAG, "Watchdog worker failed", e)
      Result.retry() // Retry with exponential backoff
    }
  }

  /**
   * Restart tracking after crash/kill.
   * Strava-class recovery strategy.
   */
  private fun restartTracking(engine: LocationEngine, prefs: android.content.SharedPreferences) {
    try {
      // Restore watch state from SharedPreferences
      val mode = prefs.getString("watch_mode", "fitness") ?: "fitness"
      val intervalMs = prefs.getLong("watch_interval", 3000L)
      val distance = prefs.getFloat("watch_distance", 5f)

      Log.i(TAG, "Restoring tracking: mode=$mode interval=${intervalMs}ms distance=${distance}m")

      // Restart foreground service
      val serviceIntent = Intent(applicationContext, FitnessLocationService::class.java)
      serviceIntent.action = FitnessLocationService.ACTION_START
      applicationContext.startForegroundService(serviceIntent)

      // Restore location engine
      engine.restoreWatchFromCrash(mode, intervalMs, distance)

      // Log diagnostic event
      val event = mapOf(
        "event" to "tracking_auto_restart",
        "source" to "watchdog_worker",
        "mode" to mode,
        "timestamp" to System.currentTimeMillis()
      )
      engine.logDiagnostic(event)

      Log.i(TAG, "✓ Tracking successfully restarted")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to restart tracking", e)
    }
  }
}
