import Foundation
import UIKit
import AudioToolbox
import UserNotifications
import os.log

// MARK: - Motion State Machine

enum MotionState: String {
  case moving, stationary
}

/// Binary motion state machine with stopTimeout hysteresis.
/// Mirrors transistorsoft's detection: moving ↔ stationary with 5-min timeout.
class MotionStateMachine {
  var state: MotionState = .stationary
  var stopTimeoutMinutes: TimeInterval = 5
  var currentActivity: String = "unknown"
  var currentConfidence: Double = 0
  var stateSince: Date = Date()
  var stopTimerRemaining: TimeInterval = 0

  private var stopTimer: Timer?
  private var stationarySince: Date?
  weak var delegate: MotionStateMachineDelegate?

  func feedActivity(_ activity: String, confidence: Double, timestamp: Date) {
    currentActivity = activity
    currentConfidence = confidence

    switch activity {
    case "walking", "running", "cycling", "driving":
      transitionTo(.moving, timestamp: timestamp)
    case "stationary", "unknown":
      startStopTimeout(timestamp: timestamp)
    default:
      break
    }
  }

  func feedSpeed(_ speed: Double, timestamp: Date) {
    if speed > 0.5 {
      // Speed indicates movement
      transitionTo(.moving, timestamp: timestamp)
    }
  }

  private func startStopTimeout(timestamp: Date) {
    if state == .stationary { return } // Already stationary
    if stopTimer != nil { return } // Timer already running

    stopTimer = Timer.scheduledTimer(withTimeInterval: stopTimeoutMinutes * 60, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.stopTimer = nil
      self.stopTimerRemaining = 0
      self.transitionTo(.stationary, timestamp: Date())
      self.delegate?.motionStateMachine(self, didFire: "stop_timeout_start", message: "Stop timeout elapsed — now stationary")
      self.delegate?.motionStateMachine(self, didPlaySound: "stop_timeout_start")
    }
    stopTimerRemaining = stopTimeoutMinutes * 60

    delegate?.motionStateMachine(self, didFire: "stop_timeout_start", message: "Device still — stop timeout \(Int(stopTimeoutMinutes))min started")
    delegate?.motionStateMachine(self, didPlaySound: "stop_timeout_start")
  }

  func cancelStopTimeout() {
    guard stopTimer != nil else { return }
    stopTimer?.invalidate()
    stopTimer = nil
    stopTimerRemaining = 0
    delegate?.motionStateMachine(self, didFire: "stop_timeout_cancel", message: "Device moved — stop timeout cancelled")
    delegate?.motionStateMachine(self, didPlaySound: "stop_timeout_cancel")
  }

  private func transitionTo(_ newState: MotionState, timestamp: Date) {
    guard state != newState else {
      // Cancel stop timeout if we're moving and timer was running
      if newState == .moving { cancelStopTimeout() }
      return
    }

    let oldState = state
    state = newState
    stateSince = timestamp

    if newState == .moving {
      cancelStopTimeout()
      stationarySince = nil
    } else {
      stationarySince = timestamp
    }

    delegate?.motionStateMachine(self, didChangeState: newState, from: oldState, activity: currentActivity)
    delegate?.motionStateMachine(self, didPlaySound: newState == .moving ? "motionchange_true" : "motionchange_false")

    let msg = newState == .moving
      ? "Started moving — \(currentActivity)"
      : "Stopped — now stationary"
    delegate?.motionStateMachine(self, didFire: "motionchange", message: msg)
  }

  func reset() {
    stopTimer?.invalidate()
    stopTimer = nil
    stopTimerRemaining = 0
    state = .stationary
    stateSince = Date()
    stationarySince = nil
    currentActivity = "unknown"
  }

  func toDictionary() -> [String: Any] {
    [
      "state": state.rawValue,
      "activity": currentActivity,
      "confidence": currentConfidence,
      "sinceTimestamp": stateSince.timeIntervalSince1970 * 1000,
      "stopTimeoutRemaining": stopTimerRemaining,
    ]
  }
}

protocol MotionStateMachineDelegate: AnyObject {
  func motionStateMachine(_ machine: MotionStateMachine, didChangeState state: MotionState, from oldState: MotionState, activity: String)
  func motionStateMachine(_ machine: MotionStateMachine, didFire event: String, message: String)
  func motionStateMachine(_ machine: MotionStateMachine, didPlaySound sound: String)
}

// MARK: - Heartbeat Engine

class HeartbeatEngine {
  var intervalSeconds: TimeInterval = 60
  private var timer: Timer?
  weak var delegate: HeartbeatEngineDelegate?

  func start() {
    stop()
    timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      self.delegate?.heartbeatEngine(self, didHeartbeat: [
        "event": "heartbeat",
        "message": "Heartbeat",
        "timestamp": Date().timeIntervalSince1970 * 1000,
      ])
      self.delegate?.heartbeatEngine(self, didPlaySound: "heartbeat")
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }
}

protocol HeartbeatEngineDelegate: AnyObject {
  func heartbeatEngine(_ engine: HeartbeatEngine, didHeartbeat event: [String: Any])
  func heartbeatEngine(_ engine: HeartbeatEngine, didPlaySound sound: String)
}

// MARK: - Debug Notification Manager

class DebugNotificationManager {
  private var currentActivityText: String = "Stationary"
  private let oslog = OSLog(subsystem: "com.fitnessgeolocation", category: "debug-notif")

  func updateActivityText(_ text: String) {
    currentActivityText = text
  }

  func getActivityText() -> String { currentActivityText }

  func postLocalNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = nil // We play our own sounds

    let request = UNNotificationRequest(
      identifier: "com.fitnessgeolocation.debug.\(UUID().uuidString)",
      content: content,
      trigger: nil // Immediate
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        os_log(.error, log: self.oslog, "notification_error: %@", error.localizedDescription)
      }
    }
  }

  func updateAndroidNotification(text: String) {
    // This is a no-op on iOS — Android handles it natively
  }
}

// MARK: - Sound Manager

class DebugSoundManager {
  private let oslog = OSLog(subsystem: "com.fitnessgeolocation", category: "debug-sound")
  var soundEnabled = true

  /// System sound IDs mapped to lifecycle events
  private let soundMap: [String: UInt32] = [
    "motionchange_true": 1016,    // Received Message (short chime)
    "motionchange_false": 1075,   // Mail Sent (descending tone)
    "location_recorded": 1104,    // SMS Received (short click)
    "location_error": 1006,       // Voice mail (error-like)
    "heartbeat": 1105,            // SMS Sent (subtle tick)
    "geofence_enter": 1023,       // Received Message (different pitch)
    "geofence_exit": 1075,        // Mail Sent
    "stop_timeout_start": 1004,   // Begin Recording (alert-like)
    "stop_timeout_cancel": 1070,  // Key Press (cancel-like)
    "stop_detection_delay": 1110, // SMS Received 2
  ]

  func play(_ sound: String) {
    guard soundEnabled else { return }
    if let soundId = soundMap[sound] {
      AudioServicesPlaySystemSound(soundId)
      os_log(.debug, log: oslog, "sound: %@ (id: %d)", sound, soundId)
    }
  }
}

// MARK: - DebugMonitor (Orchestrator)

class DebugMonitor: NSObject {
  let stateMachine = MotionStateMachine()
  let heartbeat = HeartbeatEngine()
  let notifications = DebugNotificationManager()
  let sounds = DebugSoundManager()

  weak var delegate: DebugMonitorDelegate?

  private var _enabled = false
  private let oslog = OSLog(subsystem: "com.fitnessgeolocation", category: "debug-monitor")

  // Activity → notification text mapping
  private var notificationTexts: [String: String] = [
    "stationary": "Stationary",
    "walking": "Walking",
    "running": "Running",
    "cycling": "Cycling",
    "driving": "Driving",
    "unknown": "Stationary",
    "moving": "Moving",
  ]

  var enabled: Bool {
    get { _enabled }
    set {
      let changed = _enabled != newValue
      _enabled = newValue
      if changed {
        delegate?.debugMonitor(self, didChangeEnabled: newValue)
        emitLifecycle("enabledChange", newValue ? "Debug monitoring enabled" : "Debug monitoring disabled")
      }
    }
  }

  override init() {
    super.init()
    stateMachine.delegate = self
    heartbeat.delegate = self
  }

  func configure(config: [String: Any]) {
    if let stopTimeout = config["stopTimeoutMinutes"] as? NSNumber {
      stateMachine.stopTimeoutMinutes = stopTimeout.doubleValue
    }
    if let heartbeatInterval = config["heartbeatIntervalSeconds"] as? NSNumber {
      heartbeat.intervalSeconds = heartbeatInterval.doubleValue
    }
    if let sound = config["sound"] as? Bool {
      sounds.soundEnabled = sound
    }

    // Notification text templates
    if let text = config["notificationTextStationary"] as? String { notificationTexts["stationary"] = text }
    if let text = config["notificationTextWalking"] as? String { notificationTexts["walking"] = text }
    if let text = config["notificationTextRunning"] as? String { notificationTexts["running"] = text }
    if let text = config["notificationTextCycling"] as? String { notificationTexts["cycling"] = text }
    if let text = config["notificationTextDriving"] as? String { notificationTexts["driving"] = text }
    if let text = config["notificationTextMoving"] as? String { notificationTexts["moving"] = text }
    if let title = config["notificationTitle"] as? String {
      UserDefaults.standard.set(title, forKey: "notification_title")
    }

    let wasEnabled = enabled
    enabled = config["enabled"] as? Bool ?? wasEnabled

    if enabled {
      heartbeat.start()
      emitLifecycle("configured", "Debug monitor configured")
    } else {
      heartbeat.stop()
    }

    os_log(.debug, log: oslog, "configured enabled=%d stopTimeout=%.1fmin heartbeat=%.1fs",
           enabled, stateMachine.stopTimeoutMinutes, heartbeat.intervalSeconds)
  }

  /// Feed motion activity into the state machine
  func feedActivity(_ activity: String, confidence: Double) {
    guard enabled else { return }
    stateMachine.feedActivity(activity, confidence: confidence, timestamp: Date())
    updateNotificationText(for: activity)
  }

  /// Feed speed data into the state machine
  func feedSpeed(_ speed: Double) {
    guard enabled else { return }
    stateMachine.feedSpeed(speed, timestamp: Date())
  }

  func getMotionState() -> [String: Any] {
    stateMachine.toDictionary()
  }

  func reset() {
    stateMachine.reset()
    heartbeat.stop()
    enabled = false
  }

  private func updateNotificationText(for activity: String) {
    let text: String
    switch activity {
    case "walking": text = notificationTexts["walking"] ?? "Walking"
    case "running": text = notificationTexts["running"] ?? "Running"
    case "cycling": text = notificationTexts["cycling"] ?? "Cycling"
    case "driving": text = notificationTexts["driving"] ?? "Driving"
    case "stationary": text = notificationTexts["stationary"] ?? "Stationary"
    default:
      text = stateMachine.state == .moving
        ? (notificationTexts["moving"] ?? "Moving")
        : (notificationTexts["stationary"] ?? "Stationary")
    }
    notifications.updateActivityText(text)
  }

  private func emitLifecycle(_ event: String, _ message: String, data: [String: Any] = [:]) {
    var payload: [String: Any] = data
    payload["event"] = event
    payload["message"] = message
    payload["timestamp"] = Date().timeIntervalSince1970 * 1000
    delegate?.debugMonitor(self, didEmitLifecycleEvent: payload)
  }
}

// MARK: - Delegates

extension DebugMonitor: MotionStateMachineDelegate {
  func motionStateMachine(_ machine: MotionStateMachine, didChangeState state: MotionState, from oldState: MotionState, activity: String) {
    let payload = machine.toDictionary()
    delegate?.debugMonitor(self, didEmitMotionState: payload)
    emitLifecycle("motionStateChange", "State: \(state.rawValue) — \(activity)", data: payload)
    updateNotificationText(for: activity)
  }

  func motionStateMachine(_ machine: MotionStateMachine, didFire event: String, message: String) {
    emitLifecycle(event, message)
    if event == "stop_timeout_start" || event == "stop_timeout_cancel" {
      notifications.postLocalNotification(title: "FitnessGeolocation", body: message)
    }
  }

  func motionStateMachine(_ machine: MotionStateMachine, didPlaySound sound: String) {
    sounds.play(sound)
  }
}

extension DebugMonitor: HeartbeatEngineDelegate {
  func heartbeatEngine(_ engine: HeartbeatEngine, didHeartbeat event: [String: Any]) {
    delegate?.debugMonitor(self, didEmitHeartbeat: event)
  }

  func heartbeatEngine(_ engine: HeartbeatEngine, didPlaySound sound: String) {
    sounds.play(sound)
  }
}
