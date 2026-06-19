import CoreLocation
import UIKit

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

protocol LocationEngineDelegate: AnyObject {
  func locationEngine(_ engine: LocationEngine, didPersist location: StoredLocation, watchIds: [Int], deliverLive: Bool)
  func locationEngine(_ engine: LocationEngine, didFailWithError error: Error, watchIds: [Int])
  func locationEngineDidChangeAuthorization(_ engine: LocationEngine)
  func locationEngineDidEnterForeground(_ engine: LocationEngine)
  func locationEngine(_ engine: LocationEngine, didLog event: [String: Any])
}

final class LocationEngine: NSObject {
  static let shared = LocationEngine()

  weak var delegate: LocationEngineDelegate?

  private let locationManager = CLLocationManager()
  private let database = LocationDatabase.shared
  private let backgroundSession = BackgroundActivitySession.shared
  private var filter = LocationFilter()

  private var isWatching = false
  private var mode: TrackingMode = .fitness
  private var sessionId: String = "default"
  private var motionState = "unknown"
  private var lastLocation: CLLocation?
  private var watchIds: [Int: Bool] = [:]
  private var nextWatchId = 1
  private var isPaused = false
  private var hasCustomDistanceFilter = false
  private var hasCustomDesiredAccuracy = false
  private var pendingAuthorizationCompletion: ((String) -> Void)?
  private var diagnostics: [[String: Any]] = []

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
    restoreWatchIfNeeded()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func appDidBecomeActive() {
    log("foreground", ["pending": database.pendingCount()])
    delegate?.locationEngineDidEnterForeground(self)
  }

  private var isAppActive: Bool {
    UIApplication.shared.applicationState == .active
  }

  func setMotionState(_ state: String) { motionState = state }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    log(paused ? "pause" : "resume", ["mode": mode.rawValue])
    if paused {
      setMode(.stationary)
    } else {
      setMode(.fitness)
    }
  }

  private func configureBackgroundUpdatesIfAllowed() {
    if currentAuthorizationStatus() == .authorizedAlways {
      locationManager.allowsBackgroundLocationUpdates = true
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

  // MARK: - Geolocation API

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

  func watchPosition(options: [String: Any]) -> Int {
    applyWatchOptions(options)
    let id = nextWatchId
    nextWatchId += 1
    watchIds[id] = true
    log("watch-add", ["watchId": id, "watchCount": watchIds.count])
    startWatchEngine()
    return id
  }

  func clearWatch(_ watchId: Int) {
    watchIds.removeValue(forKey: watchId)
    log("watch-clear", ["watchId": watchId, "watchCount": watchIds.count])
    if watchIds.isEmpty { stopWatchEngine() }
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

  func getPendingForJs(limit: Int) -> [[String: Any]] {
    database.getPendingForJs(limit: limit).map { $0.toDictionary() }
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
    return count
  }
  func pendingCount() -> Int { database.pendingCount() }
  func getQueueSize() -> Int { database.pendingCount() }

  func getDiagnostics() -> [[String: Any]] { diagnostics }

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
    ]
  }

  // MARK: - Engine lifecycle

  private func startWatchEngine() {
    isWatching = true
    configureBackgroundUpdatesIfAllowed()
    applyModeSettings()
    backgroundSession.start()
    persistWatchState()
    locationManager.startUpdatingLocation()
    log("watch-start", [
      "mode": mode.rawValue,
      "distanceFilter": locationManager.distanceFilter,
      "desiredAccuracy": locationManager.desiredAccuracy,
      "always": hasAlwaysAuthorization(),
    ])
  }

  private func stopWatchEngine() {
    isWatching = false
    backgroundSession.stop()
    locationManager.stopUpdatingLocation()
    filter.reset()
    clearWatchState()
    log("watch-stop", ["pending": database.pendingCount()])
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

  private func signalStrength(from location: CLLocation?) -> String {
    guard let acc = location?.horizontalAccuracy, acc > 0 else { return "weak" }
    if acc <= 10 { return "strong" }
    if acc <= 30 { return "medium" }
    return "weak"
  }

  private func makeStored(from location: CLLocation, delivered: Bool) -> StoredLocation {
    StoredLocation(
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
      sessionId: sessionId,
      deliveredToJs: delivered
    )
  }

  private func batteryLevel() -> Double {
    UIDevice.current.isBatteryMonitoringEnabled = true
    return Double(UIDevice.current.batteryLevel)
  }

  private func processLocation(_ raw: CLLocation) {
    if isPaused {
      log("location-drop", ["reason": "paused", "accuracy": raw.horizontalAccuracy])
      return
    }

    switch filter.process(raw) {
    case .reject(let reason):
      log("location-drop", ["reason": reason, "accuracy": raw.horizontalAccuracy])
      return
    case .accept(_, let smoothed):
      lastLocation = smoothed
      let canDeliverLive = isAppActive && !watchIds.isEmpty
      let stored = makeStored(from: smoothed, delivered: false)

      guard database.insert(stored) else {
        log("persist-failed", ["accuracy": smoothed.horizontalAccuracy])
        return
      }

      log("location-persist", [
        "id": stored.id,
        "accuracy": stored.accuracy,
        "pending": database.pendingCount(),
        "deliverLive": canDeliverLive,
      ])

      if canDeliverLive {
        delegate?.locationEngine(self, didPersist: stored, watchIds: Array(watchIds.keys), deliverLive: true)
      }
    }
  }

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

  private func finishAuthorizationRequest() {
    let completion = pendingAuthorizationCompletion
    pendingAuthorizationCompletion = nil
    completion?(authorizationStatusString())
  }
}

extension LocationEngine: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    log("location-raw", ["count": locations.count, "accuracy": location.horizontalAccuracy])

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
    log("location-error", ["message": error.localizedDescription])
    pendingSingleFixCompletion?(.failure(error))
    pendingSingleFixCompletion = nil
    delegate?.locationEngine(self, didFailWithError: error, watchIds: Array(watchIds.keys))
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    configureBackgroundUpdatesIfAllowed()
    finishAuthorizationRequest()
    log("authorization-change", ["status": authorizationStatusString()])
    delegate?.locationEngineDidChangeAuthorization(self)
  }
}
