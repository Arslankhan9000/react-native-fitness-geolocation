package com.fitnessgeolocation

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class LocationDatabase(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, 2) {
  companion object {
    private const val DB_NAME = "fitness_geolocation.db"
  }

  override fun onCreate(db: SQLiteDatabase) {
    db.execSQL("""
      CREATE TABLE locations (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        heading REAL,
        altitude REAL,
        timestamp INTEGER NOT NULL,
        session_id TEXT,
        delivered_to_js INTEGER DEFAULT 0
      )
    """.trimIndent())
    db.execSQL("CREATE INDEX idx_pending ON locations(delivered_to_js)")
  }

  override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
    if (oldVersion < 2) {
      db.execSQL("ALTER TABLE locations ADD COLUMN delivered_to_js INTEGER DEFAULT 0")
    }
  }

  fun insert(location: StoredLocation): Boolean {
    return writableDatabase.insertWithOnConflict(
      "locations", null,
      android.content.ContentValues().apply {
        put("id", location.id)
        put("latitude", location.latitude)
        put("longitude", location.longitude)
        put("accuracy", location.accuracy)
        put("speed", location.speed)
        put("heading", location.heading)
        put("altitude", location.altitude)
        put("timestamp", location.timestamp)
        put("session_id", location.sessionId)
        put("delivered_to_js", if (location.deliveredToJs) 1 else 0)
      },
      SQLiteDatabase.CONFLICT_REPLACE,
    ) != -1L
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

  fun markDelivered(ids: List<String>): Int {
    if (ids.isEmpty()) return 0
    val cv = android.content.ContentValues().apply { put("delivered_to_js", 1) }
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
    val cursor = readableDatabase.rawQuery(
      "SELECT COUNT(*) FROM locations WHERE delivered_to_js = 0", null,
    )
    cursor.use { if (it.moveToFirst()) return it.getInt(0) }
    return 0
  }

  private fun rowToLocation(c: android.database.Cursor): StoredLocation {
    return StoredLocation(
      id = c.getString(c.getColumnIndexOrThrow("id")),
      latitude = c.getDouble(c.getColumnIndexOrThrow("latitude")),
      longitude = c.getDouble(c.getColumnIndexOrThrow("longitude")),
      accuracy = c.getFloat(c.getColumnIndexOrThrow("accuracy")),
      speed = c.getFloat(c.getColumnIndexOrThrow("speed")),
      heading = c.getFloat(c.getColumnIndexOrThrow("heading")),
      altitude = c.getDouble(c.getColumnIndexOrThrow("altitude")),
      timestamp = c.getLong(c.getColumnIndexOrThrow("timestamp")),
      sessionId = c.getString(c.getColumnIndexOrThrow("session_id")) ?: "default",
      deliveredToJs = c.getInt(c.getColumnIndexOrThrow("delivered_to_js")) == 1,
    )
  }
}
