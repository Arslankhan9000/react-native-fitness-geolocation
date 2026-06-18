package com.fitnessgeolocation

import kotlin.math.abs

/**
 * Lightweight GPS noise filter — mirrors iOS LocationFilter heuristics.
 */
class LocationFilter {
  private var warmupCount = 0
  private val warmupRequired = 3
  private var lastAccepted: android.location.Location? = null

  fun reset() {
    warmupCount = 0
    lastAccepted = null
  }

  sealed class Result {
    data class Accept(val location: android.location.Location) : Result()
    object Reject : Result()
  }

  fun process(raw: android.location.Location): Result {
    if (raw.latitude == 0.0 && raw.longitude == 0.0) return Result.Reject

    val accuracy = if (raw.hasAccuracy()) raw.accuracy else 999f
    if (accuracy > 50f) return Result.Reject

    if (raw.hasSpeed() && raw.speed > 150f) return Result.Reject

    lastAccepted?.let { prev ->
      val dt = (raw.time - prev.time) / 1000.0
      if (dt in 0.1..30.0) {
        val dist = prev.distanceTo(raw).toDouble()
        if (dist < 2.0 && accuracy > 15f) return Result.Reject
      }
    }

    if (warmupCount < warmupRequired) {
      warmupCount++
      if (accuracy > 25f) return Result.Reject
    }

    lastAccepted = raw
    return Result.Accept(raw)
  }
}
