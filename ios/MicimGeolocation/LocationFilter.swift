import CoreLocation

/// Strava-class GPS filter — accuracy gate, spike detection, weighted smoothing
struct LocationFilter {
  private var lastAccepted: CLLocation?
  private var lastRaw: CLLocation?
  private var goodFixCount = 0
  private let warmupPoints: Int

  var maxAccuracyM: CLLocationAccuracy = 50
  var maxSpeedMps: Double = 150
  var minDistanceM: Double = 1

  init(warmupPoints: Int = 3) {
    self.warmupPoints = warmupPoints
  }

  mutating func reset() {
    lastAccepted = nil
    lastRaw = nil
    goodFixCount = 0
  }

  enum FilterResult {
    case accept(CLLocation, smoothed: CLLocation)
    case reject(reason: String)
  }

  mutating func process(_ location: CLLocation) -> FilterResult {
    if location.horizontalAccuracy < 0 || location.horizontalAccuracy > maxAccuracyM {
      return .reject(reason: "accuracy")
    }
    if location.coordinate.latitude == 0 && location.coordinate.longitude == 0 {
      return .reject(reason: "zero")
    }

    if let prev = lastRaw {
      let dt = location.timestamp.timeIntervalSince(prev.timestamp)
      if dt <= 0 { return .reject(reason: "time") }
      let dist = location.distance(from: prev)
      let speed = dist / dt
      if speed > maxSpeedMps { return .reject(reason: "spike") }
      if dist < minDistanceM && location.horizontalAccuracy > 20 {
        return .reject(reason: "jitter")
      }
    }

    lastRaw = location

    if goodFixCount < warmupPoints {
      goodFixCount += 1
      lastAccepted = location
      return .accept(location, smoothed: location)
    }

    let smoothed = smooth(prev: lastAccepted, cur: location)
    lastAccepted = smoothed
    return .accept(location, smoothed: smoothed)
  }

  private func smooth(prev: CLLocation?, cur: CLLocation) -> CLLocation {
    guard let prev = prev else { return cur }
    let wPrev = 1.0 / pow(max(1, prev.horizontalAccuracy), 2)
    let wCur = 1.0 / pow(max(1, cur.horizontalAccuracy), 2)
    let w = wPrev + wCur
    let lat = (prev.coordinate.latitude * wPrev + cur.coordinate.latitude * wCur) / w
    let lon = (prev.coordinate.longitude * wPrev + cur.coordinate.longitude * wCur) / w
    return CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
      altitude: cur.altitude,
      horizontalAccuracy: min(prev.horizontalAccuracy, cur.horizontalAccuracy),
      verticalAccuracy: cur.verticalAccuracy,
      course: cur.course,
      speed: cur.speed,
      timestamp: cur.timestamp
    )
  }
}
