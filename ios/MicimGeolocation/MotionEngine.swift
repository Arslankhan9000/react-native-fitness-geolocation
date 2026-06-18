import Foundation
import CoreMotion

enum MotionActivityType: String {
  case stationary, walking, running, cycling, driving, unknown
}

protocol MotionEngineDelegate: AnyObject {
  func motionEngine(_ engine: MotionEngine, didUpdate activity: MotionActivityType, confidence: Double)
  func motionEngine(_ engine: MotionEngine, didUpdateSteps steps: Int, distanceM: Double)
  func motionEngine(_ engine: MotionEngine, autoPauseTriggered: Bool)
  func motionEngine(_ engine: MotionEngine, autoResumeTriggered: Bool)
}

/// Strava/Garmin-class motion intelligence — runs natively, survives JS suspension
final class MotionEngine {
  static let shared = MotionEngine()

  weak var delegate: MotionEngineDelegate?

  private let activityManager = CMMotionActivityManager()
  private let pedometer = CMPedometer()
  private var isRunning = false
  private var currentActivity: MotionActivityType = .unknown
  private var stationarySince: Date?
  private var lastStepCount = 0

  var autoPauseEnabled = true
  var autoPauseDelaySeconds: TimeInterval = 45
  var autoResumeEnabled = true

  private init() {}

  func start(includePedometer: Bool = false) {
    guard !isRunning else { return }
    isRunning = true
    startActivityUpdates()
    if includePedometer && CMPedometer.isStepCountingAvailable() {
      startPedometerUpdates()
    }
  }

  func stop() {
    isRunning = false
    activityManager.stopActivityUpdates()
    pedometer.stopUpdates()
    stationarySince = nil
  }

  func currentActivityType() -> String { currentActivity.rawValue }

  private func startActivityUpdates() {
    guard CMMotionActivityManager.isActivityAvailable() else { return }
    activityManager.startActivityUpdates(to: .main) { [weak self] activity in
      guard let self = self, let a = activity else { return }
      let type = self.classify(a)
      let confidence = self.confidence(for: a)
      self.currentActivity = type
      self.delegate?.motionEngine(self, didUpdate: type, confidence: confidence)
      self.evaluateAutoPauseResume(type: type)
    }
  }

  private func startPedometerUpdates() {
    var previousSteps = 0
    pedometer.startUpdates(from: Date()) { [weak self] data, _ in
      guard let self = self, let data = data else { return }
      let steps = data.numberOfSteps.intValue
      let dist = data.distance?.doubleValue ?? 0
      if self.autoResumeEnabled && steps > previousSteps + 3 {
        self.delegate?.motionEngine(self, autoResumeTriggered: true)
      }
      previousSteps = steps
      self.lastStepCount = steps
      self.delegate?.motionEngine(self, didUpdateSteps: steps, distanceM: dist)
    }
  }

  private func classify(_ a: CMMotionActivity) -> MotionActivityType {
    if a.stationary { return .stationary }
    if a.running { return .running }
    if a.walking { return .walking }
    if a.cycling { return .cycling }
    if a.automotive { return .driving }
    return .unknown
  }

  private func confidence(for a: CMMotionActivity) -> Double {
    if a.stationary { return a.stationary ? 0.9 : 0.5 }
    if a.walking { return 0.85 }
    if a.running { return 0.9 }
    if a.cycling { return 0.85 }
    if a.automotive { return 0.8 }
    return 0.5
  }

  private func evaluateAutoPauseResume(type: MotionActivityType) {
    if type == .stationary {
      if stationarySince == nil { stationarySince = Date() }
      if autoPauseEnabled,
         let since = stationarySince,
         Date().timeIntervalSince(since) >= autoPauseDelaySeconds {
        delegate?.motionEngine(self, autoPauseTriggered: true)
        stationarySince = Date() // debounce
      }
    } else if type == .walking || type == .running || type == .cycling {
      stationarySince = nil
      if autoResumeEnabled {
        delegate?.motionEngine(self, autoResumeTriggered: true)
      }
    }
  }
}
