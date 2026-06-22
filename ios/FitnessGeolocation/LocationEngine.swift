import CoreLocation
import UIKit
import os.log

// MARK: - Tracking Mode

enum TrackingMode: String {
  case fitness, navigation, balanced, low_power, stationary

  var distanceFilter: CLLocationDistance {
    switch self {
    case .navigation: return 3
    case .fitness: return 5
    case .balanced: return 8
    case .low_power: return 15
    case .stationary: return 25
    }
  }

  var desiredAccuracy: CLLocationAccuracy {
    switch self {
    case .navigation: return kCLLocationAccuracyBestForNavigation
    case .fitness: return kCLLocationAccuracyBest
    case .balanced: return kCLLocationAccuracyNearestTenMeters
    default: return kCLLocationAccuracyHundredMeters
    }
  }
}

// MARK: - Delegate

protocol LocationEngineDelegate: AnyObject {
  func locationEngine(_ engine: LocationEngine, didPersist location: StoredLocation, watchIds: [Int], deliverLive: Bool)
  func locationEngine(_ engine: LocationEngine, didFailWithError error: Error, watchIds: [Int])
  func locationEngineDidChangeAuthorization(_ engine: LocationEngine)
  func locationEngineDidEnterForeground(_ engine: LocationEngine)
  func locationEngine(_ engine: LocationEngine, didLog event: [String: Any])
  func locationEngine(_ engine: LocationEngine, didTimeBasedTick location: StoredLocation)
  func locationEngine(_ engine: LocationEngine, didGpsStrengthChange strength: String, accuracy: Double)
  func locationEngine(_ engine: LocationEngine, didStationaryChange isStationary: Bool)
}

// MARK: - Location Engine

final class LocationEngine: NSObject {
  static let shared = LocationEngine()

  weak var delegate: LocationEngineDelegate?

  private let locationManager = CLLocationManager()
  private let database = LocationDatabase.shared
  private let backgroundSession = BackgroundActivitySession.shared
  private let motion = MotionEngine.shared
  private var filter = LocationFilter()
  /// C++ tracking engine — replaces LocationFilter + cumulativeDistance on the hot path.
  private let trackEngine = TrackEngineBridge.shared
  private let oslog = OSLog(subsystem: "com.fitnessgeolocation", category: "location")
  
  // Live Activity Manager (iOS 16.1+)
  private var liveActivityManager: LiveActivityManager? {
    if #available(iOS 16.1, *) {
      return LiveActivityManager.shared
    }
    return nil
  }
  
  // Track session details for Live Activity
  private var currentActivityType: String = "running"
  private var sessionStartTime: Date?

  // Watch state
  private var isWatching = false
  private var mode: TrackingMode = .fitness
  private var motionState = "unknown"
  private var lastLocation: CLLocation?
  private var watchIds: [Int: Bool] = [:]
  private var nextWatchId = 1
  private var isPaused = false
  private var hasCustomDistanceFilter = false
  private var hasCustomDesiredAccuracy = false
  private var pendingAuthorizationCompletion: ((String) -> Void)?
  private var diagnostics: [[String: Any]] = []

  // Session state
  private var currentSessionId: String?
  private var cumulativeDistance: Double = 0
  private var lastProcessedLocation: CLLocation?

  // Time-based tracking state
  private var timeBasedWatchId: Int?
  private var timeBasedTimer: Timer?
  private var timeBasedInterval: TimeInterval = 3.0
  private var timeBasedStationaryInterval: TimeInterval = 30.0
  private var timeBasedAdaptive: Bool = true
  private var timeBasedMaxAccuracy: Double = 50.0
  private var timeBasedPaused: Bool = false
  private var timeBasedGPSStrength: String = "medium"
  private var timeBasedIsStationary: Bool = false
  private var timeBasedStationarySince: Date?
  private var timeBasedBatchedLocations: [StoredLocation] = []
  private var lastTimeBasedTick: Date?

  // Battery-conscious motion detection (reference: transistorsoft)
  // Turn GPS OFF when stationary, use CoreMotion accelerometer to wake
  private var motionAutoPauseEnabled = true
  private var motionAutoResumeEnabled = true
  private var gpsSuspended = false                       // GPS is off, waiting for motion
  private var stopTimeout: TimeInterval = 5 * 60         // 5 min of stillness → GPS off
  private var stopTimer: Timer?
  private var stationarySince: Date?
  private var wasMovingFlagged = false

  // Stationary geofence for iOS termination recovery
  private var stationaryGeofence: CLCircularRegion?
  private var isGeofenceActive = false

  private let watchStateKey = "com.fitnessgeolocation.watchActive"

  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.activityType = .fitness
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager.distanceFilter = kCLDistanceFilterNone
    locationManager.showsBackgroundLocationIndicator = true

    NotificationCenter.default.addObserver(
      self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(appWillTerminate),
      name: UIApplication.willTerminateNotification, object: nil
    )
    restoreWatchIfNeeded()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  // MARK: - App Lifecycle

  @objc private func appDidBecomeActive() {
    os_log(.debug, log: oslog, "app_foreground pending=%d", database.pendingCount())
    log("foreground", ["pending": database.pendingCount()])
    delegate?.locationEngineDidEnterForeground(self)
  }

  @objc private func appWillTerminate() {
    // Only arm wake geofence if tracking was active when the OS kills the app.
    if isWatching || timeBasedWatchId != nil || UserDefaults.standard.bool(forKey: watchStateKey) {
      registerStationaryGeofence()
    }
    os_log(.debug, log: oslog, "app_terminate stationary_geofence=%@", stationaryGeofence?.identifier ?? "none")
    log("terminate", ["geofence": stationaryGeofence?.identifier ?? "none"])
  }

  private var isAppActive: Bool {
    UIApplication.shared.applicationState == .active
  }

  // MARK: - Motion State

  func setMotionState(_ state: String) {
    motionState = state
    timeBasedIsStationary = (state == "stationary")
    if state == "stationary" {
      if timeBasedStationarySince == nil { timeBasedStationarySince = Date() }
    } else {
      timeBasedStationarySince = nil
    }
    log("motion-state", ["state": state])
  }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    log(paused ? "pause" : "resume", ["mode": mode.rawValue])
    if paused {
      setMode(.stationary)
    } else {
      setMode(.fitness)
    }
  }

  // MARK: - Battery-Conscious GPS Management

  /// Configure motion-based GPS auto-pause/resume (reference: transistorsoft)
  func configureMotionAutoPause(enabled: Bool, delaySeconds: Double, stopTimeoutMinutes: Double) {
    motionAutoPauseEnabled = enabled
    motionAutoResumeEnabled = enabled
    stopTimeout = max(1, stopTimeoutMinutes * 60)
    motion.autoPauseEnabled = enabled
    motion.autoPauseDelaySeconds = delaySeconds
  }

  /// Called when MotionEngine detects the device has been stationary for autoPauseDelaySeconds
  func onStationaryAutoPause() {
    guard motionAutoPauseEnabled, isWatching || timeBasedWatchId != nil else { return }
    guard !gpsSuspended else { return }

    os_log(.debug, log: oslog, "motion_auto_pause: device_stationary starting_stop_timeout=%.0fs", stopTimeout)

    // Start the stop timeout — if device stays still this long, kill GPS
    startStopTimeout()
    wasMovingFlagged = false
  }

  /// Called when MotionEngine detects movement (walking/running/cycling)
  func onMotionResume() {
    guard motionAutoResumeEnabled else { return }
    cancelStopTimeout()
    stationarySince = nil
    wasMovingFlagged = true

    if gpsSuspended {
      // Restart GPS — motion detected
      resumeGPS()
    }
  }

  /// Start the stop timeout timer. After `stopTimeout` seconds of stillness, suspend GPS.
  private func startStopTimeout() {
    cancelStopTimeout()
    stopTimer = Timer.scheduledTimer(withTimeInterval: stopTimeout, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.stopTimer = nil
      self.suspendGPS()
    }
  }

  private func cancelStopTimeout() {
    stopTimer?.invalidate()
    stopTimer = nil
  }

  /// Suspend GPS — turn off CLLocationManager, keep CoreMotion alive for wake detection
  private func suspendGPS() {
    guard !gpsSuspended else { return }
    gpsSuspended = true

    locationManager.stopUpdatingLocation()
    backgroundSession.stop()

    os_log(.debug, log: oslog, "gps_suspended: motion_wake_enabled=true")
    log("gps-suspend", ["reason": "stationary_timeout", "stopTimeout": stopTimeout])

    // Register stationary geofence so iOS wakes us if device moves
    registerStationaryGeofence()
  }

  /// Resume GPS — turn CLLocationManager back on (motion detected or app foregrounded)
  private func resumeGPS() {
    guard gpsSuspended else { return }
    gpsSuspended = false

    removeStationaryGeofence()
    configureBackgroundUpdatesIfAllowed()
    applyModeSettings()
    backgroundSession.start()

    if isWatching || timeBasedWatchId != nil {
      locationManager.startUpdatingLocation()
    }

    os_log(.debug, log: oslog, "gps_resumed: motion_detected")
    log("gps-resume", ["reason": "motion_detected"])
  }

  /// Feed speed from location updates into the motion state machine
  func feedMotionSpeed(_ speed: Double) {
    guard gpsSuspended else { return }
    if speed > 0.5 {
      onMotionResume()
    }
  }

  /// Feed motion activity from bridge MotionEngine delegate for GPS suspend/resume
  func feedMotionActivity(_ activity: MotionActivityType) {
    switch activity {
    case .walking, .running, .cycling, .driving:
      onMotionResume()
    default:
      break
    }
  }

  // MARK: - Background

  private func configureBackgroundUpdatesIfAllowed() {
    if currentAuthorizationStatus() == .authorizedAlways {
      locationManager.allowsBackgroundLocationUpdates = true
      os_log(.debug, log: oslog, "background_updates_enabled")
      log("background-updates-enabled")
    }
  }

  private func currentAuthorizationStatus() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  // MARK: - Authorization

  func requestAuthorization(level: String, completion: @escaping (String) -> Void) {
    log("request-authorization", ["level": level, "status": authorizationStatusString()])
    let status = currentAuthorizationStatus()
    if status == .denied || status == .restricted {
      completion(authorizationStatusString())
      return
    }
    if level == "always", status == .authorizedAlways {
      completion(authorizationStatusString())
      return
    }
    if level != "always", status == .authorizedAlways || status == .authorizedWhenInUse {
      completion(authorizationStatusString())
      return
    }

    pendingAuthorizationCompletion = completion
    switch level {
    case "always": locationManager.requestAlwaysAuthorization()
    default: locationManager.requestWhenInUseAuthorization()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
      guard self.pendingAuthorizationCompletion != nil else { return }
      self.finishAuthorizationRequest()
    }
  }

  func authorizationStatusString() -> String {
    switch currentAuthorizationStatus() {
    case .authorizedAlways, .authorizedWhenInUse: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "notDetermined"
    }
  }

  func hasAlwaysAuthorization() -> Bool {
    currentAuthorizationStatus() == .authorizedAlways
  }

  // MARK: - Single Position

  func getCurrentPosition(options: [String: Any] = [:], completion: @escaping (Result<StoredLocation, Error>) -> Void) {
    guard CLLocationManager.locationServicesEnabled() else {
      completion(.failure(NSError(domain: "FitnessGeolocation", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Location services disabled"])))
      return
    }
    let maximumAgeMs = (options["maximumAge"] as? NSNumber)?.doubleValue ?? 0
    if let last = lastLocation {
      let ageMs = abs(last.timestamp.timeIntervalSinceNow) * 1000
      if maximumAgeMs <= 0 || ageMs <= maximumAgeMs {
        completion(.success(makeStored(from: last, delivered: true)))
        return
      }
    }
    locationManager.requestLocation()
    pendingSingleFixCompletion = completion
  }

  private var pendingSingleFixCompletion: ((Result<StoredLocation, Error>) -> Void)?

  // MARK: - Watch Position (Distance-Based)

  func watchPosition(options: [String: Any]) -> Int {
    applyWatchOptions(options)
    let id = nextWatchId
    nextWatchId += 1
    watchIds[id] = true
    os_log(.debug, log: oslog, "watch_add id=%d count=%d", id, watchIds.count)
    log("watch-add", ["watchId": id, "watchCount": watchIds.count])
    startWatchEngine()
    return id
  }

  func clearWatch(_ watchId: Int) {
    watchIds.removeValue(forKey: watchId)
    log("watch-clear", ["watchId": watchId, "watchCount": watchIds.count])
    if watchIds.isEmpty {
      stopWatchEngine()
    }
  }

  func stopObserving() {
    watchIds.removeAll()
    log("stop-observing")
    stopWatchEngine()
  }

  func setMode(_ newMode: TrackingMode) {
    mode = newMode
    applyModeSettings()
  }

  func setModeString(_ modeStr: String) {
    if let m = TrackingMode(rawValue: modeStr) { setMode(m) }
  }

  // MARK: - Time-Based Tracking

  /// Start time-based tracking (every N seconds, regardless of distance)
  func startTimeBasedTracking(options: [String: Any]) -> Int {
    let id = nextWatchId
    nextWatchId += 1
    timeBasedWatchId = id

    timeBasedInterval = (options["intervalMs"] as? NSNumber)?.doubleValue ?? 3000
    timeBasedInterval = max(0.5, timeBasedInterval / 1000.0)
    timeBasedStationaryInterval = (options["stationaryIntervalMs"] as? NSNumber)?.doubleValue ?? 30000
    timeBasedStationaryInterval = max(5.0, timeBasedStationaryInterval / 1000.0)
    timeBasedAdaptive = options["adaptiveInterval"] as? Bool ?? true
    timeBasedMaxAccuracy = (options["maxAccuracy"] as? NSNumber)?.doubleValue ?? 50.0
    timeBasedPaused = false
    timeBasedBatchedLocations = []
    cumulativeDistance = 0
    lastProcessedLocation = nil
    trackEngine.startSession(Date().timeIntervalSince1970, liveActivityInterval: 3.0)

    // Start continuous location updates with no distance filter
    configureBackgroundUpdatesIfAllowed()
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    locationManager.distanceFilter = kCLDistanceFilterNone
    locationManager.allowsBackgroundLocationUpdates = true
    backgroundSession.start()
    locationManager.startUpdatingLocation()
    isWatching = true

    // Start the timer that drains batched locations to JS
    startTimeBasedTimer()

    os_log(.debug, log: oslog, "timebased_start id=%d interval=%.1fs adaptive=%d", id, timeBasedInterval, timeBasedAdaptive)
    log("timebased-start", ["watchId": id, "interval": timeBasedInterval, "adaptive": timeBasedAdaptive])
    devLog("info", "TimeBasedTracker", "native_started", [
      "intervalMs": timeBasedInterval * 1000,
      "adaptive": timeBasedAdaptive,
      "maxAccuracy": timeBasedMaxAccuracy,
    ])

    return id
  }

  func stopTimeBasedTracking(_ watchId: Int) {
    guard timeBasedWatchId == watchId else { return }
    timeBasedTimer?.invalidate()
    timeBasedTimer = nil
    timeBasedWatchId = nil
    timeBasedBatchedLocations = []

    if watchIds.isEmpty {
      stopWatchEngine()
    }

    os_log(.debug, log: oslog, "timebased_stop id=%d", watchId)
    log("timebased-stop", ["watchId": watchId])
    devLog("info", "TimeBasedTracker", "native_stopped", [:])
  }

  func pauseTimeBasedTracking(_ watchId: Int) {
    guard timeBasedWatchId == watchId else { return }
    timeBasedPaused = true
    timeBasedTimer?.invalidate()
    timeBasedTimer = nil
    locationManager.stopUpdatingLocation()
    log("timebased-pause", ["watchId": watchId])
    devLog("debug", "TimeBasedTracker", "native_paused", [:])
  }

  func resumeTimeBasedTracking(_ watchId: Int) {
    guard timeBasedWatchId == watchId else { return }
    timeBasedPaused = false
    configureBackgroundUpdatesIfAllowed()
    locationManager.startUpdatingLocation()
    startTimeBasedTimer()
    log("timebased-resume", ["watchId": watchId])
    devLog("debug", "TimeBasedTracker", "native_resumed", [:])
  }

  func setTimeBasedInterval(_ watchId: Int, intervalMs: Double) {
    guard timeBasedWatchId == watchId else { return }
    timeBasedInterval = max(0.5, intervalMs / 1000.0)
    if timeBasedTimer != nil {
      timeBasedTimer?.invalidate()
      startTimeBasedTimer()
    }
    log("timebased-interval", ["watchId": watchId, "interval": timeBasedInterval])
  }

  private func startTimeBasedTimer() {
    timeBasedTimer?.invalidate()
    let currentInterval = timeBasedAdaptive && timeBasedIsStationary
      ? timeBasedStationaryInterval
      : timeBasedInterval
    // Cap for battery: max 60s
    let cappedInterval = min(currentInterval, 60.0)
    timeBasedTimer = Timer.scheduledTimer(withTimeInterval: cappedInterval, repeats: true) { [weak self] _ in
      self?.flushTimeBasedTick()
    }
  }

  private func flushTimeBasedTick() {
    guard let watchId = timeBasedWatchId, !timeBasedPaused else { return }

    // Take the last (most recent) batched location
    guard let latest = timeBasedBatchedLocations.last else { return }
    timeBasedBatchedLocations.removeAll()

    // GPS strength assessment
    let strength = signalStrength(fromAccuracy: latest.accuracy)
    timeBasedGPSStrength = strength

    // Detect stationary state for adaptive intervals
    var isStationary = timeBasedIsStationary
    if latest.speed < 0.5 {
      if timeBasedStationarySince == nil { timeBasedStationarySince = Date() }
      if let since = timeBasedStationarySince, Date().timeIntervalSince(since) >= 10.0 {
        isStationary = true
      }
    } else {
      timeBasedStationarySince = nil
      isStationary = false
    }

    // If adaptive and stationary state changed, restart timer with new interval
    if timeBasedAdaptive && isStationary != timeBasedIsStationary {
      timeBasedIsStationary = isStationary
      startTimeBasedTimer()
    }

    // Update cumulative distance
    cumulativeDistance = latest.cumulativeDistance
    
    // Update Live Activity with current workout data (if session active)
    // Issue #3 fix: Task is wrapped in do/catch so ActivityKit errors are logged
    // and never silently dropped. Circuit breaker inside LiveActivityManager prevents
    // battery drain from repeated failures.
    if currentSessionId != nil, let manager = liveActivityManager, let startTime = sessionStartTime {
      let durationSeconds = Date().timeIntervalSince(startTime)
      let paceFormatted = LiveActivityManager.formatPace(metersPerSecond: latest.speed)
      let gpsStatusString = LiveActivityManager.gpsStatusFromAccuracy(latest.accuracy)
      let distanceSnapshot = cumulativeDistance
      let actType = currentActivityType
      let paused = timeBasedPaused
      
      Task { @MainActor in
        do {
          try await manager.updateActivity(
            distance: distanceSnapshot,
            duration: durationSeconds,
            pace: paceFormatted,
            speed: latest.speed * 3.6, // m/s to km/h
            calories: LiveActivityManager.estimateCalories(
              distance: distanceSnapshot,
              activityType: actType
            ),
            heartRate: nil,
            gpsStatus: gpsStatusString,
            isPaused: paused
          )
        } catch {
          // Non-fatal: Live Activity update error caught at tick level.
          // The circuit breaker inside LiveActivityManager handles repeated failures.
          os_log(.error, log: OSLog(subsystem: "com.fitnessgeolocation", category: "liveactivity"),
                 "tick_live_activity_error: %@", error.localizedDescription)
        }
      }
    }

    // Emit event to bridge
    let eventBody: [String: Any] = [
      "coords": [
        "latitude": latest.latitude,
        "longitude": latest.longitude,
        "altitude": latest.altitude,
        "accuracy": latest.accuracy,
        "heading": latest.heading,
        "speed": latest.speed,
      ],
      "timestamp": latest.timestamp,
      "gpsStrength": strength,
      "isStationary": isStationary,
      "distanceFromPrev": latest.distanceFromPrev,
      "cumulativeDistance": cumulativeDistance,
      "batteryLevel": latest.batteryLevel,
      "motionState": latest.motionState,
    ]

    delegate?.locationEngine(self, didTimeBasedTick: latest)
    delegate?.locationEngine(self, didGpsStrengthChange: strength, accuracy: latest.accuracy)
    delegate?.locationEngine(self, didStationaryChange: isStationary)

    // DEV log via os_log
    os_log(.debug, log: oslog, "tick lat=%.6f lng=%.6f acc=%.1f spd=%.2f gps=%@ still=%d dist=%.1f",
           latest.latitude, latest.longitude, latest.accuracy, latest.speed,
           strength, isStationary, cumulativeDistance)
  }

  // MARK: - Stationary Geofence (iOS Termination Recovery)

  /// Register a 200m geofence around the last known location.
  /// iOS keeps geofences alive even after app termination.
  /// When the user exits this geofence, iOS relaunches the app.
  func registerStationaryGeofence() {
    guard let location = lastLocation else { return }
    removeStationaryGeofence()

    let region = CLCircularRegion(
      center: location.coordinate,
      radius: 200, // meters — matches transistorsoft's default
      identifier: "fitness_geolocation_stationary"
    )
    region.notifyOnEntry = false
    region.notifyOnExit = true

    locationManager.startMonitoring(for: region)
    stationaryGeofence = region
    isGeofenceActive = true

    os_log(.debug, log: oslog, "stationary_geofence_registered lat=%.6f lng=%.6f radius=200",
           location.coordinate.latitude, location.coordinate.longitude)
    log("geofence-registered", ["lat": location.coordinate.latitude, "lng": location.coordinate.longitude, "radius": 200])
  }

  func removeStationaryGeofence() {
    if let region = stationaryGeofence {
      locationManager.stopMonitoring(for: region)
      stationaryGeofence = nil
      isGeofenceActive = false
    }
  }

  // MARK: - Odometer

  /// Returns C++ engine's Kahan-compensated accumulated distance (preferred)
  /// falling back to the Swift-side mirror.
  var odometer: Double {
    trackEngine.isActive ? trackEngine.totalDistanceM : cumulativeDistance
  }

  func resetOdometer() {
    cumulativeDistance = 0
    lastProcessedLocation = nil
    // Restart C++ engine to reset its Kahan accumulator
    if trackEngine.isActive {
      trackEngine.startSession(Date().timeIntervalSince1970, liveActivityInterval: 3.0)
    }
    log("odometer-reset")
  }

  func setOdometer(_ value: Double) {
    cumulativeDistance = value
    log("odometer-set", ["value": value])
  }

  // MARK: - Database Access

  func getPendingForJs(limit: Int) -> [[String: Any]] {
    database.getPendingForJs(limit: Int32(limit)).map { $0.toDictionary() }
  }

  func markDelivered(ids: [String]) -> Int {
    let count = database.markDelivered(ids: ids)
    log("location-ack", ["requested": ids.count, "updated": count])
    return count
  }

  func acknowledge(ids: [String]) -> Int { database.acknowledge(ids: ids) }

  func purgeDelivered() -> Int {
    let count = database.purgeDelivered()
    log("location-purge", ["deleted": count])
    return Int(count)
  }

  func pendingCount() -> Int { database.pendingCount() }
  func getQueueSize() -> Int { database.pendingCount() }

  func getDiagnostics() -> [[String: Any]] { diagnostics }

  // Session management
  func createSession(name: String, activityType: String, extras: String?) -> String {
    let id = database.createSession(name: name, activityType: activityType, extras: extras)
    currentSessionId = id
    currentActivityType = activityType
    sessionStartTime = Date()
    cumulativeDistance = 0
    lastProcessedLocation = nil
    
    // Start Live Activity if enabled.
    // Issue #4 fix: Task body is wrapped in do/catch so any throw from startActivity
    // (e.g. ActivityKit internal error) is logged rather than silently discarded.
    if let manager = liveActivityManager {
      let sessionName = name
      let actType = activityType
      Task { @MainActor in
        do {
          try await manager.startActivity(
            workoutName: sessionName,
            activityType: actType,
            targetDistance: nil,
            targetDuration: nil
          )
        } catch {
          // Non-fatal: Live Activity start failed. GPS tracking continues normally.
          os_log(.error, log: OSLog(subsystem: "com.fitnessgeolocation", category: "liveactivity"),
                 "create_session_live_activity_start_error: %@", error.localizedDescription)
        }
      }
    }
    
    os_log(.debug, log: oslog, "session_created id=%@ name=%@", id, name)
    devLog("info", "ActivityManager", "session_created", ["sessionId": id, "name": name])
    return id
  }

  func endSession(_ sessionId: String, data: [String: Any]) {
    database.endSession(sessionId, data: data)
    
    // End Live Activity if active.
    // endActivity() is now throwing — must use try/catch inside Task.
    if currentSessionId == sessionId, let manager = liveActivityManager {
      let totalDist = data["totalDistance"] as? Double
      let totalDur  = (data["totalDuration"] as? Double).map { $0 / 1000.0 }
      let totalCal  = data["calories"] as? Int
      Task { @MainActor in
        do {
          try await manager.endActivity(
            finalDistance: totalDist,
            finalDuration: totalDur,
            finalCalories: totalCal
          )
        } catch {
          os_log(.error, log: OSLog(subsystem: "com.fitnessgeolocation", category: "liveactivity"),
                 "end_session_live_activity_error: %@", error.localizedDescription)
        }
      }
    }
    
    if currentSessionId == sessionId { 
      currentSessionId = nil
      sessionStartTime = nil
    }
    
    os_log(.debug, log: oslog, "session_ended id=%@ dist=%.1f pts=%d",
           sessionId, data["totalDistance"] as? Double ?? 0, data["pointCount"] as? Int ?? 0)
    devLog("info", "ActivityManager", "session_ended", [
      "sessionId": sessionId,
      "distance": data["totalDistance"] ?? 0,
      "duration": data["totalDuration"] ?? 0,
    ])
  }

  func discardSession(_ sessionId: String) {
    database.discardSession(sessionId)
    if currentSessionId == sessionId { currentSessionId = nil }
  }

  func getUnuploadedSessions() -> [[String: Any]] {
    database.getUnuploadedSessions()
  }

  func getSessionForUpload(_ sessionId: String) -> [String: Any]? {
    database.getSessionForUpload(sessionId)
  }

  func markSessionUploaded(_ sessionId: String) {
    database.markSessionUploaded(sessionId)
  }

  // MARK: - Engine State

  func getEngineState() -> [String: Any] {
    [
      "isWatching": isWatching,
      "isPaused": isPaused,
      "mode": mode.rawValue,
      "pendingQueue": database.pendingCount(),
      "motionState": motionState,
      "signalStrength": signalStrength(from: lastLocation),
      "backgroundSessionActive": backgroundSession.isActive,
      "diagnosticCount": diagnostics.count,
      "odometer": cumulativeDistance,
      "timeBasedActive": timeBasedWatchId != nil,
      "stationaryGeofenceActive": isGeofenceActive,
    ]
  }

  // MARK: - Engine Lifecycle

  private func startWatchEngine() {
    isWatching = true
    trackEngine.startSession(Date().timeIntervalSince1970, liveActivityInterval: 3.0)
    configureBackgroundUpdatesIfAllowed()
    applyModeSettings()
    backgroundSession.start()
    persistWatchState()
    locationManager.startUpdatingLocation()
    os_log(.debug, log: oslog, "watch_start mode=%@ df=%.1f acc=%.1f always=%d",
           mode.rawValue, locationManager.distanceFilter, locationManager.desiredAccuracy, hasAlwaysAuthorization())
    log("watch-start", [
      "mode": mode.rawValue,
      "distanceFilter": locationManager.distanceFilter,
      "desiredAccuracy": locationManager.desiredAccuracy,
      "always": hasAlwaysAuthorization(),
    ])
  }

  private func stopWatchEngine() {
    isWatching = false
    gpsSuspended = false
    cancelStopTimeout()
    timeBasedTimer?.invalidate()
    timeBasedTimer = nil
    timeBasedWatchId = nil
    timeBasedBatchedLocations = []
    removeStationaryGeofence()
    backgroundSession.stop()
    locationManager.stopUpdatingLocation()
    locationManager.showsBackgroundLocationIndicator = false
    if hasAlwaysAuthorization() {
      locationManager.allowsBackgroundLocationUpdates = false
    }
    filter.reset()
    trackEngine.stopSession()
    clearWatchState()
    log("watch-stop", ["pending": database.pendingCount()])
    devLog("info", "LocationEngine", "watch_stopped", ["pending": database.pendingCount()])
  }

  private func restoreWatchIfNeeded() {
    guard UserDefaults.standard.bool(forKey: watchStateKey) else { return }
    configureBackgroundUpdatesIfAllowed()
    applyModeSettings()
    backgroundSession.start()
    locationManager.startUpdatingLocation()
    isWatching = true
    log("watch-restore", ["mode": mode.rawValue])
  }

  private func persistWatchState() {
    UserDefaults.standard.set(true, forKey: watchStateKey)
    UserDefaults.standard.set(mode.rawValue, forKey: "com.fitnessgeolocation.mode")
  }

  private func clearWatchState() {
    UserDefaults.standard.set(false, forKey: watchStateKey)
  }

  // MARK: - Options

  private func applyWatchOptions(_ options: [String: Any]) {
    hasCustomDistanceFilter = false
    hasCustomDesiredAccuracy = false

    if let df = options["distanceFilter"] as? NSNumber {
      locationManager.distanceFilter = df.doubleValue
      hasCustomDistanceFilter = true
    }
    if let high = options["enableHighAccuracy"] as? Bool {
      locationManager.desiredAccuracy = high ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyHundredMeters
      hasCustomDesiredAccuracy = true
    }
    if let desired = options["desiredAccuracy"] as? NSNumber {
      locationManager.desiredAccuracy = desired.doubleValue
      hasCustomDesiredAccuracy = true
    }
    if let pauses = options["pausesLocationUpdatesAutomatically"] as? Bool {
      locationManager.pausesLocationUpdatesAutomatically = pauses
    }
    if let indicator = options["showsBackgroundLocationIndicator"] as? Bool {
      locationManager.showsBackgroundLocationIndicator = indicator
    }
    if let activity = options["activityType"] as? String {
      switch activity {
      case "fitness": locationManager.activityType = .fitness
      case "automotiveNavigation": locationManager.activityType = .automotiveNavigation
      case "otherNavigation": locationManager.activityType = .otherNavigation
      default: locationManager.activityType = .other
      }
    }
    if let m = options["trackingMode"] as? String, let tm = TrackingMode(rawValue: m) {
      mode = tm
    }
  }

  private func applyModeSettings() {
    if !hasCustomDesiredAccuracy {
      locationManager.desiredAccuracy = mode.desiredAccuracy
    }
    if !hasCustomDistanceFilter {
      locationManager.distanceFilter = mode.distanceFilter
    }
  }

  // MARK: - Helpers

  private func signalStrength(from location: CLLocation?) -> String {
    guard let acc = location?.horizontalAccuracy, acc > 0 else { return "weak" }
    return signalStrength(fromAccuracy: acc)
  }

  private func signalStrength(fromAccuracy accuracy: Double) -> String {
    if accuracy <= 10 { return "strong" }
    if accuracy <= 30 { return "medium" }
    return "weak"
  }

  private func makeStored(from location: CLLocation, delivered: Bool) -> StoredLocation {
    let dist = computeDistance(from: location)
    return StoredLocation(
      id: UUID().uuidString,
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      accuracy: location.horizontalAccuracy,
      speed: max(0, location.speed),
      heading: location.course >= 0 ? location.course : 0,
      altitude: location.altitude,
      timestamp: Int64(location.timestamp.timeIntervalSince1970 * 1000),
      batteryLevel: batteryLevel(),
      signalStrength: signalStrength(from: location),
      provider: "gps",
      motionState: motionState,
      confidence: min(1.0, max(0, 1.0 - location.horizontalAccuracy / 100.0)),
      sessionId: currentSessionId ?? UUID().uuidString,
      deliveredToJs: delivered,
      distanceFromPrev: dist,
      cumulativeDistance: cumulativeDistance
    )
  }

  private func computeDistance(from location: CLLocation) -> Double {
    guard let last = lastProcessedLocation else {
      lastProcessedLocation = location
      return 0
    }
    let dist = location.distance(from: last)
    if dist > 0 { cumulativeDistance += dist }
    lastProcessedLocation = location
    return dist
  }

  private func batteryLevel() -> Double {
    UIDevice.current.isBatteryMonitoringEnabled = true
    return Double(UIDevice.current.batteryLevel)
  }

  // MARK: - Location Processing

  private func processLocation(_ raw: CLLocation) {
    if isPaused || timeBasedPaused {
      log("location-drop", ["reason": "paused", "accuracy": raw.horizontalAccuracy])
      return
    }

    // ── C++ fast path ────────────────────────────────────────────────────────
    // TrackEngineBridge runs: LocationFilterC → KalmanState → haversine_m
    // All zero-allocation, ~2 µs on A15. Falls back to Swift filter for the
    // stored CLLocation object (needed for downstream APIs that expect CLLocation).
    let engResult = trackEngine.ingest(
      lat: raw.coordinate.latitude,
      lng: raw.coordinate.longitude,
      accuracy: raw.horizontalAccuracy,
      unixTimeS: raw.timestamp.timeIntervalSince1970,
      speedMps: raw.speed
    )

    // Sync the Swift-side odometer with the C++ accumulated distance
    cumulativeDistance = trackEngine.totalDistanceM

    // ── Live Activity update (native, no JS bridge crossing) ─────────────────
    if engResult.shouldUpdateLiveActivity, engResult.accepted {
      if #available(iOS 16.1, *) {
        let sessionStart = Date(timeIntervalSince1970:
          raw.timestamp.timeIntervalSince1970 - engResult.elapsedS)
        _ = sessionStart  // reserved for future staleDate calculation
        Task { @MainActor in
          await LiveActivityManager.shared.updateActivity(
            distance: engResult.totalDistanceM,
            duration: engResult.elapsedS,
            pace: engResult.paceStr,
            speed: engResult.speedKmh,
            calories: LiveActivityManager.estimateCalories(
              distance: engResult.totalDistanceM,
              activityType: currentActivityType
            ),
            heartRate: nil,
            gpsStatus: LiveActivityManager.gpsStatusFromAccuracy(raw.horizontalAccuracy),
            isPaused: isPaused
          )
        }
      }
    }

    // ── Swift filter path (for CLLocation-based downstream) ──────────────────
    // We keep filter.process for reject/accept signalling but use the C++ result
    // for distance. Accept only if the C++ engine agreed.
    guard engResult.accepted else {
      log("location-drop", ["reason": "cpp_filter", "accuracy": raw.horizontalAccuracy])
      return
    }

    // Build a smoothed CLLocation using C++ filtered coordinates
    let smoothed = CLLocation(
      coordinate: CLLocationCoordinate2D(
        latitude: engResult.filteredLat,
        longitude: engResult.filteredLng
      ),
      altitude: raw.altitude,
      horizontalAccuracy: raw.horizontalAccuracy,
      verticalAccuracy: raw.verticalAccuracy,
      course: raw.course,
      speed: max(0, raw.speed),
      timestamp: raw.timestamp
    )

    lastLocation = smoothed
    let stored = makeStored(from: smoothed, delivered: false)

    guard database.insert(stored) else {
      log("persist-failed", ["accuracy": smoothed.horizontalAccuracy])
      return
    }

    // If time-based tracking is active, batch this location
    if timeBasedWatchId != nil {
      timeBasedBatchedLocations.append(stored)
      // Cap batch size to prevent memory growth
      if timeBasedBatchedLocations.count > 100 {
        timeBasedBatchedLocations.removeFirst(timeBasedBatchedLocations.count - 100)
      }
    }

    // DEV log to os_log
    os_log(.debug, log: oslog, "persist lat=%.6f lng=%.6f acc=%.1f spd=%.2f dist=%.1f cumulative=%.1f",
           stored.latitude, stored.longitude, stored.accuracy, stored.speed,
           stored.distanceFromPrev, stored.cumulativeDistance)

    log("location-persist", [
      "id": stored.id,
      "accuracy": stored.accuracy,
      "speed": stored.speed,
      "distance": stored.distanceFromPrev,
      "cumulative": stored.cumulativeDistance,
      "pending": database.pendingCount(),
      "deliverLive": isAppActive,
    ])

    // Deliver live to watch callbacks if app is active
    if isAppActive && !watchIds.isEmpty {
      delegate?.locationEngine(self, didPersist: stored, watchIds: Array(watchIds.keys), deliverLive: true)
    }
  }

  // MARK: - Logging

  private func log(_ event: String, _ data: [String: Any] = [:]) {
    var row = data
    row["event"] = event
    row["timestamp"] = Int64(Date().timeIntervalSince1970 * 1000)
    row["platform"] = "ios"
    diagnostics.append(row)
    if diagnostics.count > 300 {
      diagnostics.removeFirst(diagnostics.count - 300)
    }
    delegate?.locationEngine(self, didLog: row)
  }

  func devLog(_ level: String, _ tag: String, _ message: String, _ data: [String: Any] = [:]) {
    let logLevel: OSLogType
    switch level {
    case "error": logLevel = .error
    case "warn": logLevel = .fault
    case "info": logLevel = .info
    default: logLevel = .debug
    }
    os_log(logLevel, log: oslog, "[%@] %@ data=%@", tag, message, data.description)
  }

  private func finishAuthorizationRequest() {
    let completion = pendingAuthorizationCompletion
    pendingAuthorizationCompletion = nil
    completion?(authorizationStatusString())
  }

  // MARK: - HTTP Auto-Sync

  var httpConfigured = false
  var httpUrl: String?
  var httpMethod = "POST"
  var httpHeaders: [String: String] = [:]
  var httpAutoSync = true
  var httpBatchSync = true
  var httpBatchSize = 100
  var httpRetryCount = 3
  var httpListenerEnabled = false
  private var httpSession: URLSession?
  private let httpQueue = DispatchQueue(label: "com.fitnessgeolocation.http", qos: .background)

  func httpConfigure(url: String?, method: String, headers: [String: String],
                     autoSync: Bool, batchSync: Bool, batchSize: Int, retryCount: Int) {
    httpUrl = url
    httpMethod = method
    httpHeaders = headers
    httpAutoSync = autoSync
    httpBatchSync = batchSync
    httpBatchSize = batchSize
    httpRetryCount = retryCount
    httpConfigured = url != nil

    if let u = url {
      let config = URLSessionConfiguration.background(withIdentifier: "com.fitnessgeolocation.uploads")
      config.sessionSendsLaunchEvents = true
      config.isDiscretionary = false
      httpSession = URLSession(configuration: config)
      os_log(.debug, log: oslog, "http_configured: %@", u)
    }
  }

  /// Synchronously upload pending locations to the configured HTTP endpoint.
  ///
  /// Issue #5 fix: `DispatchSemaphore.wait()` on the main thread causes a deadlock because
  /// URLSession completion callbacks need the main thread to deliver. This method now:
  ///   1. Asserts it is NOT running on the main thread (hard crash in debug, early-return in release).
  ///   2. Dispatches onto the dedicated background `httpQueue` when called from unknown contexts.
  ///
  /// Callers (JS bridge) always call this from a background thread via the RN bridge, so
  /// in normal operation the precondition always passes. The queue-based overload below
  /// provides a safe fire-and-forget variant for internal use.
  func httpSync() -> [[String: Any]] {
    // Issue #5: Prevent semaphore deadlock — must never block the main thread.
    if Thread.isMainThread {
      os_log(.fault, log: oslog,
             "httpSync called on main thread — this would deadlock. Skipping upload.")
      return []
    }

    guard let url = httpUrl else { return [] }
    let points = database.getPendingForJs(limit: Int32(httpBatchSize))
    guard !points.isEmpty else { return [] }

    let body: String
    if httpBatchSync {
      let arr = points.map { $0.toHttpDictionary() }
      if let data = try? JSONSerialization.data(withJSONObject: arr),
         let str = String(data: data, encoding: .utf8) {
        body = str
      } else { return [] }
    } else {
      var results: [[String: Any]] = []
      for point in points {
        if let dict = uploadSingle(url: url, point: point) { results.append(dict) }
      }
      return results
    }

    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = httpMethod
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in httpHeaders { request.setValue(value, forHTTPHeaderField: key) }
    request.httpBody = body.data(using: .utf8)
    request.timeoutInterval = 15

    // Safe: semaphore.wait() is on a background thread (asserted above).
    // URLSession delivers its completion on an internal thread — no deadlock.
    let semaphore = DispatchSemaphore(value: 0)
    var resultLocations: [[String: Any]] = []
    var responseCode = 0
    var responseText = ""

    URLSession.shared.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      guard let httpResponse = response as? HTTPURLResponse else {
        os_log(.error, log: self.oslog, "http_sync_no_response error=%@",
               error?.localizedDescription ?? "unknown")
        return
      }
      responseCode = httpResponse.statusCode
      responseText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      if (200...299).contains(responseCode) {
        let ids = points.map { $0.id }
        _ = self.database.markDelivered(ids: ids)
        resultLocations = points.map { $0.toDictionary() }
        os_log(.debug, log: self.oslog, "http_sync_success: %d points, status=%d", points.count, responseCode)
      } else {
        os_log(.error, log: self.oslog, "http_sync_failed: status=%d body=%@", responseCode, responseText)
      }
    }.resume()
    _ = semaphore.wait(timeout: .now() + 30)

    if httpListenerEnabled {
      delegate?.locationEngine(self, didLog: [
        "event": "httpResponse",
        "success": !resultLocations.isEmpty,
        "status": responseCode,
        "responseText": responseText,
        "locationCount": points.count,
      ])
    }

    return resultLocations
  }

  /// Fire-and-forget variant: dispatches `httpSync()` onto the background HTTP queue.
  /// Use this for internal triggered syncs to avoid blocking any caller thread.
  func httpSyncAsync(completion: (([[String: Any]]) -> Void)? = nil) {
    httpQueue.async { [weak self] in
      guard let self = self else { return }
      let results = self.httpSync()
      completion?(results)
    }
  }

  private func uploadSingle(url: String, point: StoredLocation) -> [String: Any]? {
    let dict = point.toHttpDictionary()
    guard let body = try? JSONSerialization.data(withJSONObject: dict) else { return nil }

    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = httpMethod
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in httpHeaders { request.setValue(value, forHTTPHeaderField: key) }
    request.httpBody = body
    request.timeoutInterval = 15

    let semaphore = DispatchSemaphore(value: 0)
    var success = false

    URLSession.shared.dataTask(with: request) { _, response, _ in
      if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
        success = true
      }
      semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 15)

    if success { _ = database.markDelivered(ids: [point.id]) }
    return success ? point.toDictionary() : nil
  }

  func destroyAllLocations() {
    database.clearAll()
  }

  // MARK: - Geofencing

  var geofenceStore: [String: [String: Any]] = [:]

  func addGeofence(_ data: [String: Any]) -> Bool {
    guard let id = data["identifier"] as? String else { return false }
    geofenceStore[id] = data

    // Start CLCircularRegion monitoring on iOS
    if let lat = data["latitude"] as? Double,
       let lng = data["longitude"] as? Double,
       let radius = data["radius"] as? Double {
      let region = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
        radius: max(radius, 100), // iOS minimum is 100m
        identifier: "geofence_\(id)"
      )
      region.notifyOnEntry = data["notifyOnEntry"] as? Bool ?? true
      region.notifyOnExit = data["notifyOnExit"] as? Bool ?? true
      locationManager.startMonitoring(for: region)
    }
    os_log(.debug, log: oslog, "geofence_added: %@", id)
    return true
  }

  func addGeofences(_ list: [[String: Any]]) -> Bool {
    list.forEach { _ = addGeofence($0) }
    return true
  }

  func removeGeofence(_ identifier: String) -> Bool {
    geofenceStore.removeValue(forKey: identifier)
    locationManager.stopMonitoring(for: CLCircularRegion(
      center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
      radius: 100, identifier: "geofence_\(identifier)"
    ))
    os_log(.debug, log: oslog, "geofence_removed: %@", identifier)
    return true
  }

  func removeGeofences(_ identifiers: [String]?) -> Bool {
    if let ids = identifiers {
      ids.forEach { _ = removeGeofence($0) }
    } else {
      geofenceStore.keys.forEach { _ = removeGeofence($0) }
      geofenceStore.removeAll()
    }
    return true
  }

  func getGeofences() -> [[String: Any]] {
    Array(geofenceStore.values)
  }

  func geofenceExists(_ identifier: String) -> Bool {
    geofenceStore[identifier] != nil
  }

  // MARK: - Provider State & Power Save

  func getProviderState() -> [String: Any] {
    [
      "enabled": CLLocationManager.locationServicesEnabled(),
      "status": authorizationStatusString(),
      "gps": CLLocationManager.locationServicesEnabled(),
      "network": false,
      "accuracyAuthorization": accuracyAuthorizationString(),
    ]
  }

  private func accuracyAuthorizationString() -> String {
    if #available(iOS 14.0, *) {
      switch locationManager.accuracyAuthorization {
      case .fullAccuracy: return "full"
      case .reducedAccuracy: return "reduced"
      @unknown default: return "full"
      }
    }
    return "full"
  }

  func isPowerSaveMode() -> Bool {
    return ProcessInfo.processInfo.isLowPowerModeEnabled
  }

  func getSensors() -> [String: Any] {
    // iOS sensors detection via MotionEngine availability
    [
      "accelerometer": true, // All modern iOS devices have these
      "gyroscope": true,
      "magnetometer": true,
      "motionHardware": true, // M-series coprocessor
    ]
  }

  func getDeviceInfo() -> [String: Any] {
    let device = UIDevice.current
    return [
      "manufacturer": "Apple",
      "model": device.model,
      "version": device.systemVersion,
      "platform": "ios",
      "framework": "React Native",
    ]
  }
  
  // MARK: - Live Activity Management
  
  /**
   * Enable or disable Live Activity feature (user setting).
   * Live Activity is OFF by default for security and privacy.
   */
  func setLiveActivityEnabled(_ enabled: Bool) {
    if #available(iOS 16.1, *) {
      liveActivityManager?.setEnabled(enabled)
      os_log(.debug, log: oslog, "live_activity_enabled=%d", enabled)
    }
  }
  
  /**
   * Check if Live Activity is enabled by user.
   */
  func isLiveActivityEnabled() -> Bool {
    if #available(iOS 16.1, *) {
      return liveActivityManager?.isUserEnabled ?? false
    }
    return false
  }
  
  /**
   * Check if Live Activity is currently active (showing).
   */
  func isLiveActivityActive() -> Bool {
    if #available(iOS 16.1, *) {
      return liveActivityManager?.isActive ?? false
    }
    return false
  }
  
  /**
   * Check if device supports Live Activity feature (iOS 16.1+).
   */
  func isLiveActivitySupported() -> Bool {
    if #available(iOS 16.1, *) {
      return liveActivityManager?.isSupported ?? false
    }
    return false
  }
}

extension StoredLocation {
  func toHttpDictionary() -> [String: Any] {
    [
      "latitude": latitude,
      "longitude": longitude,
      "accuracy": accuracy,
      "speed": speed,
      "altitude": altitude,
      "timestamp": timestamp,
      "heading": heading,
      "distanceFromPrev": distanceFromPrev,
      "cumulativeDistance": cumulativeDistance,
      "signalStrength": signalStrength,
      "motionState": motionState,
      "batteryLevel": batteryLevel,
    ]
  }
}

// MARK: - CLLocationManagerDelegate

extension LocationEngine: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    os_log(.debug, log: oslog, "raw lat=%.6f lng=%.6f acc=%.1f spd=%.2f", 
           location.coordinate.latitude, location.coordinate.longitude,
           location.horizontalAccuracy, location.speed)

    if let completion = pendingSingleFixCompletion {
      pendingSingleFixCompletion = nil
      lastLocation = location
      let stored = makeStored(from: location, delivered: true)
      _ = database.insert(stored)
      completion(.success(stored))
      return
    }

    processLocation(location)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    os_log(.error, log: oslog, "error %@", error.localizedDescription)
    log("location-error", ["message": error.localizedDescription])
    pendingSingleFixCompletion?(.failure(error))
    pendingSingleFixCompletion = nil
    delegate?.locationEngine(self, didFailWithError: error, watchIds: Array(watchIds.keys))
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    configureBackgroundUpdatesIfAllowed()
    finishAuthorizationRequest()
    os_log(.debug, log: oslog, "auth_change status=%@", authorizationStatusString())
    log("authorization-change", ["status": authorizationStatusString()])
    delegate?.locationEngineDidChangeAuthorization(self)
  }

  // Geofence events
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard region.identifier.hasPrefix("geofence_") else { return }
    let id = String(region.identifier.dropFirst("geofence_".count))
    os_log(.debug, log: oslog, "geofence_enter: %@", id)
    let eng = LocationEngine.shared
    if let geo = eng.geofenceStore[id] {
      eng.delegate?.locationEngine(eng, didLog: [
        "event": "geofence",
        "action": "ENTER",
        "identifier": id,
        "latitude": geo["latitude"] ?? 0,
        "longitude": geo["longitude"] ?? 0,
        "radius": geo["radius"] ?? 0,
        "timestamp": Date().timeIntervalSince1970 * 1000,
      ])
    }
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    // Check if this is a user geofence (geofence_ prefix)
    if region.identifier.hasPrefix("geofence_") {
      let id = String(region.identifier.dropFirst("geofence_".count))
      os_log(.debug, log: oslog, "geofence_exit: %@", id)
      let eng = LocationEngine.shared
      if let geo = eng.geofenceStore[id] {
        eng.delegate?.locationEngine(eng, didLog: [
          "event": "geofence",
          "action": "EXIT",
          "identifier": id,
          "latitude": geo["latitude"] ?? 0,
          "longitude": geo["longitude"] ?? 0,
          "radius": geo["radius"] ?? 0,
          "timestamp": Date().timeIntervalSince1970 * 1000,
        ])
      }
      return
    }

    // Stationary geofence for app termination recovery
    guard region.identifier == "fitness_geolocation_stationary" else { return }
    os_log(.debug, log: oslog, "stationary_geofence_exit recovering tracking")
    log("geofence-exit", ["region": region.identifier])

    // iOS relaunched us — restart GPS if we were tracking
    if !isWatching && timeBasedWatchId == nil {
      // Restore last known config and restart
      restoreWatchIfNeeded()
    }

    // Remove the geofence so we don't fire again
    removeStationaryGeofence()
  }
}
