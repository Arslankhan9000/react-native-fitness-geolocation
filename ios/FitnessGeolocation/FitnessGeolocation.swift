import Foundation
import React

@objc(FitnessGeolocation)
class FitnessGeolocation: RCTEventEmitter, LocationEngineDelegate, MotionEngineDelegate, DebugMonitorDelegate, PedometerEngineDelegate {
  private let engine = LocationEngine.shared
  private let motion = MotionEngine.shared
  private let pedometer = PedometerEngine.shared
  private let debugMonitor: DebugMonitor = DebugMonitor()
  private var hasListeners = false

  override init() {
    super.init()
    engine.delegate = self
    motion.delegate = self
    pedometer.delegate = self
    debugMonitor.delegate = self
  }

  override static func requiresMainQueueSetup() -> Bool { true }

  override func supportedEvents() -> [String]! {
    ["watchPosition", "authorizationChange", "foregroundSync",
     "motionActivity", "motionSteps", "autoPause", "autoResume",
     "diagnostic", "timeBasedTick", "geofence", "geofencesChange",
     "providerChange", "powerSaveChange", "connectivityChange", "httpResponse",
     "location", "motionchange", "heartbeat", "schedule", "enabledchange",
     "debugMotionState", "debugHeartbeat", "debugEnabledChange", "debugLifecycle",
     "pedometerUpdate"]
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
  func stopLocationObserving() {
    engine.stopObserving()
    motion.stop()
  }

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

  @objc(configureLogger:resolver:rejecter:)
  func configureLogger(_ config: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    let dict = config as? [String: Any] ?? [:]
    let level = (dict["logLevel"] as? NSNumber)?.intValue ?? (dict["logLevel"] as? Int) ?? 0
    let maxDays = (dict["logMaxDays"] as? NSNumber)?.intValue ?? (dict["logMaxDays"] as? Int) ?? 3
    engine.configureLogger(logLevel: level, logMaxDays: maxDays)
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
    debugMonitor.feedSpeed(Double(location.speed))
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
    let eventName = event["event"] as? String ?? ""
    if debugMonitor.enabled {
      switch eventName {
      case "watch-start":
        debugMonitor.postDebugNotification(body: "GPS watch started")
      case "watch-stop", "stop-observing":
        debugMonitor.postDebugNotification(body: "GPS watch stopped")
      case "gps-pause":
        debugMonitor.postDebugNotification(body: "GPS paused")
      case "gps-resume":
        debugMonitor.postDebugNotification(body: "GPS resumed")
      case "watch-restore":
        debugMonitor.postDebugNotification(body: "GPS watch restored after relaunch")
      case "foreground":
        debugMonitor.postDebugNotification(body: "App foreground — pending: \(event["pending"] ?? 0)")
      case "terminate":
        debugMonitor.postDebugNotification(body: "App terminating — geofence armed")
      default:
        break
      }
    }

    guard hasListeners else { return }

    switch eventName {
    case "geofence":
      sendEvent(withName: "geofence", body: [
        "identifier": event["identifier"] ?? "",
        "action": event["action"] ?? "",
        "latitude": event["latitude"] ?? 0,
        "longitude": event["longitude"] ?? 0,
        "radius": event["radius"] ?? 0,
        "timestamp": event["timestamp"] ?? Date().timeIntervalSince1970 * 1000,
      ])
    case "geofencesChange":
      sendEvent(withName: "geofencesChange", body: [
        "on": event["on"] ?? [],
        "off": event["off"] ?? [],
      ])
    case "httpResponse":
      sendEvent(withName: "httpResponse", body: event)
    case "location":
      sendEvent(withName: "location", body: event["location"] ?? event)
    case "motionchange":
      sendEvent(withName: "motionchange", body: event)
    case "heartbeat":
      sendEvent(withName: "heartbeat", body: event)
    case "schedule":
      sendEvent(withName: "schedule", body: event)
    case "enabledchange":
      sendEvent(withName: "enabledchange", body: event)
    default:
      sendEvent(withName: "diagnostic", body: event)
    }
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

  // MARK: - Pedometer

  @objc(pedometerIsSupported:rejecter:)
  func pedometerIsSupported(_ resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve([
      "supported": pedometer.isSupported(),
      "granted": pedometer.isAuthorized(),
      "status": pedometer.authorizationStatusString(),
      "platform": "ios",
    ])
  }

  @objc(pedometerStart:resolver:rejecter:)
  func pedometerStart(_ sessionId: NSString?,
                      resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    let sid = sessionId as String?
    pedometer.start(sessionId: sid) { result in
      switch result {
      case .success(let snap): resolve(snap)
      case .failure(let e): reject("PEDOMETER_ERROR", e.localizedDescription, e)
      }
    }
  }

  @objc(pedometerStop:rejecter:)
  func pedometerStop(_ resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
    pedometer.stop { snap in resolve(snap) }
  }

  @objc(pedometerGetSnapshot:rejecter:)
  func pedometerGetSnapshot(_ resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(pedometer.snapshot())
  }

  @objc(pedometerQuery:toMs:resolver:rejecter:)
  func pedometerQuery(_ fromMs: NSNumber, toMs: NSNumber,
                      resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    pedometer.query(fromMs: fromMs.doubleValue, toMs: toMs.doubleValue) { result in
      switch result {
      case .success(let data): resolve(data)
      case .failure(let e): reject("PEDOMETER_QUERY", e.localizedDescription, e)
      }
    }
  }

  @objc(pedometerOnAppForeground)
  func pedometerOnAppForeground() {
    pedometer.onAppForeground()
  }

  @objc(pedometerGetDiagnostics:rejecter:)
  func pedometerGetDiagnostics(_ resolve: @escaping RCTPromiseResolveBlock,
                               rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(pedometer.getDiagnostics())
  }

  func pedometerEngine(_ engine: PedometerEngine, didUpdate payload: [String: Any]) {
    guard hasListeners else { return }
    sendEvent(withName: "pedometerUpdate", body: payload)
  }

  // MARK: - Background Engine API

  @objc(ready:resolver:rejecter:)
  func ready(_ config: NSDictionary,
             resolver resolve: @escaping RCTPromiseResolveBlock,
             rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.ready(config as? [String: Any] ?? [:]))
  }

  @objc(setConfig:resolver:rejecter:)
  func setConfig(_ config: NSDictionary,
                 resolver resolve: @escaping RCTPromiseResolveBlock,
                 rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.mergeConfig(config as? [String: Any] ?? [:])
    resolve(engine.getState())
  }

  @objc(getState:rejecter:)
  func getState(_ resolve: @escaping RCTPromiseResolveBlock,
                rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getState())
  }

  @objc(start:rejecter:)
  func start(_ resolve: @escaping RCTPromiseResolveBlock,
             rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.startEngine()
    resolve(engine.getState())
  }

  @objc(stop:rejecter:)
  func stop(_ resolve: @escaping RCTPromiseResolveBlock,
            rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.stopEngine()
    resolve(engine.getState())
  }

  @objc(changePace:resolver:rejecter:)
  func changePace(_ moving: Bool,
                  resolver resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.changePace(moving)
    resolve(nil)
  }

  @objc(startSchedule:rejecter:)
  func startSchedule(_ resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.startSchedule()
    resolve(nil)
  }

  @objc(stopSchedule:rejecter:)
  func stopSchedule(_ resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.stopSchedule()
    resolve(nil)
  }

  @objc(startGeofences:rejecter:)
  func startGeofences(_ resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.startGeofencesMode()
    resolve(nil)
  }

  @objc(sync:rejecter:)
  func sync(_ resolve: @escaping RCTPromiseResolveBlock,
            rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.httpSyncAsync { results in resolve(results) }
  }

  @objc(getLocations:rejecter:)
  func getLocations(_ resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getLocations())
  }

  @objc(destroyLocation:resolver:rejecter:)
  func destroyLocation(_ uuid: String,
                       resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.destroyLocation(uuid))
  }

  @objc(insertLocation:resolver:rejecter:)
  func insertLocation(_ params: NSDictionary,
                      resolver resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.insertLocation(params as? [String: Any] ?? [:]))
  }

  @objc(getLog:resolver:rejecter:)
  func getLog(_ query: NSDictionary?,
              resolver resolve: @escaping RCTPromiseResolveBlock,
              rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(engine.getNativeLog(query: query as? [String: Any] ?? [:]))
  }

  @objc(destroyLog:rejecter:)
  func destroyLog(_ resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.destroyNativeLog()
    resolve(nil)
  }

  @objc(log:message:resolver:rejecter:)
  func log(_ level: String, message: String,
           resolver resolve: @escaping RCTPromiseResolveBlock,
           rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.nativeLog(level: level, message: message)
    resolve(nil)
  }

  @objc(uploadLog:query:resolver:rejecter:)
  func uploadLog(_ url: String, query: NSDictionary?,
                 resolver resolve: @escaping RCTPromiseResolveBlock,
                 rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.uploadLog(url: url, query: query as? [String: Any] ?? [:]) { ok, msg in
      ok ? resolve(msg) : reject("UPLOAD_FAILED", msg, nil)
    }
  }

  @objc(requestTemporaryFullAccuracy:resolver:rejecter:)
  func requestTemporaryFullAccuracy(_ purpose: String,
                                    resolver resolve: @escaping RCTPromiseResolveBlock,
                                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.requestTemporaryFullAccuracy(purpose: purpose) { resolve($0) }
  }

  @objc(reset:rejecter:)
  func reset(_ resolve: @escaping RCTPromiseResolveBlock,
             rejecter reject: @escaping RCTPromiseRejectBlock) {
    engine.stopEngine()
    engine.destroyAllLocations()
    engine.destroyNativeLog()
    resolve(nil)
  }

  // MARK: - Live Activities

  @objc(setLiveActivityEnabled:)
  func setLiveActivityEnabled(_ enabled: Bool) {
    if #available(iOS 16.1, *) {
      LiveActivityManager.shared.setEnabled(enabled)
    }
  }

  @objc(getLiveActivityEnabled:rejecter:)
  func getLiveActivityEnabled(_ resolve: @escaping RCTPromiseResolveBlock,
                               rejecter reject: @escaping RCTPromiseRejectBlock) {
    if #available(iOS 16.1, *) {
      resolve(LiveActivityManager.shared.isUserEnabled)
    } else {
      resolve(false)
    }
  }

  @objc(startLiveActivity:activityType:resolver:rejecter:)
  func startLiveActivity(_ name: String, activityType: String,
                         resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 16.1, *) else { return resolve(nil) }
    Task { @MainActor in
      do {
        try await LiveActivityManager.shared.startActivity(
          workoutName: name,
          activityType: activityType
        )
        resolve(nil)
      } catch {
        reject("LIVE_ACTIVITY_ERROR", error.localizedDescription, error)
      }
    }
  }

  @objc(updateLiveActivity:duration:pace:speed:calories:gpsStatus:isPaused:)
  func updateLiveActivity(_ distance: NSNumber, duration: NSNumber, pace: String,
                          speed: NSNumber, calories: NSNumber,
                          gpsStatus: String, isPaused: Bool) {
    guard #available(iOS 16.1, *) else { return }
    Task { @MainActor in
      await LiveActivityManager.shared.updateActivity(
        distance: distance.doubleValue,
        duration: duration.doubleValue,
        pace: pace,
        speed: speed.doubleValue,
        calories: calories.intValue,
        heartRate: nil,
        gpsStatus: gpsStatus,
        isPaused: isPaused
      )
    }
  }

  @objc(endLiveActivity:duration:calories:resolver:rejecter:)
  func endLiveActivity(_ distance: NSNumber, duration: NSNumber, calories: NSNumber,
                       resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 16.1, *) else { return resolve(nil) }
    Task { @MainActor in
      try? await LiveActivityManager.shared.endActivity(
        finalDistance: distance.doubleValue,
        finalDuration: duration.doubleValue,
        finalCalories: calories.intValue,
        dismissImmediately: true
      )
      resolve(nil)
    }
  }

  @objc(dismissAllLiveActivities:rejecter:)
  func dismissAllLiveActivities(_ resolve: @escaping RCTPromiseResolveBlock,
                                rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 16.1, *) else { return resolve(nil) }
    Task { @MainActor in
      await LiveActivityManager.shared.dismissAllActivities(immediate: true)
      resolve(nil)
    }
  }
}
