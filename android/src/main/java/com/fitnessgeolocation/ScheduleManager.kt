package com.fitnessgeolocation

import java.util.Calendar

/** Cron-like schedule windows — Transistorsoft-compatible format. */
class ScheduleManager {
  enum class TrackingMode { location, geofence }

  data class Window(
    val days: Set<Int>,
    val onMinutes: Int,
    val offMinutes: Int,
    val mode: TrackingMode,
    var triggered: Boolean = false,
  )

  private val windows = mutableListOf<Window>()
  var isEnabled = false
    private set
  var onScheduleChange: ((Boolean, TrackingMode) -> Unit)? = null

  fun configure(records: List<String>) {
    windows.clear()
    records.forEach { parse(it)?.let { w -> windows.add(w) } }
  }

  fun start() {
    isEnabled = true
    evaluate()
  }

  fun stop() {
    isEnabled = false
    windows.forEach { it.triggered = false }
  }

  fun evaluate(now: Calendar = Calendar.getInstance()) {
    if (!isEnabled || windows.isEmpty()) return
    val weekday = now.get(Calendar.DAY_OF_WEEK) // 1=Sunday
    val minutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

    windows.forEachIndexed { i, w ->
      if (!w.days.contains(weekday)) return@forEachIndexed
      val inWindow = if (w.onMinutes <= w.offMinutes) {
        minutes in w.onMinutes until w.offMinutes
      } else {
        minutes >= w.onMinutes || minutes < w.offMinutes
      }
      if (inWindow && !w.triggered) {
        windows[i] = w.copy(triggered = true)
        onScheduleChange?.invoke(true, w.mode)
      } else if (!inWindow && w.triggered) {
        windows[i] = w.copy(triggered = false)
        onScheduleChange?.invoke(false, w.mode)
      }
    }
  }

  fun stateMap(): Map<String, Any> = mapOf(
    "schedulerEnabled" to isEnabled,
    "scheduleCount" to windows.size,
  )

  private fun parse(record: String): Window? {
    val parts = record.trim().split(" ").filter { it.isNotEmpty() }
    if (parts.size < 2) return null
    val days = parseDays(parts[0]) ?: return null
    val (on, off) = parseTimeRange(parts[1]) ?: return null
    val mode = if (parts.size >= 3 && parts[2].equals("geofence", true)) TrackingMode.geofence else TrackingMode.location
    return Window(days, on, off, mode)
  }

  private fun parseDays(s: String): Set<Int>? {
    if ("-" in s) {
      val b = s.split("-")
      if (b.size != 2) return null
      val lo = b[0].toIntOrNull() ?: return null
      val hi = b[1].toIntOrNull() ?: return null
      return (lo..hi).toSet()
    }
    return s.toIntOrNull()?.let { setOf(it) }
  }

  private fun parseTimeRange(s: String): Pair<Int, Int>? {
    val b = s.split("-")
    if (b.size != 2) return null
    val on = parseTime(b[0]) ?: return null
    val off = parseTime(b[1]) ?: return null
    return on to off
  }

  private fun parseTime(s: String): Int? {
    val p = s.split(":")
    if (p.size != 2) return null
    val h = p[0].toIntOrNull() ?: return null
    val m = p[1].toIntOrNull() ?: return null
    return h * 60 + m
  }
}
