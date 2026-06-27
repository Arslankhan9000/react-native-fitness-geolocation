package com.fitnessgeolocation

import android.os.Build

/**
 * Manufacturer-specific behavior for background sensors and battery policy.
 *
 * Chinese OEMs (MIUI, EMUI, ColorOS) aggressively kill background work beyond
 * standard Android Doze. Step counting uses hardware TYPE_STEP_COUNTER when
 * possible (no FGS), but OEM autostart / battery saver still blocks sensor
 * delivery until the user opens the app — we surface that in PedometerHealth.
 */
object OemProfiles {

  enum class RestrictionLevel { NONE, MODERATE, AGGRESSIVE }

  fun manufacturerKey(): String = Build.MANUFACTURER.lowercase()

  fun restrictionLevel(): RestrictionLevel {
    val m = manufacturerKey()
    return when {
      m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> RestrictionLevel.AGGRESSIVE
      m.contains("huawei") || m.contains("honor") -> RestrictionLevel.AGGRESSIVE
      m.contains("oppo") || m.contains("realme") || m.contains("vivo") ||
        m.contains("iqoo") || m.contains("oneplus") -> RestrictionLevel.AGGRESSIVE
      m.contains("samsung") -> RestrictionLevel.MODERATE
      m.contains("motorola") || m.contains("nokia") -> RestrictionLevel.MODERATE
      else -> RestrictionLevel.NONE
    }
  }

  fun hasAggressiveBackgroundKill(): Boolean =
    restrictionLevel() == RestrictionLevel.AGGRESSIVE

  fun oemSettingsLabel(): String? {
    val m = manufacturerKey()
    return when {
      m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> "MIUI Security Center"
      m.contains("huawei") || m.contains("honor") -> "Huawei System Manager"
      m.contains("oppo") -> "Oppo Battery Optimizer"
      m.contains("vivo") || m.contains("iqoo") -> "Vivo iQOO Security"
      m.contains("oneplus") -> "OnePlus Security"
      m.contains("samsung") -> "Samsung Device Care"
      m.contains("realme") -> "Realme Phone Manager"
      else -> null
    }
  }

  fun pedometerRationale(): String? {
    val m = manufacturerKey()
    return when {
      m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") ->
        "MIUI may pause step counting until you open the app. Enable Autostart and disable battery restrictions for reliable daily steps."
      m.contains("huawei") || m.contains("honor") ->
        "EMUI may stop step updates in the background. Add this app to Protected Apps in Phone Manager."
      m.contains("oppo") || m.contains("realme") ->
        "ColorOS may freeze background sensors. Allow Auto-Start and disable battery optimization."
      m.contains("vivo") || m.contains("iqoo") ->
        "OriginOS may limit background activity. Enable Autostart and set Background Activity to Always."
      m.contains("oneplus") ->
        "OxygenOS may restrict background sensors. Disable battery optimization and App Auto-Launch limits."
      m.contains("samsung") ->
        "Samsung may put unused apps to sleep. Set this app to Unrestricted under Battery in Device Care."
      else -> null
    }
  }

  /** Some OEMs batch-deliver STEP_COUNTER; faster sampling on foreground reconcile helps. */
  fun prefersFastSensorSampling(): Boolean = hasAggressiveBackgroundKill()
}
