package com.fitnessgeolocation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * After device reboot, hardware STEP_COUNTER baseline resets.
 * Flag session for reconcile when JS calls Pedometer.restore().
 */
class PedometerBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
      intent?.action != "android.intent.action.QUICKBOOT_POWERON" &&
      intent?.action != "com.htc.intent.action.QUICKBOOT_POWERON"
    ) {
      return
    }
    val prefs = context.getSharedPreferences("fitness_geo_pedometer", Context.MODE_PRIVATE)
    if (!prefs.getBoolean("session_v1_running", false)) return
    prefs.edit().putBoolean("session_v1_needs_reconcile", true).apply()
    Log.i("FitnessGeoPedometer", "boot: session flagged for reconcile")
    PedometerEngine.getInstance(context).markReconcileOnBoot()
  }
}
