package com.fitnessgeolocation

/** Persistent native log with verbosity + retention (Transistorsoft-style). */
class NativeLogger(private val database: LocationDatabase) {
  @Volatile private var minLevel = 0
  @Volatile private var maxDays = 3

  fun configure(logLevel: Int, logMaxDays: Int) {
    minLevel = logLevel.coerceIn(0, 5)
    maxDays = logMaxDays.coerceAtLeast(1)
    purgeOld()
  }

  fun log(level: String, message: String) {
    if (!shouldLog(level)) return
    database.logNative(level, message)
    purgeOld()
  }

  fun getLog(start: Long?, end: Long?, order: Int, limit: Int) =
    database.getNativeLog(start, end, order, limit)

  fun destroyLog() = database.destroyNativeLog()

  private fun shouldLog(level: String): Boolean {
    if (minLevel <= 0) return false
    return levelValue(level) <= minLevel
  }

  private fun levelValue(level: String): Int = when (level.uppercase()) {
    "ERROR" -> 1
    "WARN", "WARNING" -> 2
    "INFO" -> 3
    "DEBUG" -> 4
    "VERBOSE", "TRACE" -> 5
    else -> 3
  }

  private fun purgeOld() {
    val cutoff = System.currentTimeMillis() - maxDays.toLong() * 86_400_000L
    database.purgeNativeLogsBefore(cutoff)
  }
}
