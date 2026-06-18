import Foundation
import SQLite3

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
}

final class LocationDatabase {
  static let shared = LocationDatabase()

  private var db: OpaquePointer?
  private let queue = DispatchQueue(label: "com.micim.geolocation.database", qos: .userInitiated)

  private init() {
    openDatabase()
    createTables()
    migrateIfNeeded()
  }

  deinit {
    if db != nil { sqlite3_close(db) }
  }

  private var dbPath: String {
    let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    return (dir as NSString).appendingPathComponent("micim_geolocation.db")
  }

  private func openDatabase() {
    if sqlite3_open(dbPath, &db) != SQLITE_OK {
      print("[MicimGeolocation] Failed to open database")
    }
  }

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
      delivered_to_js INTEGER DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_locations_pending ON locations(delivered_to_js);
    CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp);
    """
    queue.sync { sqlite3_exec(db, sql, nil, nil, nil) }
  }

  private func migrateIfNeeded() {
    queue.sync {
      var stmt: OpaquePointer?
      let check = "PRAGMA table_info(locations)"
      guard sqlite3_prepare_v2(db, check, -1, &stmt, nil) == SQLITE_OK else { return }
      defer { sqlite3_finalize(stmt) }
      var hasDelivered = false
      while sqlite3_step(stmt) == SQLITE_ROW {
        if let name = sqlite3_column_text(stmt, 1) {
          if String(cString: name) == "delivered_to_js" { hasDelivered = true }
        }
      }
      if !hasDelivered {
        sqlite3_exec(db, "ALTER TABLE locations ADD COLUMN delivered_to_js INTEGER DEFAULT 0", nil, nil, nil)
      }
    }
  }

  /// Write-first: always persist before any JS delivery
  func insert(_ location: StoredLocation) -> Bool {
    queue.sync {
      let sql = """
      INSERT OR REPLACE INTO locations
      (id, latitude, longitude, accuracy, speed, heading, altitude, timestamp,
       battery_level, signal_strength, provider, motion_state, confidence,
       session_id, delivered_to_js)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
      defer { sqlite3_finalize(stmt) }

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
      sqlite3_bind_int(stmt, 15, location.deliveredToJs ? 1 : 0)

      return sqlite3_step(stmt) == SQLITE_DONE
    }
  }

  func markDelivered(ids: [String]) -> Int {
    guard !ids.isEmpty else { return 0 }
    return queue.sync {
      let placeholders = ids.map { _ in "?" }.joined(separator: ",")
      let sql = "UPDATE locations SET delivered_to_js = 1 WHERE id IN (\(placeholders))"
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

  /// Locations collected while JS was suspended — replay to watchPosition callbacks
  func getPendingForJs(limit: Int = 200) -> [StoredLocation] {
    queue.sync {
      var results: [StoredLocation] = []
      let sql = "SELECT * FROM locations WHERE delivered_to_js = 0 ORDER BY timestamp ASC LIMIT ?"
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_int(stmt, 1, Int32(limit))
      while sqlite3_step(stmt) == SQLITE_ROW {
        if let loc = rowToLocation(stmt) { results.append(loc) }
      }
      return results
    }
  }

  func pendingCount() -> Int {
    queue.sync {
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM locations WHERE delivered_to_js = 0", -1, &stmt, nil) == SQLITE_OK else { return 0 }
      defer { sqlite3_finalize(stmt) }
      if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int(stmt, 0)) }
      return 0
    }
  }

  func acknowledge(ids: [String]) -> Int {
    guard !ids.isEmpty else { return 0 }
    return queue.sync {
      let placeholders = ids.map { _ in "?" }.joined(separator: ",")
      let sql = "DELETE FROM locations WHERE id IN (\(placeholders))"
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

  func clearAll() {
    queue.sync { sqlite3_exec(db, "DELETE FROM locations", nil, nil, nil) }
  }

  func purgeDelivered() -> Int {
    queue.sync {
      sqlite3_exec(db, "DELETE FROM locations WHERE delivered_to_js = 1", nil, nil, nil)
      return Int(sqlite3_changes(db))
    }
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
      deliveredToJs: sqlite3_column_int(stmt, 14) == 1
    )
  }
}

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
}
