import Foundation
import SQLite3
import os.log

// MARK: - Models

struct StoredLocation {
  let id: String
  let latitude: Double
  let longitude: Double
  let accuracy: Double
  let speed: Double
  let heading: Double
  let altitude: Double
  let timestamp: Int64
  let batteryLevel: Double
  let signalStrength: String
  let provider: String
  let motionState: String
  let confidence: Double
  let sessionId: String
  let deliveredToJs: Bool
  let distanceFromPrev: Double
  let cumulativeDistance: Double
}

struct ActivitySession {
  let id: String
  let name: String
  let activityType: String
  let startTime: Int64
  let endTime: Int64?
  let totalDistance: Double
  let totalDuration: Int64
  let totalActiveDuration: Int64
  let maxSpeed: Double
  let elevationGain: Double
  let averageAccuracy: Double
  let pointCount: Int
  let pauseCount: Int
  let uploaded: Bool
  let extras: String?
}

// MARK: - Database

final class LocationDatabase {
  static let shared = LocationDatabase()

  private var db: OpaquePointer?
  private let queue = DispatchQueue(label: "com.fitnessgeolocation.database", qos: .userInitiated)
  private let log = OSLog(subsystem: "com.fitnessgeolocation", category: "database")

  /// Shared prepared statements cache — avoids recompiling SQL
  private var insertStmt: OpaquePointer?
  private var pendingCountStmt: OpaquePointer?
  private var pendingForJsStmt: OpaquePointer?
  private var pendingForSessionStmt: OpaquePointer?
  private var endSessionStmt: OpaquePointer?

  private init() {
    openDatabase()
    pragmaOptimize()
    createTables()
    migrateIfNeeded()
    prepareStatements()
  }

  deinit {
    sqlite3_finalize(insertStmt)
    sqlite3_finalize(pendingCountStmt)
    sqlite3_finalize(pendingForJsStmt)
    sqlite3_finalize(pendingForSessionStmt)
    sqlite3_finalize(endSessionStmt)
    if db != nil { sqlite3_close(db) }
  }

  /// Use modern FileManager API instead of deprecated NSSearchPathForDirectoriesInDomains
  private var dbPath: String {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return dir.appendingPathComponent("fitness_geolocation.db").path
  }

  private func openDatabase() {
    if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
      os_log(.error, log: log, "Failed to open database")
    }
  }

  /// WAL mode for concurrent reads + writes without locks
  /// Performance: ~2-3x faster reads, no reader-writer lock contention
  private func pragmaOptimize() {
    sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA cache_size=-8000", nil, nil, nil) // 8MB cache
    sqlite3_exec(db, "PRAGMA temp_store=MEMORY", nil, nil, nil)
    sqlite3_exec(db, "PRAGMA mmap_size=268435456", nil, nil, nil) // 256MB mmap
    sqlite3_exec(db, "PRAGMA busy_timeout=5000", nil, nil, nil) // 5s busy timeout
  }

  /// Pre-compile statements that are used repeatedly (hot path optimization)
  private func prepareStatements() {
    let insertSQL = """
    INSERT OR REPLACE INTO locations
    (id, latitude, longitude, accuracy, speed, heading, altitude, timestamp,
     battery_level, signal_strength, provider, motion_state, confidence,
     session_id, delivered_to_js, distance_from_prev, cumulative_distance)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil)

    sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM locations WHERE delivered_to_js = 0", -1, &pendingCountStmt, nil)

    sqlite3_prepare_v2(db, "SELECT * FROM locations WHERE delivered_to_js = 0 ORDER BY timestamp ASC LIMIT ?", -1, &pendingForJsStmt, nil)

    sqlite3_prepare_v2(db, "SELECT * FROM locations WHERE session_id = ? AND delivered_to_js = 0 ORDER BY timestamp ASC LIMIT ?", -1, &pendingForSessionStmt, nil)
  }

  // MARK: - Schema

  private func createTables() {
    let sql = """
    CREATE TABLE IF NOT EXISTS locations (
      id TEXT PRIMARY KEY,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      accuracy REAL,
      speed REAL,
      heading REAL,
      altitude REAL,
      timestamp INTEGER NOT NULL,
      battery_level REAL,
      signal_strength TEXT,
      provider TEXT,
      motion_state TEXT,
      confidence REAL,
      session_id TEXT,
      delivered_to_js INTEGER DEFAULT 0,
      distance_from_prev REAL DEFAULT 0,
      cumulative_distance REAL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_locations_pending ON locations(delivered_to_js);
    CREATE INDEX IF NOT EXISTS idx_locations_session ON locations(session_id);
    CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp);
    """
    queue.sync { sqlite3_exec(db, sql, nil, nil, nil) }

    let sessionsSQL = """
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
    );
    CREATE INDEX IF NOT EXISTS idx_sessions_uploaded ON sessions(uploaded);
    """
    queue.sync { sqlite3_exec(db, sessionsSQL, nil, nil, nil) }
  }

  private func migrateIfNeeded() {
    queue.sync {
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, "PRAGMA table_info(locations)", -1, &stmt, nil) == SQLITE_OK else { return }
      defer { sqlite3_finalize(stmt) }
      var columns = Set<String>()
      while sqlite3_step(stmt) == SQLITE_ROW {
        if let name = sqlite3_column_text(stmt, 1) {
          columns.insert(String(cString: name))
        }
      }
      if !columns.contains("delivered_to_js") {
        sqlite3_exec(db, "ALTER TABLE locations ADD COLUMN delivered_to_js INTEGER DEFAULT 0", nil, nil, nil)
      }
      if !columns.contains("distance_from_prev") {
        sqlite3_exec(db, "ALTER TABLE locations ADD COLUMN distance_from_prev REAL DEFAULT 0", nil, nil, nil)
      }
      if !columns.contains("cumulative_distance") {
        sqlite3_exec(db, "ALTER TABLE locations ADD COLUMN cumulative_distance REAL DEFAULT 0", nil, nil, nil)
      }
    }
  }

  // MARK: - Location CRUD

  func insert(_ location: StoredLocation) -> Bool {
    queue.sync {
      // Use prepared statement for hot path (avoids recompiling SQL on every insert)
      guard let stmt = insertStmt else { return false }
      sqlite3_reset(stmt)
      sqlite3_clear_bindings(stmt)

      sqlite3_bind_text(stmt, 1, (location.id as NSString).utf8String, -1, nil)
      sqlite3_bind_double(stmt, 2, location.latitude)
      sqlite3_bind_double(stmt, 3, location.longitude)
      sqlite3_bind_double(stmt, 4, location.accuracy)
      sqlite3_bind_double(stmt, 5, location.speed)
      sqlite3_bind_double(stmt, 6, location.heading)
      sqlite3_bind_double(stmt, 7, location.altitude)
      sqlite3_bind_int64(stmt, 8, location.timestamp)
      sqlite3_bind_double(stmt, 9, location.batteryLevel)
      sqlite3_bind_text(stmt, 10, (location.signalStrength as NSString).utf8String, -1, nil)
      sqlite3_bind_text(stmt, 11, (location.provider as NSString).utf8String, -1, nil)
      sqlite3_bind_text(stmt, 12, (location.motionState as NSString).utf8String, -1, nil)
      sqlite3_bind_double(stmt, 13, location.confidence)
      sqlite3_bind_text(stmt, 14, (location.sessionId as NSString).utf8String, -1, nil)
      sqlite3_bind_int32(stmt, 15, location.deliveredToJs ? 1 : 0)
      sqlite3_bind_double(stmt, 16, location.distanceFromPrev)
      sqlite3_bind_double(stmt, 17, location.cumulativeDistance)

      return sqlite3_step(stmt) == SQLITE_DONE
    }
  }

  func getPendingForJs(limit: Int32 = 200) -> [StoredLocation] {
    queue.sync {
      guard let stmt = pendingForJsStmt else { return [] }
      sqlite3_reset(stmt)
      sqlite3_clear_bindings(stmt)
      sqlite3_bind_int32(stmt, 1, limit)

      var results: [StoredLocation] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        if let loc = rowToLocation(stmt) { results.append(loc) }
      }
      return results
    }
  }

  func getPendingForSession(sessionId: String, limit: Int32 = 5000) -> [StoredLocation] {
    queue.sync {
      guard let stmt = pendingForSessionStmt else { return [] }
      sqlite3_reset(stmt)
      sqlite3_clear_bindings(stmt)
      sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
      sqlite3_bind_int32(stmt, 2, limit)

      var results: [StoredLocation] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        if let loc = rowToLocation(stmt) { results.append(loc) }
      }
      return results
    }
  }

  func markDelivered(ids: [String]) -> Int {
    guard !ids.isEmpty else { return 0 }
    return queue.sync {
      let ph = ids.map { _ in "?" }.joined(separator: ",")
      let sql = "UPDATE locations SET delivered_to_js = 1 WHERE id IN (\(ph))"
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
      defer { sqlite3_finalize(stmt) }
      for (i, id) in ids.enumerated() {
        sqlite3_bind_text(stmt, Int32(i + 1), (id as NSString).utf8String, -1, nil)
      }
      guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
      return Int(sqlite3_changes(db)) // Returns Int32 directly
    }
  }

  func acknowledge(ids: [String]) -> Int {
    guard !ids.isEmpty else { return 0 }
    return queue.sync {
      let ph = ids.map { _ in "?" }.joined(separator: ",")
      let sql = "DELETE FROM locations WHERE id IN (\(ph))"
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
      defer { sqlite3_finalize(stmt) }
      for (i, id) in ids.enumerated() {
        sqlite3_bind_text(stmt, Int32(i + 1), (id as NSString).utf8String, -1, nil)
      }
      guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
      return Int(sqlite3_changes(db))
    }
  }

  func pendingCount() -> Int {
    queue.sync {
      guard let stmt = pendingCountStmt else { return 0 }
      sqlite3_reset(stmt)
      if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_int(stmt, 0) }
      return 0
    }
  }

  func clearAll() {
    queue.sync {
      sqlite3_exec(db, "DELETE FROM locations", nil, nil, nil)
      sqlite3_exec(db, "DELETE FROM sessions", nil, nil, nil)
    }
  }

  func purgeDelivered() -> Int32 {
    queue.sync {
      sqlite3_exec(db, "DELETE FROM locations WHERE delivered_to_js = 1", nil, nil, nil)
      return sqlite3_changes(db)
    }
  }

  // MARK: - Session CRUD

  func createSession(name: String, activityType: String, extras: String?) -> String {
    let id = UUID().uuidString
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    queue.sync {
      var stmt: OpaquePointer?
      let sql = "INSERT INTO sessions (id, name, activity_type, start_time, extras) VALUES (?, ?, ?, ?, ?)"
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
      sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)
      sqlite3_bind_text(stmt, 3, (activityType as NSString).utf8String, -1, nil)
      sqlite3_bind_int64(stmt, 4, now)
      if let e = extras {
        sqlite3_bind_text(stmt, 5, (e as NSString).utf8String, -1, nil)
      } else {
        sqlite3_bind_null(stmt, 5)
      }
      sqlite3_step(stmt)
    }
    return id
  }

  func endSession(_ sessionId: String, data: [String: Any]) {
    queue.sync {
      var stmt: OpaquePointer?
      let sql = """
      UPDATE sessions SET
        end_time = ?, total_distance = ?, total_duration = ?,
        total_active_duration = ?, max_speed = ?, elevation_gain = ?,
        average_accuracy = ?, point_count = ?
      WHERE id = ?
      """
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970 * 1000))
      sqlite3_bind_double(stmt, 2, (data["totalDistance"] as? Double) ?? 0)
      sqlite3_bind_int64(stmt, 3, (data["totalDuration"] as? Int64) ?? 0)
      sqlite3_bind_int64(stmt, 4, (data["totalActiveDuration"] as? Int64) ?? 0)
      sqlite3_bind_double(stmt, 5, (data["maxSpeed"] as? Double) ?? 0)
      sqlite3_bind_double(stmt, 6, (data["elevationGain"] as? Double) ?? 0)
      sqlite3_bind_double(stmt, 7, (data["averageAccuracy"] as? Double) ?? 0)
      sqlite3_bind_int32(stmt, 8, Int32((data["pointCount"] as? Int) ?? 0))
      sqlite3_bind_text(stmt, 9, (sessionId as NSString).utf8String, -1, nil)
      sqlite3_step(stmt)
    }
  }

  func discardSession(_ sessionId: String) {
    queue.sync {
      var stmt1: OpaquePointer?
      var stmt2: OpaquePointer?
      // Use parameterized queries — NEVER string interpolation with SQL
      if sqlite3_prepare_v2(db, "DELETE FROM locations WHERE session_id = ?", -1, &stmt1, nil) == SQLITE_OK {
        sqlite3_bind_text(stmt1, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt1)
        sqlite3_finalize(stmt1)
      }
      if sqlite3_prepare_v2(db, "DELETE FROM sessions WHERE id = ?", -1, &stmt2, nil) == SQLITE_OK {
        sqlite3_bind_text(stmt2, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt2)
        sqlite3_finalize(stmt2)
      }
    }
  }

  func getUnuploadedSessions() -> [[String: Any]] {
    queue.sync {
      var results: [[String: Any]] = []
      let sql = "SELECT * FROM sessions WHERE uploaded = 0 ORDER BY start_time ASC"
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
      defer { sqlite3_finalize(stmt) }
      while sqlite3_step(stmt) == SQLITE_ROW {
        results.append(sessionFrom(stmt: stmt))
      }
      return results
    }
  }

  func getSessionForUpload(_ sessionId: String) -> [String: Any]? {
    // Fetch session and points OUTSIDE the queue lock to avoid deadlock
    // (getPendingForSession needs its own queue lock)
    var result: [String: Any]?
    queue.sync {
      var stmt: OpaquePointer?
      let sql = "SELECT * FROM sessions WHERE id = ?"
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
      guard sqlite3_step(stmt) == SQLITE_ROW else { return }

      var dict = sessionFrom(stmt: stmt)
      dict["points"] = getPendingForSession(sessionId: sessionId).map { $0.toDictionary() }
      result = dict
    }
    return result
  }

  func markSessionUploaded(_ sessionId: String) {
    queue.sync {
      var stmt: OpaquePointer?
      // Parameterized query — no string interpolation
      if sqlite3_prepare_v2(db, "UPDATE sessions SET uploaded = 1 WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
      }
      // Clean up points
      if sqlite3_prepare_v2(db, "DELETE FROM locations WHERE session_id = ?", -1, &stmt, nil) == SQLITE_OK {
        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
      }
    }
  }

  // MARK: - Helpers

  /// Build session dictionary from a prepared statement at the current row
  private func sessionFrom(stmt: OpaquePointer) -> [String: Any] {
    var dict: [String: Any] = [
      "sessionId": String(cString: sqlite3_column_text(stmt, 0)),
      "name": String(cString: sqlite3_column_text(stmt, 1)),
      "activityType": String(cString: sqlite3_column_text(stmt, 2)),
      "startTime": sqlite3_column_int64(stmt, 3),
      "endTime": sqlite3_column_int64(stmt, 4),
      "totalDistance": sqlite3_column_double(stmt, 5),
      "totalDuration": sqlite3_column_int64(stmt, 6),
      "totalActiveDuration": sqlite3_column_int64(stmt, 7),
      "maxSpeed": sqlite3_column_double(stmt, 8),
      "elevationGain": sqlite3_column_double(stmt, 9),
      "averageAccuracy": sqlite3_column_double(stmt, 10),
      "pointCount": Int(sqlite3_column_int(stmt, 11)),
      "pauseCount": Int(sqlite3_column_int(stmt, 12)),
      "uploaded": sqlite3_column_int(stmt, 13) != 0,
    ]
    if let extras = sqlite3_column_text(stmt, 14) {
      dict["extras"] = String(cString: extras)
    }
    return dict
  }

  private func rowToLocation(_ stmt: OpaquePointer?) -> StoredLocation? {
    guard let stmt = stmt else { return nil }
    return StoredLocation(
      id: String(cString: sqlite3_column_text(stmt, 0)),
      latitude: sqlite3_column_double(stmt, 1),
      longitude: sqlite3_column_double(stmt, 2),
      accuracy: sqlite3_column_double(stmt, 3),
      speed: sqlite3_column_double(stmt, 4),
      heading: sqlite3_column_double(stmt, 5),
      altitude: sqlite3_column_double(stmt, 6),
      timestamp: sqlite3_column_int64(stmt, 7),
      batteryLevel: sqlite3_column_double(stmt, 8),
      signalStrength: String(cString: sqlite3_column_text(stmt, 9)),
      provider: String(cString: sqlite3_column_text(stmt, 10)),
      motionState: String(cString: sqlite3_column_text(stmt, 11)),
      confidence: sqlite3_column_double(stmt, 12),
      sessionId: String(cString: sqlite3_column_text(stmt, 13)),
      deliveredToJs: sqlite3_column_int(stmt, 14) != 0,
      distanceFromPrev: sqlite3_column_double(stmt, 15),
      cumulativeDistance: sqlite3_column_double(stmt, 16)
    )
  }
}

// MARK: - Extensions

extension StoredLocation {
  func toDictionary() -> [String: Any] {
    [
      "id": id,
      "latitude": latitude,
      "longitude": longitude,
      "timestamp": timestamp,
      "accuracy": accuracy,
      "speed": speed,
      "heading": heading,
      "altitude": altitude,
      "batteryLevel": batteryLevel,
      "signalStrength": signalStrength,
      "provider": provider,
      "motionState": motionState,
      "confidence": confidence,
      "distanceFromPrev": distanceFromPrev,
      "cumulativeDistance": cumulativeDistance,
    ]
  }

  func toPositionDictionary() -> [String: Any] {
    [
      "coords": [
        "latitude": latitude,
        "longitude": longitude,
        "altitude": altitude,
        "accuracy": accuracy,
        "heading": heading,
        "speed": speed,
      ],
      "timestamp": timestamp,
    ]
  }

  func toTimeBasedDictionary() -> [String: Any] {
    [
      "coords": [
        "latitude": latitude,
        "longitude": longitude,
        "altitude": altitude,
        "accuracy": accuracy,
        "heading": heading,
        "speed": speed,
      ],
      "timestamp": timestamp,
      "gpsStrength": signalStrength,
      "isStationary": motionState == "stationary",
      "distanceFromPrev": distanceFromPrev,
      "cumulativeDistance": cumulativeDistance,
      "batteryLevel": batteryLevel,
      "motionState": motionState,
    ]
  }
}
