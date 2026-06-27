import Foundation
import SQLite3
import os.log

/// Persistent native log ring — field diagnostics for support teams.
final class NativeLogger {
  static let shared = NativeLogger()

  private var db: OpaquePointer?
  private let queue = DispatchQueue(label: "com.fitnessgeolocation.logger", qos: .utility)
  private let log = OSLog(subsystem: "com.fitnessgeolocation", category: "logger")
  private var maxDays = 3
  private var minLevel = 0

  private func levelValue(_ level: String) -> Int {
    switch level.uppercased() {
    case "ERROR": return 1
    case "WARN", "WARNING": return 2
    case "INFO": return 3
    case "DEBUG": return 4
    case "VERBOSE", "TRACE": return 5
    default: return 3
    }
  }

  func setMinLevel(_ level: Int) {
    minLevel = max(0, min(5, level))
  }

  private init() {
    openDatabase()
    createTable()
  }

  deinit {
    if db != nil { sqlite3_close(db) }
  }

  private var dbPath: String {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return dir.appendingPathComponent("fitness_geolocation.db").path
  }

  private func openDatabase() {
    if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
      os_log(.error, log: log, "logger: failed to open db")
    }
  }

  private func createTable() {
    queue.sync {
      sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS native_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          level TEXT NOT NULL,
          message TEXT NOT NULL,
          timestamp INTEGER NOT NULL
        )
      """, nil, nil, nil)
      sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_native_logs_ts ON native_logs(timestamp)", nil, nil, nil)
    }
  }

  func setMaxDays(_ days: Int) {
    maxDays = max(1, days)
    purgeOld()
  }

  func log(level: String, message: String) {
    let value = levelValue(level)
    guard minLevel > 0, value <= minLevel else { return }
    queue.async { [weak self] in
      guard let self = self, let db = self.db else { return }
      var stmt: OpaquePointer?
      let sql = "INSERT INTO native_logs (level, message, timestamp) VALUES (?, ?, ?)"
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
      defer { sqlite3_finalize(stmt) }
      sqlite3_bind_text(stmt, 1, (level as NSString).utf8String, -1, nil)
      sqlite3_bind_text(stmt, 2, (message as NSString).utf8String, -1, nil)
      sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970 * 1000))
      _ = sqlite3_step(stmt)
      self.purgeOld()
    }
  }

  func getLog(start: Int64?, end: Int64?, order: Int, limit: Int) -> String {
    queue.sync {
      guard let db = self.db else { return "" }
      var clauses: [String] = []
      if let s = start { clauses.append("timestamp >= \(s)") }
      if let e = end { clauses.append("timestamp <= \(e)") }
      let whereClause = clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))"
      let orderDir = order >= 0 ? "ASC" : "DESC"
      let sql = "SELECT level, message, timestamp FROM native_logs \(whereClause) ORDER BY timestamp \(orderDir) LIMIT \(limit)"
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return "" }
      defer { sqlite3_finalize(stmt) }
      var lines: [String] = []
      while sqlite3_step(stmt) == SQLITE_ROW {
        let level = String(cString: sqlite3_column_text(stmt, 0))
        let msg = String(cString: sqlite3_column_text(stmt, 1))
        let ts = sqlite3_column_int64(stmt, 2)
        lines.append("[\(ts)] [\(level)] \(msg)")
      }
      return lines.joined(separator: "\n")
    }
  }

  func destroyLog() {
    queue.sync {
      sqlite3_exec(db, "DELETE FROM native_logs", nil, nil, nil)
    }
  }

  private func purgeOld() {
    let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(maxDays) * 86_400_000
    sqlite3_exec(db, "DELETE FROM native_logs WHERE timestamp < \(cutoff)", nil, nil, nil)
  }
}
