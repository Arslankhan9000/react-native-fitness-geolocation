package com.fitnessgeolocation

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log

class LocationDatabase(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, 6) {
  companion object {
    private const val DB_NAME = "fitness_geolocation.db"
    private const val TAG = "FitnessGeoDB"
  }

  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL("""
      CREATE TABLE IF NOT EXISTS locations (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        heading REAL,
        altitude REAL,
        timestamp INTEGER NOT NULL,
        battery_level REAL DEFAULT -1,
        motion_state TEXT DEFAULT 'unknown',
        signal_strength TEXT DEFAULT 'medium',
        session_id TEXT,
        delivered_to_js INTEGER DEFAULT 0,
        distance_from_prev REAL DEFAULT 0,
        cumulative_distance REAL DEFAULT 0,
        quality_json TEXT
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_locations_pending ON locations(delivered_to_js)")
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_locations_session ON locations(session_id)")
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp)")

    db.execSQL("""
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        name TEXT,
        activity_type TEXT DEFAULT 'running',
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        total_distance REAL DEFAULT 0,
        total_duration INTEGER DEFAULT 0,
        total_active_duration INTEGER DEFAULT 0,
        max_speed REAL DEFAULT 0,
        elevation_gain REAL DEFAULT 0,
        average_accuracy REAL DEFAULT 0,
        point_count INTEGER DEFAULT 0,
        pause_count INTEGER DEFAULT 0,
        uploaded INTEGER DEFAULT 0,
        extras TEXT
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_sessions_uploaded ON sessions(uploaded)")

    // ─── v5: Engine event stores (offline-first) ─────────────────────────────
    db.execSQL("""
      CREATE TABLE IF NOT EXISTS diagnostics_timeline (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        level TEXT NOT NULL,
        event TEXT NOT NULL,
        data_json TEXT,
        timestamp INTEGER NOT NULL
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_diag_session_ts ON diagnostics_timeline(session_id, timestamp)")

    db.execSQL("""
      CREATE TABLE IF NOT EXISTS motion_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        activity TEXT NOT NULL,
        confidence REAL DEFAULT 0,
        data_json TEXT,
        timestamp INTEGER NOT NULL
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_motion_session_ts ON motion_events(session_id, timestamp)")

    db.execSQL("""
      CREATE TABLE IF NOT EXISTS geofence_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        identifier TEXT NOT NULL,
        action TEXT NOT NULL,
        data_json TEXT,
        timestamp INTEGER NOT NULL
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_geofence_session_ts ON geofence_events(session_id, timestamp)")

    db.execSQL("""
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        attempts INTEGER DEFAULT 0,
        last_error TEXT,
        next_retry_ts INTEGER DEFAULT 0,
        created_ts INTEGER NOT NULL
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON sync_queue(next_retry_ts)")
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    if (oldVersion < 2) {
      db.execSQL("ALTER TABLE locations ADD COLUMN delivered_to_js INTEGER DEFAULT 0")
    }
    if (oldVersion < 3) {
      try { db.execSQL("ALTER TABLE locations ADD COLUMN distance_from_prev REAL DEFAULT 0") } catch (_: Exception) {}
      try { db.execSQL("ALTER TABLE locations ADD COLUMN cumulative_distance REAL DEFAULT 0") } catch (_: Exception) {}
      try { db.execSQL("ALTER TABLE locations ADD COLUMN battery_level REAL DEFAULT -1") } catch (_: Exception) {}
      try { db.execSQL("ALTER TABLE locations ADD COLUMN motion_state TEXT DEFAULT 'unknown'") } catch (_: Exception) {}
      try { db.execSQL("ALTER TABLE locations ADD COLUMN signal_strength TEXT DEFAULT 'medium'") } catch (_: Exception) {}
    }
    if (oldVersion < 4) {
      db.execSQL("""
        CREATE TABLE IF NOT EXISTS native_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          level TEXT NOT NULL,
          message TEXT NOT NULL,
          timestamp INTEGER NOT NULL
        )
      """.trimIndent())
      db.execSQL("CREATE INDEX IF NOT EXISTS idx_native_logs_ts ON native_logs(timestamp)")
    }
    if (oldVersion < 5) {
      db.execSQL("""
        CREATE TABLE IF NOT EXISTS diagnostics_timeline (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT,
          level TEXT NOT NULL,
          event TEXT NOT NULL,
          data_json TEXT,
          timestamp INTEGER NOT NULL
        )
      """.trimIndent())
      db.execSQL("CREATE INDEX IF NOT EXISTS idx_diag_session_ts ON diagnostics_timeline(session_id, timestamp)")

      db.execSQL("""
        CREATE TABLE IF NOT EXISTS motion_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT,
          activity TEXT NOT NULL,
          confidence REAL DEFAULT 0,
          data_json TEXT,
          timestamp INTEGER NOT NULL
        )
      """.trimIndent())
      db.execSQL("CREATE INDEX IF NOT EXISTS idx_motion_session_ts ON motion_events(session_id, timestamp)")

      db.execSQL("""
        CREATE TABLE IF NOT EXISTS geofence_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT,
          identifier TEXT NOT NULL,
          action TEXT NOT NULL,
          data_json TEXT,
          timestamp INTEGER NOT NULL
        )
      """.trimIndent())
      db.execSQL("CREATE INDEX IF NOT EXISTS idx_geofence_session_ts ON geofence_events(session_id, timestamp)")

      db.execSQL("""
        CREATE TABLE IF NOT EXISTS sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          attempts INTEGER DEFAULT 0,
          last_error TEXT,
          next_retry_ts INTEGER DEFAULT 0,
          created_ts INTEGER NOT NULL
        )
      """.trimIndent())
      db.execSQL("CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON sync_queue(next_retry_ts)")
    }
    if (oldVersion < 6) {
      try { db.execSQL("ALTER TABLE locations ADD COLUMN quality_json TEXT") } catch (_: Exception) {}
    }
  }

  // ─── Locations ─────────────────────────────────────────────────────────────

  fun insert(location: StoredLocation): Boolean {
    val cv = ContentValues().apply {
      put("id", location.id)
      put("latitude", location.latitude)
      put("longitude", location.longitude)
      put("accuracy", location.accuracy)
      put("speed", location.speed)
      put("heading", location.heading)
      put("altitude", location.altitude)
      put("timestamp", location.timestamp)
      put("battery_level", location.batteryLevel)
      put("motion_state", location.motionState)
      put("signal_strength", location.signalStrength)
      put("session_id", location.sessionId)
      put("delivered_to_js", if (location.deliveredToJs) 1 else 0)
      put("distance_from_prev", location.distanceFromPrev)
      put("cumulative_distance", location.cumulativeDistance)
      put("quality_json", location.qualityJson)
    }
    return writableDatabase.insertWithOnConflict("locations", null, cv, SQLiteDatabase.CONFLICT_REPLACE) != -1L
  }

  fun getPendingForJs(limit: Int): List<StoredLocation> {
    val results = mutableListOf<StoredLocation>()
    val cursor = readableDatabase.query(
      "locations", null, "delivered_to_js = 0", null, null, null,
      "timestamp ASC", limit.toString(),
    )
    cursor.use {
      while (it.moveToNext()) {
        results.add(rowToLocation(it))
      }
    }
    return results
  }

  fun getPendingForSession(sessionId: String, limit: Int = 5000): List<StoredLocation> {
    val results = mutableListOf<StoredLocation>()
    val cursor = readableDatabase.query(
      "locations", null, "session_id = ? AND delivered_to_js = 0",
      arrayOf(sessionId), null, null, "timestamp ASC", limit.toString(),
    )
    cursor.use {
      while (it.moveToNext()) {
        results.add(rowToLocation(it))
      }
    }
    return results
  }

  fun markDelivered(ids: List<String>): Int {
    if (ids.isEmpty()) return 0
    val cv = ContentValues().apply { put("delivered_to_js", 1) }
    return ids.sumOf { id ->
      writableDatabase.update("locations", cv, "id = ?", arrayOf(id))
    }
  }

  fun acknowledge(ids: List<String>): Int {
    if (ids.isEmpty()) return 0
    val placeholders = ids.joinToString(",") { "?" }
    return writableDatabase.delete("locations", "id IN ($placeholders)", ids.toTypedArray())
  }

  fun purgeDelivered(): Int {
    return writableDatabase.delete("locations", "delivered_to_js = 1", null)
  }

  fun pendingCount(): Int {
    val cursor = readableDatabase.rawQuery("SELECT COUNT(*) FROM locations WHERE delivered_to_js = 0", null)
    cursor.use { if (it.moveToFirst()) return it.getInt(0) }
    return 0
  }

  fun clearAll() {
    writableDatabase.delete("locations", null, null)
    writableDatabase.delete("sessions", null, null)
  }

  fun getAllLocations(limit: Int = 1000): List<StoredLocation> {
    val results = mutableListOf<StoredLocation>()
    val cursor = readableDatabase.query(
      "locations", null, null, null, null, null,
      "timestamp DESC", limit.toString(),
    )
    cursor.use { while (it.moveToNext()) results.add(rowToLocation(it)) }
    return results
  }

  fun destroyLocation(id: String): Boolean {
    return writableDatabase.delete("locations", "id = ?", arrayOf(id)) > 0
  }

  fun logNative(level: String, message: String) {
    val cv = ContentValues().apply {
      put("level", level)
      put("message", message)
      put("timestamp", System.currentTimeMillis())
    }
    writableDatabase.insert("native_logs", null, cv)
  }

  fun getNativeLog(start: Long?, end: Long?, order: Int, limit: Int): String {
    val clauses = mutableListOf<String>()
    val args = mutableListOf<String>()
    start?.let { clauses.add("timestamp >= ?"); args.add(it.toString()) }
    end?.let { clauses.add("timestamp <= ?"); args.add(it.toString()) }
    val where = if (clauses.isEmpty()) "" else "WHERE ${clauses.joinToString(" AND ")}"
    val orderDir = if (order >= 0) "ASC" else "DESC"
    val cursor = readableDatabase.rawQuery(
      "SELECT level, message, timestamp FROM native_logs $where ORDER BY timestamp $orderDir LIMIT $limit",
      args.toTypedArray(),
    )
    val lines = mutableListOf<String>()
    cursor.use {
      while (it.moveToNext()) {
        lines.add("[${it.getLong(2)}] [${it.getString(0)}] ${it.getString(1)}")
      }
    }
    return lines.joinToString("\n")
  }

  fun destroyNativeLog() {
    writableDatabase.delete("native_logs", null, null)
  }

  fun purgeNativeLogsBefore(cutoffMs: Long) {
    writableDatabase.delete("native_logs", "timestamp < ?", arrayOf(cutoffMs.toString()))
  }

  fun deleteLocationsForSession(sessionId: String) {
    writableDatabase.delete("locations", "session_id = ?", arrayOf(sessionId))
  }

  // ─── Sessions ──────────────────────────────────────────────────────────────

  fun createSession(name: String, activityType: String, extras: String?): String {
    val id = java.util.UUID.randomUUID().toString()
    val cv = ContentValues().apply {
      put("id", id)
      put("name", name)
      put("activity_type", activityType)
      put("start_time", System.currentTimeMillis())
      extras?.let { put("extras", it) }
    }
    writableDatabase.insertWithOnConflict("sessions", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    return id
  }

  fun endSession(sessionId: String, data: Map<String, Any?>) {
    val cv = ContentValues().apply {
      put("end_time", System.currentTimeMillis())
      put("total_distance", (data["totalDistance"] as? Double) ?: 0.0)
      put("total_duration", (data["totalDuration"] as? Long) ?: 0L)
      put("total_active_duration", (data["totalActiveDuration"] as? Long) ?: 0L)
      put("max_speed", (data["maxSpeed"] as? Double) ?: 0.0)
      put("elevation_gain", (data["elevationGain"] as? Double) ?: 0.0)
      put("average_accuracy", (data["averageAccuracy"] as? Double) ?: 0.0)
      put("point_count", (data["pointCount"] as? Int) ?: 0)
    }
    writableDatabase.update("sessions", cv, "id = ?", arrayOf(sessionId))
  }

  fun discardSession(sessionId: String) {
    deleteLocationsForSession(sessionId)
    writableDatabase.delete("sessions", "id = ?", arrayOf(sessionId))
  }

  fun getUnuploadedSessions(): List<Map<String, Any?>> {
    val results = mutableListOf<Map<String, Any?>>()
    val cursor = readableDatabase.rawQuery(
      "SELECT * FROM sessions WHERE uploaded = 0 ORDER BY start_time ASC", null
    )
    cursor.use {
      while (it.moveToNext()) {
        results.add(sessionRowToMap(it))
      }
    }
    return results
  }

  fun getSessionForUpload(sessionId: String): Map<String, Any?>? {
    val cursor = readableDatabase.rawQuery(
      "SELECT * FROM sessions WHERE id = ?", arrayOf(sessionId)
    )
    cursor.use {
      if (it.moveToFirst()) {
        val sessionData = sessionRowToMap(it).toMutableMap()
        val points = getPendingForSession(sessionId).map { loc ->
          mapOf(
            "id" to loc.id,
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "timestamp" to loc.timestamp,
            "accuracy" to loc.accuracy,
            "speed" to loc.speed,
            "altitude" to loc.altitude,
            "distanceFromPrev" to loc.distanceFromPrev,
            "cumulativeDistance" to loc.cumulativeDistance,
          )
        }
        sessionData["points"] = points
        return sessionData
      }
    }
    return null
  }

  fun markSessionUploaded(sessionId: String) {
    val cv = ContentValues().apply { put("uploaded", 1) }
    writableDatabase.update("sessions", cv, "id = ?", arrayOf(sessionId))
    deleteLocationsForSession(sessionId)
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  private fun rowToLocation(c: Cursor): StoredLocation {
    return StoredLocation(
      id = c.getString(c.getColumnIndexOrThrow("id")),
      latitude = c.getDouble(c.getColumnIndexOrThrow("latitude")),
      longitude = c.getDouble(c.getColumnIndexOrThrow("longitude")),
      accuracy = c.getFloat(c.getColumnIndexOrThrow("accuracy")),
      speed = c.getFloat(c.getColumnIndexOrThrow("speed")),
      heading = c.getFloat(c.getColumnIndexOrThrow("heading")),
      altitude = c.getDouble(c.getColumnIndexOrThrow("altitude")),
      timestamp = c.getLong(c.getColumnIndexOrThrow("timestamp")),
      batteryLevel = tryOrNull { c.getDouble(c.getColumnIndexOrThrow("battery_level")) } ?: -1.0,
      motionState = tryOrNull { c.getString(c.getColumnIndexOrThrow("motion_state")) } ?: "unknown",
      signalStrength = tryOrNull { c.getString(c.getColumnIndexOrThrow("signal_strength")) } ?: "medium",
      sessionId = tryOrNull { c.getString(c.getColumnIndexOrThrow("session_id")) } ?: "default",
      deliveredToJs = c.getInt(c.getColumnIndexOrThrow("delivered_to_js")) == 1,
      distanceFromPrev = tryOrNull { c.getDouble(c.getColumnIndexOrThrow("distance_from_prev")) } ?: 0.0,
      cumulativeDistance = tryOrNull { c.getDouble(c.getColumnIndexOrThrow("cumulative_distance")) } ?: 0.0,
      qualityJson = tryOrNull { c.getString(c.getColumnIndexOrThrow("quality_json")) },
    )
  }

  private fun sessionRowToMap(c: Cursor): Map<String, Any?> {
    return mapOf(
      "sessionId" to c.getString(c.getColumnIndexOrThrow("id")),
      "name" to c.getString(c.getColumnIndexOrThrow("name")),
      "activityType" to c.getString(c.getColumnIndexOrThrow("activity_type")),
      "startTime" to c.getLong(c.getColumnIndexOrThrow("start_time")),
      "endTime" to c.getLong(c.getColumnIndexOrThrow("end_time")),
      "totalDistance" to c.getDouble(c.getColumnIndexOrThrow("total_distance")),
      "totalDuration" to c.getLong(c.getColumnIndexOrThrow("total_duration")),
      "totalActiveDuration" to c.getLong(c.getColumnIndexOrThrow("total_active_duration")),
      "maxSpeed" to c.getDouble(c.getColumnIndexOrThrow("max_speed")),
      "elevationGain" to c.getDouble(c.getColumnIndexOrThrow("elevation_gain")),
      "pointCount" to c.getInt(c.getColumnIndexOrThrow("point_count")),
      "pauseCount" to c.getInt(c.getColumnIndexOrThrow("pause_count")),
      "uploaded" to (c.getInt(c.getColumnIndexOrThrow("uploaded")) == 1),
    )
  }

  private fun <T> tryOrNull(block: () -> T): T? = try { block() } catch (_: Exception) { null }
}
