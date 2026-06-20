import Foundation
import React

@objc(FitnessGeolocation)
class FitnessGeolocation: RCTEventEmitter, LocationEngineDelegate, MotionEngineDelegate, DebugMonitorDelegate {
  private let engine = LocationEngine.shared
  private let motion = MotionEngine.shared
  private let debugMonitor: DebugMonitor = DebugMonitor()
  private var hasListeners = false

  override init() {
    super.init()
    engine.delegate = self
    motion.delegate = self
    debugMonitor.delegate = self
  }

  override static func requiresMainQueueSetup() -> Bool { true }

  override func supportedEvents() -> [String]! {
    ["watchPosition", "authorizationChange", "foregroundSync",
     "motionActivity", "motionSteps", "autoPause", "autoResume",
     "diagnostic", "timeBasedTick", "geofence", "geofencesChange",
     "providerChange", "powerSaveChange", "connectivityChange", "httpResponse",
     "debugMotionState", "debugHeartbeat", "debugEnabledChange", "debugLifecycle"]
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

  // MARK: - Authorization

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

  @objc(setConfiguration:resolver:rejecter:)
  func setConfiguration(_ config: NSDictionary,
                        resolver resolve: @escaping RCTPromiseResolveBlock,
                        rejecter reject: @escaping RCTPromiseRejectBlock) {
    if let mode = config["trackingMode"] as? String {
      engine.setModeString(mode)
    }
    resolve(nil)
  }

  // MARK: - Motion Engine

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

  // MARK: - Time-Based Tracking

  @objc(startTimeBasedTracking:)
  func startTimeBasedTracking(_ options: NSDictionary) -> NSNumber {
    NSNumber(value: engine.startTimeBasedTracking(options: options as? [String: Any] ?? [:]))
  }

  @objc(stopTimeBasedTracking:)
  func stopTimeBasedTracking(_ watchId: NSNumber) {
    engine.stopTimeBasedTracking(watchId.intValue)
  }

  @objc(pauseTimeBasedTracking:)
  func pauseTimeBasedTracking(_ watchId: NSNumber) {
    engine.pauseTimeBasedTracking(watchId.intValue)
  }

  @objc(resumeTimeBasedTracking:)
  func resumeTimeBasedTracking(_ watchId: NSNumber) {
    engine.resumeTimeBasedTracking(watchId.intValue)
  }

  @objc(setTimeBasedInterval:intervalMs:)
  func setTimeBasedInterval(_ watchId: NSNumber, intervalMs: NSNumber) {
    engine.setTimeBasedInterval(watchId.intValue, intervalMs: intervalMs.doubleValue)
  }

  // MARK: - Session Management

  @objc(createSession:activityType:extras:resolver:rejecter:)
  func createSession(_ name: String, activityType: String, extras: String?,
                     resolver resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
    let id = engine.createSession(name: name, activityType: activityType, extras: extras)
    resolve(id)
  }

  @objc(endSession:data:resolver:rejecter:)
  func endSession(_ sessionId: String, data: NSDictionary,
                  resolver resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.endSession(sessionId, data: data as? [String: Any] ?? [:])
    resolve(nil)
  }

  @objc(discardSession:resolver:rejecter:)
  func discardSession(_ sessionId: String,
                      resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.discardSession(sessionId)
    resolve(nil)
  }

  @objc(getPendingSessions:rejecter:)
  func getPendingSessions(_ resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getUnuploadedSessions())
  }

  @objc(getSessionForUpload:resolver:rejecter:)
  func getSessionForUpload(_ sessionId: String,
                           resolver resolve: @escaping RCTPromiseResolveBlock,
                           rejecter reject: @escaping RCTPromiseRejectBlock) {
    if let result = engine.getSessionForUpload(sessionId) {
      resolve(result)
    } else {
      reject("NOT_FOUND", "Session not found", nil)
    }
  }

  @objc(markSessionUploaded:resolver:rejecter:)
  func markSessionUploaded(_ sessionId: String,
                           resolver resolve: @escaping RCTPromiseResolveBlock,
                           rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.markSessionUploaded(sessionId)
    resolve(nil)
  }

  // MARK: - Odometer

  @objc(getOdometer:rejecter:)
  func getOdometer(_ resolve: @escaping RCTPromiseResolveBlock,
                   rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.odometer)
  }

  @objc(resetOdometer:rejecter:)
  func resetOdometer(_ resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.resetOdometer()
    resolve(nil)
  }

  @objc(setOdometer:resolver:rejecter:)
  func setOdometer(_ value: NSNumber,
                   resolver resolve: @escaping RCTPromiseResolveBlock,
                   rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.setOdometer(value.doubleValue)
    resolve(nil)
  }

  // MARK: - Diagnostics & Logging

  @objc(getDiagnostics:rejecter:)
  func getDiagnostics(_ resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getDiagnostics())
  }

  @objc(devLog:tag:message:data:)
  func devLog(_ level: String, tag: String, message: String, data: NSDictionary?) {
    engine.devLog(level, tag, message, (data as? [String: Any]) ?? [:])
  }

  // MARK: - HTTP Sync

  @objc(configureHttp:)
  func configureHttp(_ config: NSDictionary) {
    let map = config as? [String: Any] ?? [:]
    engine.httpConfigure(url: map["url"] as? String,
                        method: map["method"] as? String ?? "POST",
                        headers: map["headers"] as? [String: String] ?? [:],
                        autoSync: map["autoSync"] as? Bool ?? true,
                        batchSync: map["batchSync"] as? Bool ?? true,
                        batchSize: (map["batchSize"] as? NSNumber)?.intValue ?? 100,
                        retryCount: (map["retryCount"] as? NSNumber)?.intValue ?? 3)
  }

  @objc(httpSync:rejecter:)
  func httpSync(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.httpSync())
  }

  @objc(addHttpListener)
  func addHttpListener() {
    engine.httpListenerEnabled = true
  }

  @objc(removeHttpListener)
  func removeHttpListener() {
    engine.httpListenerEnabled = false
  }

  @objc(destroyLocations:rejecter:)
  func destroyLocations(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.destroyAllLocations()
    resolve(nil)
  }

  @objc(getCount:rejecter:)
  func getCount(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.pendingCount())
  }

  // MARK: - Geofencing

  @objc(addGeofence:resolver:rejecter:)
  func addGeofence(_ geofence: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
                   rejecter reject: @escaping RCTPromiseRejectBlock) {
    let map = geofence as? [String: Any] ?? [:]
    resolve(engine.addGeofence(map))
  }

  @objc(addGeofences:resolver:rejecter:)
  func addGeofences(_ geofences: NSArray, resolver resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    let list = geofences.compactMap { $0 as? [String: Any] }
    resolve(engine.addGeofences(list))
  }

  @objc(removeGeofence:resolver:rejecter:)
  func removeGeofence(_ identifier: String, resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.removeGeofence(identifier))
  }

  @objc(removeGeofences:resolver:rejecter:)
  func removeGeofences(_ identifiers: NSArray?, resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    let ids = identifiers?.compactMap { $0 as? String }
    resolve(engine.removeGeofences(ids))
  }

  @objc(getGeofences:rejecter:)
  func getGeofences(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getGeofences())
  }

  @objc(geofenceExists:resolver:rejecter:)
  func geofenceExists(_ identifier: String, resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.geofenceExists(identifier))
  }

  // MARK: - Provider Events

  @objc(getProviderState:rejecter:)
  func getProviderState(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getProviderState())
  }

  @objc(isPowerSaveMode:rejecter:)
  func isPowerSaveMode(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.isPowerSaveMode())
  }

  @objc(getSensors:rejecter:)
  func getSensors(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getSensors())
  }

  @objc(getDeviceInfo:rejecter:)
  func getDeviceInfo(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getDeviceInfo())
  }

  // MARK: - Debug Monitor

  @objc(setDebugMonitorConfig:resolver:rejecter:)
  func setDebugMonitorConfig(_ config: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
                              rejecter reject: @escaping RCTPromiseRejectBlock) {
    debugMonitor.configure(config: config as? [String: Any] ?? [:])
    resolve(nil)
  }

  @objc(getDebugMotionState:rejecter:)
  func getDebugMotionState(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(debugMonitor.getMotionState())
  }

  // MARK: - DebugMonitorDelegate

  func debugMonitor(_ monitor: AnyObject, didChangeEnabled enabled: Bool) {
    guard hasListeners else { return }
    sendEvent(withName: "debugEnabledChange", body: ["enabled": enabled])
  }

  func debugMonitor(_ monitor: AnyObject, didEmitMotionState state: [String: Any]) {
    guard hasListeners else { return }
    sendEvent(withName: "debugMotionState", body: state)
  }

  func debugMonitor(_ monitor: AnyObject, didEmitHeartbeat event: [String: Any]) {
    guard hasListeners else { return }
    sendEvent(withName: "debugHeartbeat", body: event)
  }

  func debugMonitor(_ monitor: AnyObject, didEmitLifecycleEvent event: [String: Any]) {
    guard hasListeners else { return }
    sendEvent(withName: "debugLifecycle", body: event)
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

  func locationEngine(_ engine: LocationEngine, didLog event: [String: Any]) {
    guard hasListeners else { return }

    // Route geofence events to their own channel
    if event["event"] as? String == "geofence" {
      sendEvent(withName: "geofence", body: [
        "identifier": event["identifier"] ?? "",
        "action": event["action"] ?? "",
        "latitude": event["latitude"] ?? 0,
        "longitude": event["longitude"] ?? 0,
        "radius": event["radius"] ?? 0,
        "timestamp": event["timestamp"] ?? Date().timeIntervalSince1970 * 1000,
      ])
      return
    }

    sendEvent(withName: "diagnostic", body: event)
  }

  func locationEngine(_ engine: LocationEngine, didTimeBasedTick location: StoredLocation) {
    guard hasListeners else { return }
    sendEvent(withName: "timeBasedTick", body: location.toTimeBasedDictionary())
  }

  func locationEngine(_ engine: LocationEngine, didGpsStrengthChange strength: String, accuracy: Double) {
    // Forwarded via timeBasedTick data — no dedicated event needed
  }

  func locationEngine(_ engine: LocationEngine, didStationaryChange isStationary: Bool) {
    // Forwarded via timeBasedTick data
  }

  // MARK: - MotionEngineDelegate

  func motionEngine(_ engine: MotionEngine, didUpdate activity: MotionActivityType, confidence: Double) {
    LocationEngine.shared.setMotionState(activity.rawValue)
    // Feed into battery-conscious GPS suspend/resume
    LocationEngine.shared.feedMotionActivity(activity)
    debugMonitor.feedActivity(activity.rawValue, confidence: confidence)
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
    guard autoPauseTriggered else { return }
    // Feed into battery-conscious GPS suspend/resume
    LocationEngine.shared.onStationaryAutoPause()
    guard hasListeners else { return }
    sendEvent(withName: "autoPause", body: ["reason": "stationary"])
  }

  func motionEngine(_ engine: MotionEngine, autoResumeTriggered: Bool) {
    guard autoResumeTriggered else { return }
    // Feed into battery-conscious GPS suspend/resume
    LocationEngine.shared.onMotionResume()
    guard hasListeners else { return }
    sendEvent(withName: "autoResume", body: ["reason": "movement"])
  }
}
