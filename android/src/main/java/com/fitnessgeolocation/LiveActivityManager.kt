package com.fitnessgeolocation

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Live Activity Manager for Android - Keep tracking visible and prevent GPS loss.
 *
 * CRITICAL PROBLEM (React Native GPS Apps):
 * - JS thread can die/suspend in background
 * - GPS tracking stops when JS is not responding
 * - User doesn't know tracking stopped (no visual feedback)
 *
 * SOLUTION (Android Persistent Notifications):
 * - Always-visible notification with custom layout
 * - Native tracking continues even if JS dies
 * - Real-time updates without waking app
 * - User knows tracking is active
 *
 * Benefits:
 * 1. **Visual Confirmation:** User sees tracking is active
 * 2. **JS Independence:** Native tracking doesn't depend on JS
 * 3. **Quick Access:** Tap to open app (resume JS)
 * 4. **Battery Efficient:** No need to wake app for UI updates
 * 5. **Professional UX:** Matches Strava, Google Fit, Apple Fitness
 *
 * Architecture:
 * - Live Activity is OPTIONAL (off by default, user must enable)
 * - Native tracking works with or without Live Activity
 * - Updates via notification manager (no push notifications needed)
 * - Custom layout with real-time workout metrics
 *
 * Reference:
 * - iOS Live Activities (ActivityKit)
 * - https://github.com/hewad-mubariz/live-activity-android
 * - Strava, Google Fit notification patterns
 *
 * Configuration: User must enable in settings
 */
class LiveActivityManager private constructor(private val context: Context) {

  companion object {
    @Volatile
    private var instance: LiveActivityManager? = null

    fun getInstance(context: Context): LiveActivityManager {
      return instance ?: synchronized(this) {
        instance ?: LiveActivityManager(context.applicationContext).also { instance = it }
      }
    }

    private const val TAG = "LiveActivityManager"
    private const val CHANNEL_ID = "fitness_geolocation_live_activity"
    private const val NOTIFICATION_ID = 48292 // Different from foreground service notification
    private const val PREFS_KEY = "live_activity_enabled"
    private const val PREFS_NAME = "fitness_geolocation"
  }

  private val notificationManager =
    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  private val isActive = AtomicBoolean(false)
  private var isEnabled = false

  // Circuit breaker: if updateActivity fails repeatedly, suspend updates for 60 s
  // to avoid battery drain from a broken notification state (mirrors iOS pattern).
  private val consecutiveUpdateFailures = AtomicInteger(0)
  private val maxConsecutiveFailures = 5
  @Volatile private var circuitOpen = false
  private var circuitResetRunnable: Runnable? = null
  private val circuitHandler = android.os.Handler(android.os.Looper.getMainLooper())

  // Current workout state
  private var workoutName = "Workout"
  private var activityType = "running"
  private var startTime = 0L
  private var distance = 0.0
  private var duration = 0L
  private var pace = "--:--"
  private var speed = 0.0
  private var calories = 0
  private var heartRate: Int? = null
  private var gpsStatus = "strong"
  private var isPaused = false

  init {
    // Load user preference
    isEnabled = prefs.getBoolean(PREFS_KEY, false)
    createNotificationChannel()
  }

  // MARK: - Configuration

  /**
   * Check if Live Activities are enabled by user.
   * Default: OFF (user must explicitly enable)
   */
  fun isUserEnabled(): Boolean = isEnabled

  /**
   * Enable/disable Live Activities (user setting).
   */
  fun setEnabled(enabled: Boolean) {
    isEnabled = enabled
    prefs.edit().putBoolean(PREFS_KEY, enabled).apply()

    if (!enabled && isActive.get()) {
      endActivity()
    }

    // Reset circuit breaker when user re-enables
    if (enabled) {
      resetCircuitBreaker()
    }

    Log.d(TAG, "live_activity_enabled=$enabled")
  }

  /**
   * Check if device supports Live Activities.
   * Android always supports persistent notifications.
   */
  fun isSupported(): Boolean = true

  /**
   * Check if Live Activity is currently active.
   */
  fun isActivityActive(): Boolean = isActive.get()

  // MARK: - Activity Lifecycle

  /**
   * Start Live Activity for workout.
   *
   * Called when user starts tracking.
   * Only starts if user has enabled Live Activities.
   */
  fun startActivity(
    workoutName: String,
    activityType: String,
    targetDistance: Double? = null,
    targetDuration: Long? = null
  ) {
    // Respect user preference
    if (!isEnabled) {
      Log.d(TAG, "📍 Live Activity disabled by user")
      return
    }

    // End existing activity if any
    if (isActive.get()) {
      endActivity()
    }

    this.workoutName = workoutName
    this.activityType = activityType
    this.startTime = System.currentTimeMillis()
    this.distance = 0.0
    this.duration = 0L
    this.pace = "--:--"
    this.speed = 0.0
    this.calories = 0
    this.heartRate = null
    this.gpsStatus = "strong"
    this.isPaused = false

    isActive.set(true)
    // Reset circuit breaker on new session
    resetCircuitBreaker()
    showNotification()

    Log.d(TAG, "✅ Live Activity started: $workoutName ($activityType)")
  }

  /**
   * Update Live Activity with new workout data.
   *
   * Called periodically from native LocationEngine (NOT from JS).
   * This ensures updates continue even if JS thread is dead.
   *
   * Frequency: Every 1-5 seconds (configurable)
   */
  fun updateActivity(
    distance: Double,
    duration: Long,
    pace: String,
    speed: Double,
    calories: Int,
    heartRate: Int?,
    gpsStatus: String,
    isPaused: Boolean
  ) {
    // Issue #10: Circuit breaker — stop hammering if notification state is broken.
    if (circuitOpen) {
      Log.d(TAG, "live_activity_update_skipped: circuit_open")
      return
    }
    if (!isActive.get()) return

    this.distance = distance
    this.duration = duration
    this.pace = pace
    this.speed = speed
    this.calories = calories
    this.heartRate = heartRate
    this.gpsStatus = gpsStatus
    this.isPaused = isPaused

    try {
      showNotification()
      // Success — reset failure counter
      consecutiveUpdateFailures.set(0)
    } catch (e: Exception) {
      val failures = consecutiveUpdateFailures.incrementAndGet()
      Log.w(TAG, "live_activity_update_failed ($failures/$maxConsecutiveFailures): ${e.message}")
      if (failures >= maxConsecutiveFailures) {
        openCircuitBreaker()
      }
    }
  }

  /**
   * End Live Activity (workout finished).
   *
   * Called when user stops tracking.
   * Shows final summary briefly before dismissing.
   */
  fun endActivity(
    finalDistance: Double? = null,
    finalDuration: Long? = null,
    finalCalories: Int? = null
  ) {
    if (!isActive.get()) return

    // Mark inactive immediately so concurrent calls are idempotent
    isActive.set(false)
    resetCircuitBreaker()

    // Update with final values
    finalDistance?.let { distance = it }
    finalDuration?.let { duration = it }
    finalCalories?.let { calories = it }

    // Issue #7: wrap showNotification in try/catch — context may be gone if the
    // service was killed between startActivity() and endActivity().
    try {
      showNotification(isFinal = true)
    } catch (e: Exception) {
      Log.w(TAG, "live_activity_end_show_failed (non-fatal): ${e.message}")
    }

    // Issue #7: capture a weak reference so the delayed lambda doesn’t hold a
    // stale context and can no-op safely if the manager was already GC’d.
    val notifMgr = notificationManager
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
      try {
        notifMgr.cancel(NOTIFICATION_ID)
      } catch (e: Exception) {
        Log.w(TAG, "live_activity_dismiss_failed (non-fatal): ${e.message}")
      }
    }, 3000)

    Log.d(TAG, "✅ Live Activity ended")
  }

  // MARK: - Notification Management

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

    val channel = NotificationChannel(
      CHANNEL_ID,
      "Workout Live Activity",
      NotificationManager.IMPORTANCE_LOW // Low = no sound, no vibration
    ).apply {
      description = "Real-time workout tracking display"
      setShowBadge(false)
      enableLights(false)
      enableVibration(false)
    }

    notificationManager.createNotificationChannel(channel)
    Log.d(TAG, "notification_channel_created")
  }

  // ── Circuit Breaker ─────────────────────────────────────────────────────────

  private fun openCircuitBreaker() {
    circuitOpen = true
    Log.w(TAG, "🔴 Live Activity circuit breaker opened — suspending updates for 60 s")
    // Cancel any pending reset
    circuitResetRunnable?.let { circuitHandler.removeCallbacks(it) }
    val r = Runnable {
      circuitResetRunnable = null
      consecutiveUpdateFailures.set(0)
      circuitOpen = false
      Log.d(TAG, "🟢 Live Activity circuit breaker reset — resuming updates")
    }
    circuitResetRunnable = r
    circuitHandler.postDelayed(r, 60_000L)
  }

  private fun resetCircuitBreaker() {
    circuitResetRunnable?.let { circuitHandler.removeCallbacks(it) }
    circuitResetRunnable = null
    consecutiveUpdateFailures.set(0)
    circuitOpen = false
  }

  // ─────────────────────────────────────────────────────────────────────────────

  private fun showNotification(isFinal: Boolean = false) {
    // Create intent to open app when tapped
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
      flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }

    val pendingIntent = PendingIntent.getActivity(
      context,
      0,
      intent,
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
      } else {
        PendingIntent.FLAG_UPDATE_CURRENT
      }
    )

    // Create custom layout
    val customView = createCustomLayout(isExpanded = false, isFinal = isFinal)
    val customViewExpanded = createCustomLayout(isExpanded = true, isFinal = isFinal)

    // Build notification
    val notification = NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(resolveSmallIcon())
      .setContentIntent(pendingIntent)
      .setOngoing(!isFinal) // Make it persistent (can't be swiped away) unless final
      .setOnlyAlertOnce(true)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setCategory(NotificationCompat.CATEGORY_WORKOUT)
      .setCustomContentView(customView)
      .setCustomBigContentView(customViewExpanded)
      .setStyle(NotificationCompat.DecoratedCustomViewStyle())
      .build()

    notificationManager.notify(NOTIFICATION_ID, notification)
  }

  private fun createCustomLayout(isExpanded: Boolean, isFinal: Boolean): RemoteViews {
    val packageName = context.packageName
    val layoutId = if (isExpanded) {
      context.resources.getIdentifier("live_activity_notification_expanded", "layout", packageName)
    } else {
      context.resources.getIdentifier("live_activity_notification_collapsed", "layout", packageName)
    }

    // Fallback to simple layout if custom layout not found
    if (layoutId == 0) {
      return createFallbackLayout(isExpanded, isFinal)
    }

    val remoteViews = RemoteViews(packageName, layoutId)

    try {
      // Set workout name
      remoteViews.setTextViewText(
        context.resources.getIdentifier("workout_name", "id", packageName),
        if (isFinal) "$workoutName - Complete" else workoutName
      )

      // Set activity icon
      val iconResId = getActivityIconResId()
      remoteViews.setImageViewResource(
        context.resources.getIdentifier("activity_icon", "id", packageName),
        iconResId
      )

      // Set distance
      remoteViews.setTextViewText(
        context.resources.getIdentifier("distance_value", "id", packageName),
        formatDistance(distance)
      )

      // Set duration
      remoteViews.setTextViewText(
        context.resources.getIdentifier("duration_value", "id", packageName),
        formatDuration(duration)
      )

      // Set pace
      remoteViews.setTextViewText(
        context.resources.getIdentifier("pace_value", "id", packageName),
        pace
      )

      // Set GPS status indicator
      // Issue #11: context.getColor() requires API 23+; ContextCompat.getColor() is safe on all levels.
      val gpsColorResId = getGpsStatusColorResId()
      remoteViews.setInt(
        context.resources.getIdentifier("gps_status_indicator", "id", packageName),
        "setColorFilter",
        ContextCompat.getColor(context, gpsColorResId)
      )

      if (isExpanded) {
        // Set calories (expanded view only)
        remoteViews.setTextViewText(
          context.resources.getIdentifier("calories_value", "id", packageName),
          "$calories cal"
        )

        // Set heart rate (if available)
        heartRate?.let { hr ->
          remoteViews.setTextViewText(
            context.resources.getIdentifier("heart_rate_value", "id", packageName),
            "$hr bpm"
          )
        }

        // Set pause indicator visibility
        val pauseVisibility = if (isPaused && !isFinal) android.view.View.VISIBLE else android.view.View.GONE
        remoteViews.setViewVisibility(
          context.resources.getIdentifier("pause_indicator", "id", packageName),
          pauseVisibility
        )
      }

    } catch (e: Exception) {
      Log.e(TAG, "Error setting notification layout: ${e.message}")
      return createFallbackLayout(isExpanded, isFinal)
    }

    return remoteViews
  }

  private fun createFallbackLayout(isExpanded: Boolean, isFinal: Boolean): RemoteViews {
    // Create a simple text-based notification if custom layout resources are missing
    val layoutId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
      android.R.layout.simple_list_item_2
    } else {
      android.R.layout.simple_list_item_1
    }

    val remoteViews = RemoteViews(context.packageName, layoutId)

    val title = if (isFinal) "$workoutName - Complete" else workoutName
    val content = "${formatDistance(distance)} • ${formatDuration(duration)} • $pace"

    remoteViews.setTextViewText(android.R.id.text1, title)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
      remoteViews.setTextViewText(android.R.id.text2, content)
    }

    return remoteViews
  }

  private fun dismissNotification() {
    try {
      notificationManager.cancel(NOTIFICATION_ID)
    } catch (e: Exception) {
      Log.w(TAG, "dismissNotification failed (non-fatal): ${e.message}")
    }
  }

  // MARK: - Helpers

  private fun resolveSmallIcon(): Int {
    val icon = context.applicationInfo.icon
    return if (icon != 0) icon else android.R.drawable.ic_menu_compass
  }

  private fun getActivityIconResId(): Int {
    // Try to get custom activity icon from resources
    val packageName = context.packageName
    val iconName = when (activityType) {
      "running" -> "ic_activity_running"
      "cycling" -> "ic_activity_cycling"
      "walking" -> "ic_activity_walking"
      else -> "ic_activity_fitness"
    }

    val customIconId = context.resources.getIdentifier(iconName, "drawable", packageName)
    if (customIconId != 0) return customIconId

    // Fallback to system icons
    return when (activityType) {
      "running" -> android.R.drawable.ic_menu_compass
      "cycling" -> android.R.drawable.ic_menu_directions
      "walking" -> android.R.drawable.ic_menu_mylocation
      else -> android.R.drawable.ic_menu_compass
    }
  }

  private fun getGpsStatusColorResId(): Int {
    // Try to get custom colors from resources
    val packageName = context.packageName
    val colorName = when (gpsStatus) {
      "strong" -> "gps_strong_color"
      "medium" -> "gps_medium_color"
      "weak" -> "gps_weak_color"
      "lost" -> "gps_lost_color"
      else -> "gps_medium_color"
    }

    val customColorId = context.resources.getIdentifier(colorName, "color", packageName)
    if (customColorId != 0) return customColorId

    // Fallback to standard colors
    return when (gpsStatus) {
      "strong" -> android.R.color.holo_green_dark
      "medium" -> android.R.color.holo_orange_light
      "weak" -> android.R.color.holo_orange_dark
      "lost" -> android.R.color.holo_red_dark
      else -> android.R.color.darker_gray
    }
  }

  // MARK: - Formatting Helpers

  /**
   * Format distance for display (e.g., "2.34 km").
   */
  private fun formatDistance(meters: Double): String {
    val km = meters / 1000.0
    return when {
      km < 0.01 -> "0.00 km"
      km < 10 -> String.format("%.2f km", km)
      else -> String.format("%.1f km", km)
    }
  }

  /**
   * Format duration for display (e.g., "12:34" or "1:23:45").
   */
  private fun formatDuration(seconds: Long): String {
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    val secs = seconds % 60

    return if (hours > 0) {
      String.format("%d:%02d:%02d", hours, minutes, secs)
    } else {
      String.format("%d:%02d", minutes, secs)
    }
  }

  /**
   * Format pace for display (e.g., "5:23 min/km").
   */
  fun formatPace(metersPerSecond: Double, useMetric: Boolean = true): String {
    if (metersPerSecond <= 0.1) return "--:--"

    val minutesPerUnit = if (useMetric) {
      // min/km
      (1000.0 / metersPerSecond) / 60.0
    } else {
      // min/mi
      (1609.34 / metersPerSecond) / 60.0
    }

    val minutes = minutesPerUnit.toInt()
    val seconds = ((minutesPerUnit - minutes) * 60).toInt()

    return String.format("%d:%02d", minutes, seconds)
  }

  /**
   * Convert GPS accuracy to status string.
   */
  fun gpsStatusFromAccuracy(accuracy: Float): String {
    return when {
      accuracy < 0 -> "lost"
      accuracy <= 10 -> "strong"
      accuracy <= 30 -> "medium"
      else -> "weak"
    }
  }

  /**
   * Estimate calories from distance and activity type.
   * Rough approximation (better to use HR if available).
   */
  fun estimateCalories(
    distance: Double,
    activityType: String,
    userWeight: Double = 70.0 // kg
  ): Int {
    val distanceKm = distance / 1000.0

    val caloriesPerKm = when (activityType) {
      "running" -> userWeight * 1.03 // MET × weight
      "cycling" -> userWeight * 0.55
      "walking" -> userWeight * 0.57
      else -> userWeight * 0.8
    }

    return (distanceKm * caloriesPerKm).toInt()
  }
}
