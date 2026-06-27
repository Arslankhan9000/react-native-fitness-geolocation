package com.fitnessgeolocation

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * Battery Optimization Manager - Request Doze Mode exemption.
 * 
 * Critical for background GPS tracking:
 * - Android Doze Mode throttles GPS updates after 30-60 min screen-off
 * - Industry standard: Request REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
 * - Strava, Garmin, Google Maps all request this permission
 * 
 * Fallback strategy if denied:
 * - Use AlarmManager to wake app periodically
 * - Reduce update frequency
 * - Show warning to user
 */
object BatteryOptimizationManager {

  private const val TAG = "BatteryOptimization"

  /**
   * Check if app is exempted from battery optimization.
   * 
   * @return true if exempted or not applicable (< Android M)
   */
  fun isIgnoringBatteryOptimizations(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      return true // Not applicable on older Android
    }

    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    val packageName = context.packageName
    return pm.isIgnoringBatteryOptimizations(packageName)
  }

  /**
   * Check if we CAN request battery optimization exemption.
   * 
   * Google Play policy:
   * - Only certain app types can request this
   * - Fitness/health apps ARE allowed
   * - Must be declared in manifest
   */
  @RequiresApi(Build.VERSION_CODES.M)
  fun canRequestBatteryOptimization(context: Context): Boolean {
    val pm = context.packageManager
    val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      pm.getPackageInfo(
        context.packageName,
        android.content.pm.PackageManager.PackageInfoFlags.of(
          android.content.pm.PackageManager.GET_PERMISSIONS.toLong(),
        ),
      )
    } else {
      @Suppress("DEPRECATION")
      pm.getPackageInfo(context.packageName, android.content.pm.PackageManager.GET_PERMISSIONS)
    }
    val permissions = info.requestedPermissions ?: return false
    return permissions.contains(android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
  }

  /**
   * Request battery optimization exemption.
   * 
   * Shows system dialog asking user to allow.
   * This is the same flow Strava uses.
   * 
   * @param activity Required for startActivityForResult
   * @param requestCode Request code for result callback
   */
  @SuppressLint("BatteryLife")
  @RequiresApi(Build.VERSION_CODES.M)
  fun requestIgnoreBatteryOptimizations(activity: Activity, requestCode: Int) {
    if (isIgnoringBatteryOptimizations(activity)) {
      Log.d(TAG, "Already exempted from battery optimization")
      return
    }

    if (!canRequestBatteryOptimization(activity)) {
      Log.e(TAG, "Cannot request battery optimization - permission not in manifest")
      return
    }

    Log.i(TAG, "Requesting battery optimization exemption")

    try {
      val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
      intent.data = Uri.parse("package:${activity.packageName}")
      activity.startActivityForResult(intent, requestCode)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to request battery optimization", e)
      // Fallback: Open battery settings page
      openBatterySettings(activity)
    }
  }

  /**
   * Open battery settings page as fallback.
   * User can manually whitelist the app.
   */
  fun openBatterySettings(context: Context) {
    try {
      val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
      intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
      context.startActivity(intent)
    } catch (e: Exception) {
      Log.e(TAG, "Failed to open battery settings", e)
    }
  }

  /**
   * Get user-friendly explanation for why we need exemption.
   * Show this in a dialog before requesting.
   */
  fun getExplanationMessage(context: Context): String {
    return """
      |Background Location Tracking
      |
      |To accurately track your workouts with the screen off, we need permission to run in the background without restrictions.
      |
      |Without this permission:
      |• GPS tracking will stop after 30-60 minutes
      |• Your workout data may be incomplete
      |• Battery usage will be higher (GPS restarts repeatedly)
      |
      |We only use GPS during active workouts, not all the time.
      |
      |Apps like Strava, Garmin, and Apple Fitness use the same permission for the same reason.
    """.trimMargin()
  }

  /**
   * Log current battery optimization state for diagnostics.
   */
  fun logDiagnostics(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
      Log.d(TAG, "Battery optimization: N/A (Android < M)")
      return
    }

    val isExempted = isIgnoringBatteryOptimizations(context)
    val canRequest = canRequestBatteryOptimization(context)
    
    Log.d(TAG, "Battery optimization state:")
    Log.d(TAG, "  - Exempted: $isExempted")
    Log.d(TAG, "  - Can request: $canRequest")
    Log.d(TAG, "  - Manufacturer: ${Build.MANUFACTURER}")
    Log.d(TAG, "  - Model: ${Build.MODEL}")
    Log.d(TAG, "  - Android: ${Build.VERSION.RELEASE}")

    // Check for aggressive battery savers (Xiaomi, Huawei, Samsung, OnePlus)
    checkManufacturerRestrictions(context)
  }

  /**
   * Check for manufacturer-specific battery restrictions.
   * 
   * Some manufacturers (Xiaomi, Huawei, OnePlus) have additional
   * battery saving features beyond standard Android Doze Mode.
   */
  private fun checkManufacturerRestrictions(context: Context) {
    val manufacturer = Build.MANUFACTURER.lowercase()
    
    val warning = when {
      manufacturer.contains("xiaomi") -> {
        "Xiaomi device detected. Please also disable MIUI's battery saver in Settings > Battery > App battery saver."
      }
      manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
        "Huawei device detected. Please also disable power management in Settings > Battery > App launch."
      }
      manufacturer.contains("samsung") -> {
        "Samsung device detected. Please add this app to 'Never sleeping apps' in Settings > Battery."
      }
      manufacturer.contains("oneplus") || manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
        "OnePlus/OPPO device detected. Please disable battery optimization in Settings > Battery > Battery optimization."
      }
      else -> null
    }

    if (warning != null) {
      Log.w(TAG, "⚠️ $warning")
    }
  }

  /**
   * Check if device is in Doze Mode right now.
   * Useful for diagnostics.
   */
  @RequiresApi(Build.VERSION_CODES.M)
  fun isDeviceIdleMode(context: Context): Boolean {
    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    return pm.isDeviceIdleMode
  }

  /**
   * Get battery restriction info for diagnostics.
   */
  @RequiresApi(Build.VERSION_CODES.P)
  fun getBatteryRestrictionInfo(context: Context): String {
    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    val locationMode = pm.locationPowerSaveMode
    
    return when (locationMode) {
      PowerManager.LOCATION_MODE_NO_CHANGE -> "No GPS restriction"
      PowerManager.LOCATION_MODE_GPS_DISABLED_WHEN_SCREEN_OFF -> "⚠️ GPS disabled when screen off"
      PowerManager.LOCATION_MODE_ALL_DISABLED_WHEN_SCREEN_OFF -> "🔴 All location disabled when screen off"
      PowerManager.LOCATION_MODE_FOREGROUND_ONLY -> "⚠️ Background location restricted"
      PowerManager.LOCATION_MODE_THROTTLE_REQUESTS_WHEN_SCREEN_OFF -> "⚠️ GPS throttled when screen off"
      else -> "Unknown ($locationMode)"
    }
  }
}
