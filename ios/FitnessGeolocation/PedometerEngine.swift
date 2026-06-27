import Foundation
import CoreMotion
import UIKit

/// Passive step session engine — CMPedometer + gap query recovery (HealthKit-style, no notification).
protocol PedometerEngineDelegate: AnyObject {
  func pedometerEngine(_ engine: PedometerEngine, didUpdate payload: [String: Any])
}

final class PedometerEngine {
  static let shared = PedometerEngine()

  weak var delegate: PedometerEngineDelegate?

  private let pedometer = CMPedometer()
  private let prefs = UserDefaults.standard
  private let sessionKey = "com.fitnessgeolocation.pedometer.session"
  private let queue = OperationQueue()

  private var isRunning = false
  private var sessionId: String?
  private var sessionStartMs: Double = 0
  private var sessionSteps = 0
  private var sessionDistanceM = 0.0
  private var floorsAscended = 0
  private var floorsDescended = 0
  private var lastEventMs: Double = 0
  private var counterType = "CMPedometer"

  private init() {
    queue.maxConcurrentOperationCount = 1
    queue.name = "com.fitnessgeolocation.pedometer"
    restorePersistedSession()
  }

  // MARK: - Capability

  func isSupported() -> Bool {
    CMPedometer.isStepCountingAvailable()
  }

  func isAuthorized() -> Bool {
    switch CMPedometer.authorizationStatus() {
    case .authorized, .notDetermined:
      return true
    default:
      return false
    }
  }

  func authorizationStatusString() -> String {
    switch CMPedometer.authorizationStatus() {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not_determined"
    @unknown default: return "unknown"
    }
  }

  // MARK: - Lifecycle

  func start(sessionId: String?, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    guard isSupported() else {
      completion(.failure(NSError(domain: "Pedometer", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Step counting not available on this device"])))
      return
    }

    // Idempotent resume
    if isRunning, let sid = self.sessionId {
      reconcileGap(from: Date(timeIntervalSince1970: sessionStartMs / 1000)) { [weak self] in
        guard let self = self else { return }
        self.startLiveUpdates()
        var snap = self.snapshotDict()
        snap["sessionId"] = sessionId ?? sid
        completion(.success(snap))
      }
      return
    }

    let sid = sessionId ?? UUID().uuidString
    let now = Date()
    sessionStartMs = now.timeIntervalSince1970 * 1000
    self.sessionId = sid
    sessionSteps = 0
    sessionDistanceM = 0
    floorsAscended = 0
    floorsDescended = 0
    isRunning = true
    counterType = "CMPedometer"
    persistSession()

    reconcileGap(from: now) { [weak self] in
      guard let self = self else { return }
      self.startLiveUpdates()
      completion(.success(self.snapshotDict()))
    }
  }

  func stop(completion: @escaping ([String: Any]) -> Void) {
    guard isRunning else {
      completion(snapshotDict())
      return
    }

    let end = Date()
    reconcileGap(from: Date(timeIntervalSince1970: sessionStartMs / 1000)) { [weak self] in
      guard let self = self else { return }
      self.pedometer.stopUpdates()
      self.isRunning = false
      self.clearPersistedSession()
      completion(self.snapshotDict())
    }
    _ = end
  }

  func snapshot() -> [String: Any] {
    snapshotDict()
  }

  func query(fromMs: Double, toMs: Double, completion: @escaping (Result<[String: Any], Error>) -> Void) {
    guard isSupported() else {
      completion(.failure(NSError(domain: "Pedometer", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Step counting not available"])))
      return
    }
    let from = Date(timeIntervalSince1970: fromMs / 1000)
    let to = Date(timeIntervalSince1970: toMs / 1000)
    pedometer.queryPedometerData(from: from, to: to) { data, error in
      if let error = error {
        completion(.failure(error))
        return
      }
      guard let data = data else {
        completion(.success(self.emptyQuery(fromMs: fromMs, toMs: toMs)))
        return
      }
      completion(.success([
        "steps": data.numberOfSteps.intValue,
        "distance": data.distance?.doubleValue ?? 0,
        "startDate": fromMs,
        "endDate": toMs,
        "floorsAscended": data.floorsAscended?.intValue ?? 0,
        "floorsDescended": data.floorsDescended?.intValue ?? 0,
        "counterType": "CMPedometer",
        "source": "query",
      ]))
    }
  }

  func onAppForeground() {
    guard isRunning else { return }
    reconcileGap(from: Date(timeIntervalSince1970: sessionStartMs / 1000)) { [weak self] in
      guard let self = self, self.isRunning else { return }
      self.startLiveUpdates()
      self.emitUpdate(source: "foreground_reconcile")
    }
  }

  // MARK: - Private

  /// Always anchor live updates to session start — never `Date()` or steps reset on resume.
  private func startLiveUpdates() {
    let startDate = Date(timeIntervalSince1970: sessionStartMs / 1000)
    pedometer.stopUpdates()
    pedometer.startUpdates(from: startDate) { [weak self] data, error in
      guard let self = self, self.isRunning else { return }
      if error != nil { return }
      guard let data = data else { return }
      let steps = data.numberOfSteps.intValue
      let dist = data.distance?.doubleValue ?? 0
      self.sessionSteps = max(self.sessionSteps, steps)
      self.sessionDistanceM = max(self.sessionDistanceM, dist)
      self.floorsAscended = data.floorsAscended?.intValue ?? self.floorsAscended
      self.floorsDescended = data.floorsDescended?.intValue ?? self.floorsDescended
      self.lastEventMs = Date().timeIntervalSince1970 * 1000
      self.persistSession()
      self.emitUpdate(source: "live")
    }
  }

  /// Query CMPedometer for steps since session start — fills gaps after kill/background.
  private func reconcileGap(from startDate: Date, completion: @escaping () -> Void) {
    let end = Date()
    pedometer.queryPedometerData(from: startDate, to: end) { [weak self] data, _ in
      guard let self = self else { completion(); return }
      if let data = data {
        self.sessionSteps = max(self.sessionSteps, data.numberOfSteps.intValue)
        self.sessionDistanceM = max(self.sessionDistanceM, data.distance?.doubleValue ?? 0)
        self.floorsAscended = data.floorsAscended?.intValue ?? self.floorsAscended
        self.floorsDescended = data.floorsDescended?.intValue ?? self.floorsDescended
        self.lastEventMs = end.timeIntervalSince1970 * 1000
        self.persistSession()
      }
      completion()
    }
  }

  private func emitUpdate(source: String) {
    var payload = snapshotDict()
    payload["source"] = source
    delegate?.pedometerEngine(self, didUpdate: payload)
  }

  private func snapshotDict() -> [String: Any] {
    [
      "sessionId": sessionId as Any,
      "isRunning": isRunning,
      "steps": sessionSteps,
      "distance": sessionDistanceM,
      "startDate": sessionStartMs,
      "endDate": lastEventMs > 0 ? lastEventMs : Date().timeIntervalSince1970 * 1000,
      "floorsAscended": floorsAscended,
      "floorsDescended": floorsDescended,
      "counterType": counterType,
      "cadenceSpm": NSNull(),
      "averageSpeedMps": NSNull(),
    ]
  }

  private func emptyQuery(fromMs: Double, toMs: Double) -> [String: Any] {
    [
      "steps": 0,
      "distance": 0,
      "startDate": fromMs,
      "endDate": toMs,
      "counterType": "CMPedometer",
      "source": "query",
    ]
  }

  private func persistSession() {
    guard isRunning, let sid = sessionId else { return }
    prefs.set([
      "sessionId": sid,
      "sessionStartMs": sessionStartMs,
      "sessionSteps": sessionSteps,
      "sessionDistanceM": sessionDistanceM,
      "floorsAscended": floorsAscended,
      "floorsDescended": floorsDescended,
      "lastEventMs": lastEventMs,
      "isRunning": true,
    ], forKey: sessionKey)
  }

  private func clearPersistedSession() {
    prefs.removeObject(forKey: sessionKey)
  }

  private func restorePersistedSession() {
    guard let dict = prefs.dictionary(forKey: sessionKey),
          dict["isRunning"] as? Bool == true else { return }
    sessionId = dict["sessionId"] as? String
    sessionStartMs = dict["sessionStartMs"] as? Double ?? 0
    sessionSteps = dict["sessionSteps"] as? Int ?? 0
    sessionDistanceM = dict["sessionDistanceM"] as? Double ?? 0
    floorsAscended = dict["floorsAscended"] as? Int ?? 0
    floorsDescended = dict["floorsDescended"] as? Int ?? 0
    lastEventMs = dict["lastEventMs"] as? Double ?? 0
    isRunning = true
  }

  func getDiagnostics() -> [String: Any] {
    [
      "manufacturer": "Apple",
      "model": UIDevice.current.model,
      "platform": "ios",
      "counterType": counterType,
      "isRunning": isRunning,
      "hasStepCounter": CMPedometer.isStepCountingAvailable(),
      "hasStepDetector": false,
      "hasAccelerometerFallback": false,
      "oemRestrictionLevel": "none",
      "oemAggressiveBackground": false,
      "oemSettingsLabel": NSNull(),
      "oemPedometerNote": "Enable Motion & Fitness access for step counting. Low Power Mode may delay updates.",
      "sessionSteps": sessionSteps,
      "needsReconcile": false,
      "motionAuth": authorizationStatusString(),
    ]
  }
}
