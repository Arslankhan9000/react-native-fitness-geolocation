import Foundation
import React

@objc(FitnessGeolocation)
class FitnessGeolocation: RCTEventEmitter, LocationEngineDelegate, MotionEngineDelegate {
  private let engine = LocationEngine.shared
  private let motion = MotionEngine.shared
  private var hasListeners = false

  override init() {
    super.init()
    engine.delegate = self
    motion.delegate = self
  }

  override static func requiresMainQueueSetup() -> Bool { true }

  override func supportedEvents() -> [String]! {
    ["watchPosition", "authorizationChange", "foregroundSync",
     "motionActivity", "motionSteps", "autoPause", "autoResume"]
  }

  override func startObserving() { hasListeners = true }
  override func stopObserving() { hasListeners = false }

  // MARK: - Geolocation

  @objc(getCurrentPosition:resolver:rejecter:)
  func getCurrentPosition(_ options: NSDictionary,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.getCurrentPosition(options: options as? [String: Any] ?? [:]) { result in
      switch result {
      case .success(let loc): resolve(loc.toPositionDictionary())
      case .failure(let e): reject("POSITION_UNAVAILABLE", e.localizedDescription, e)
      }
    }
  }

  @objc(watchPosition:)
  func watchPosition(_ options: NSDictionary) -> NSNumber {
    NSNumber(value: engine.watchPosition(options: options as? [String: Any] ?? [:]))
  }

  @objc(clearWatch:)
  func clearWatch(_ watchId: NSNumber) { engine.clearWatch(watchId.intValue) }

  @objc(stopLocationObserving)
  func stopLocationObserving() { engine.stopObserving() }

  @objc(getPendingForJs:resolver:rejecter:)
  func getPendingForJs(_ limit: NSNumber, resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getPendingForJs(limit: limit.intValue))
  }

  @objc(markDelivered:resolver:rejecter:)
  func markDelivered(_ ids: [String], resolver resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.markDelivered(ids: ids))
  }

  @objc(purgeDelivered:rejecter:)
  func purgeDelivered(_ resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.purgeDelivered())
  }

  @objc(getQueueSize:rejecter:)
  func getQueueSize(_ resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getQueueSize())
  }

  @objc(requestAuthorization:resolver:rejecter:)
  func requestAuthorization(_ level: String, resolver resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.requestAuthorization(level: level) { resolve($0) }
  }

  @objc(getAuthorizationStatus:rejecter:)
  func getAuthorizationStatus(_ resolve: @escaping RCTPromiseResolveBlock,
                              rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(["status": engine.authorizationStatusString(), "always": engine.hasAlwaysAuthorization()])
  }

  // MARK: - Fitness / Motion API

  @objc(startMotionTracking:resolver:rejecter:)
  func startMotionTracking(_ includePedometer: Bool, resolver resolve: @escaping RCTPromiseResolveBlock,
                           rejecter reject: @escaping RCTPromiseRejectBlock) {
    motion.start(includePedometer: includePedometer)
    resolve(nil)
  }

  @objc(stopMotionTracking:rejecter:)
  func stopMotionTracking(_ resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
    motion.stop()
    resolve(nil)
  }

  @objc(setTrackingMode:resolver:rejecter:)
  func setTrackingMode(_ mode: String, resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.setModeString(mode)
    resolve(nil)
  }

  @objc(setActivityPaused:resolver:rejecter:)
  func setActivityPaused(_ paused: Bool, resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.setPaused(paused)
    resolve(nil)
  }

  @objc(getEngineState:rejecter:)
  func getEngineState(_ resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getEngineState())
  }

  @objc(configureAutoPause:delaySeconds:resolver:rejecter:)
  func configureAutoPause(_ enabled: Bool, delaySeconds: NSNumber,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
    motion.autoPauseEnabled = enabled
    motion.autoPauseDelaySeconds = delaySeconds.doubleValue
    resolve(nil)
  }

  // MARK: - LocationEngineDelegate

  func locationEngine(_ engine: LocationEngine, didPersist location: StoredLocation,
                      watchIds: [Int], deliverLive: Bool) {
    guard hasListeners, deliverLive else { return }
    for watchId in watchIds {
      sendEvent(withName: "watchPosition", body: [
        "watchId": watchId,
        "position": location.toPositionDictionary(),
        "nativeId": location.id,
      ])
    }
  }

  func locationEngine(_ engine: LocationEngine, didFailWithError error: Error, watchIds: [Int]) {
    guard hasListeners else { return }
    for watchId in watchIds {
      sendEvent(withName: "watchPosition", body: [
        "watchId": watchId,
        "error": ["code": 2, "message": error.localizedDescription],
      ])
    }
  }

  func locationEngineDidChangeAuthorization(_ engine: LocationEngine) {
    guard hasListeners else { return }
    sendEvent(withName: "authorizationChange", body: ["status": engine.authorizationStatusString()])
  }

  func locationEngineDidEnterForeground(_ engine: LocationEngine) {
    guard hasListeners else { return }
    sendEvent(withName: "foregroundSync", body: ["pending": engine.pendingCount()])
  }

  // MARK: - MotionEngineDelegate

  func motionEngine(_ engine: MotionEngine, didUpdate activity: MotionActivityType, confidence: Double) {
    LocationEngine.shared.setMotionState(activity.rawValue)
    guard hasListeners else { return }
    sendEvent(withName: "motionActivity", body: [
      "activity": activity.rawValue,
      "confidence": confidence,
    ])
  }

  func motionEngine(_ engine: MotionEngine, didUpdateSteps steps: Int, distanceM: Double) {
    guard hasListeners else { return }
    sendEvent(withName: "motionSteps", body: ["steps": steps, "distanceM": distanceM])
  }

  func motionEngine(_ engine: MotionEngine, autoPauseTriggered: Bool) {
    guard hasListeners, autoPauseTriggered else { return }
    sendEvent(withName: "autoPause", body: ["reason": "stationary"])
  }

  func motionEngine(_ engine: MotionEngine, autoResumeTriggered: Bool) {
    guard hasListeners, autoResumeTriggered else { return }
    sendEvent(withName: "autoResume", body: ["reason": "movement"])
  }
}
