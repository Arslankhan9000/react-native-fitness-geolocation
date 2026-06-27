package com.fitnessgeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Android platform helpers — API 28 (Android 9) through API 35+ (Android 15/16).
 * Centralises version branching so call sites stay policy-correct on current and future OS releases.
 */
object PlatformCompat {

  private const val TAG = "PlatformCompat"

  /** Library floor: Android 9 / API 28 */
  const val MIN_SUPPORTED_SDK = Build.VERSION_CODES.P

  private val BOOT_ACTIONS = setOf(
    Intent.ACTION_BOOT_COMPLETED,
    "android.intent.action.QUICKBOOT_POWERON",
    "com.htc.intent.action.QUICKBOOT_POWERON",
  )

  fun isBootCompletedAction(action: String?): Boolean {
    return action != null && action in BOOT_ACTIONS
  }

  /**
   * Start the location foreground service with correct API branching and FGS policy handling.
   * Returns false when Android 12+ blocks background FGS starts (caller should defer or notify user).
   */
  fun startLocationForegroundService(context: Context, intent: Intent): Boolean {
    return try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        ContextCompat.startForegroundService(context, intent)
      } else {
        context.startService(intent)
      }
      true
    } catch (e: Exception) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
        e.javaClass.simpleName == "ForegroundServiceStartNotAllowedException"
      ) {
        Log.w(TAG, "FGS start blocked by system policy — defer until user opens app")
        false
      } else {
        Log.e(TAG, "FGS start failed", e)
        false
      }
    }
  }

  /** Register a dynamic receiver that must not be exported (API 33+ requirement). */
  fun registerNotExportedReceiver(
    context: Context,
    receiver: BroadcastReceiver,
    filter: IntentFilter,
  ) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      context.registerReceiver(receiver, filter)
    }
  }
}
