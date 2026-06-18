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

  private let watchStateKey = "com.fitnessgeolocation.watchActive"

  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.activityType = .fitness
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = 5
    locationManager.showsBackgroundLocationIndicator = true

    NotificationCenter.default.addObserver(
      self, selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil
    )
    restoreWatchIfNeeded()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func appDidBecomeActive() {
    delegate?.locationEngineDidEnterForeground(self)
  }

  private var isAppActive: Bool {
    UIApplication.shared.applicationState == .active
  }

  func setMotionState(_ state: String) { motionState = state }

  func setPaused(_ paused: Bool) {
    isPaused = paused
    if paused {
      setMode(.stationary)
    } else {
      setMode(.fitness)
    }
  }

  private func configureBackgroundUpdatesIfAllowed() {
    if locationManager.authorizationStatus == .authorizedAlways {
      locationManager.allowsBackgroundLocationUpdates = true
    }
  }

  // MARK: - Authorization

  func requestAuthorization(level: String, completion: @escaping (String) -> Void) {
    switch level {
    case "always": locationManager.requestAlwaysAuthorization()
    default: locationManager.requestWhenInUseAuthorization()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      completion(self.authorizationStatusString())
    }
  }

  func authorizationStatusString() -> String {
    switch locationManager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "notDetermined"
    }
  }

  func hasAlwaysAuthorization() -> Bool {
    locationManager.authorizationStatus == .authorizedAlways
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
    startWatchEngine()
    return id
  }

  func clearWatch(_ watchId: Int) {
    watchIds.removeValue(forKey: watchId)
    if watchIds.isEmpty { stopWatchEngine() }
  }

  func stopObserving() {
    watchIds.removeAll()
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

  func markDelivered(ids: [String]) -> Int { database.markDelivered(ids: ids) }
  func acknowledge(ids: [String]) -> Int { database.acknowledge(ids: ids) }
  func purgeDelivered() -> Int { database.purgeDelivered() }
  func pendingCount() -> Int { database.pendingCount() }
  func getQueueSize() -> Int { database.pendingCount() }

  func getEngineState() -> [String: Any] {
    [
      "isWatching": isWatching,
      "isPaused": isPaused,
      "mode": mode.rawValue,
      "pendingQueue": database.pendingCount(),
      "motionState": motionState,
      "signalStrength": signalStrength(from: lastLocation),
      "backgroundSessionActive": backgroundSession.isActive,
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
  }

  private func stopWatchEngine() {
    isWatching = false
    backgroundSession.stop()
    locationManager.stopUpdatingLocation()
    filter.reset()
    clearWatchState()
  }

  private func restoreWatchIfNeeded() {
    guard UserDefaults.standard.bool(forKey: watchStateKey) else { return }
    configureBackgroundUpdatesIfAllowed()
    applyModeSettings()
    backgroundSession.start()
    locationManager.startUpdatingLocation()
    isWatching = true
  }

  private func persistWatchState() {
    UserDefaults.standard.set(true, forKey: watchStateKey)
    UserDefaults.standard.set(mode.rawValue, forKey: "com.fitnessgeolocation.mode")
  }

  private func clearWatchState() {
    UserDefaults.standard.set(false, forKey: watchStateKey)
  }

  private func applyWatchOptions(_ options: [String: Any]) {
    if let df = options["distanceFilter"] as? NSNumber {
      locationManager.distanceFilter = df.doubleValue
    }
    if let high = options["enableHighAccuracy"] as? Bool {
      locationManager.desiredAccuracy = high ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
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
    locationManager.desiredAccuracy = mode.desiredAccuracy
    if locationManager.distanceFilter <= 0 || locationManager.distanceFilter > 100 {
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
    if isPaused { return }

    switch filter.process(raw) {
    case .reject:
      return
    case .accept(_, let smoothed):
      lastLocation = smoothed
      let canDeliverLive = isAppActive && !watchIds.isEmpty
      let stored = makeStored(from: smoothed, delivered: canDeliverLive)

      guard database.insert(stored) else { return }

      if canDeliverLive {
        database.markDelivered(ids: [stored.id])
        delegate?.locationEngine(self, didPersist: stored, watchIds: Array(watchIds.keys), deliverLive: true)
      }
    }
  }
}

extension LocationEngine: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }

    if let completion = pendingSingleFixCompletion {
      pendingSingleFixCompletion = nil
      processLocation(location)
      if let last = lastLocation {
        completion(.success(makeStored(from: last, delivered: true)))
      }
      return
    }

    processLocation(location)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    pendingSingleFixCompletion?(.failure(error))
    pendingSingleFixCompletion = nil
    delegate?.locationEngine(self, didFailWithError: error, watchIds: Array(watchIds.keys))
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    configureBackgroundUpdatesIfAllowed()
    delegate?.locationEngineDidChangeAuthorization(self)
  }
}
