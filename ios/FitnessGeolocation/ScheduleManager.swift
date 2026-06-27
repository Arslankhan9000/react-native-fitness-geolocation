import Foundation

/// Cron-like schedule windows — Transistorsoft-compatible format.
/// Examples: "1-7 09:00-17:00", "1-5 08:00-18:00 geofence"
final class ScheduleManager {
  static let shared = ScheduleManager()

  enum TrackingMode: String {
    case location
    case geofence
  }

  struct Window {
    let days: Set<Int>       // 1=Sunday … 7=Saturday (US)
    let onMinutes: Int       // minutes from midnight
    let offMinutes: Int
    let mode: TrackingMode
    var triggered = false
  }

  private(set) var windows: [Window] = []
  private(set) var isEnabled = false
  var onScheduleChange: ((Bool, TrackingMode) -> Void)?

  private init() {}

  func configure(records: [String]) {
    windows = records.compactMap { parse($0) }
  }

  func start() {
    isEnabled = true
    evaluate()
  }

  func stop() {
    isEnabled = false
    windows.indices.forEach { windows[$0].triggered = false }
  }

  /// Call on location tick, app resume, and background fetch.
  func evaluate(now: Date = Date()) {
    guard isEnabled, !windows.isEmpty else { return }
    let cal = Calendar.current
    let weekday = cal.component(.weekday, from: now) // 1=Sun
    let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

    for i in windows.indices {
      var w = windows[i]
      guard w.days.contains(weekday) else { continue }
      let inWindow: Bool
      if w.onMinutes <= w.offMinutes {
        inWindow = minutes >= w.onMinutes && minutes < w.offMinutes
      } else {
        // overnight window e.g. 22:00-06:00
        inWindow = minutes >= w.onMinutes || minutes < w.offMinutes
      }
      if inWindow && !w.triggered {
        w.triggered = true
        windows[i] = w
        onScheduleChange?(true, w.mode)
      } else if !inWindow && w.triggered {
        w.triggered = false
        windows[i] = w
        onScheduleChange?(false, w.mode)
      }
    }
  }

  func stateDict() -> [String: Any] {
    ["schedulerEnabled": isEnabled, "scheduleCount": windows.count]
  }

  // MARK: - Parser

  private func parse(_ record: String) -> Window? {
    let parts = record.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 2 else { return nil }
    let dayPart = String(parts[0])
    let timePart = String(parts[1])
    let mode: TrackingMode = parts.count >= 3 && parts[2].lowercased() == "geofence" ? .geofence : .location

    guard let days = parseDays(dayPart),
          let (on, off) = parseTimeRange(timePart) else { return nil }
    return Window(days: days, onMinutes: on, offMinutes: off, mode: mode)
  }

  private func parseDays(_ s: String) -> Set<Int>? {
    if s.contains("-") {
      let bounds = s.split(separator: "-")
      guard bounds.count == 2,
            let lo = Int(bounds[0]), let hi = Int(bounds[1]) else { return nil }
      return Set(lo...hi)
    }
    if let d = Int(s) { return [d] }
    return nil
  }

  private func parseTimeRange(_ s: String) -> (Int, Int)? {
    let bounds = s.split(separator: "-")
    guard bounds.count == 2,
          let on = parseTime(String(bounds[0])),
          let off = parseTime(String(bounds[1])) else { return nil }
    return (on, off)
  }

  private func parseTime(_ s: String) -> Int? {
    let p = s.split(separator: ":")
    guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
    return h * 60 + m
  }
}
