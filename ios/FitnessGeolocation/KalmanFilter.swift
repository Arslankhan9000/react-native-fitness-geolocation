import Foundation
import CoreLocation
import Accelerate

/**
 * DEPRECATED — retained for reference only.
 *
 * This Swift Kalman filter is no longer called at runtime. It has been
 * superseded by `teng::KalmanState` in TrackEngine.h, which implements
 * the identical algorithm using flat double[4] / double[4][4] arrays on
 * the stack — zero heap allocation vs ~20 per fix in this Swift version.
 *
 * See TrackEngine.h §4 for the live implementation.
 *
 * Algorithm: 2D Kalman filter with constant velocity model
 * State Vector (4D): [lat, lng, vLat, vLng]
 */
struct KalmanFilter {

  // State vector: [lat, lng, vLat, vLng]
  private var x: [Double] = [0, 0, 0, 0]

  // State covariance matrix (4x4)
  private var P: [[Double]] = [
    [1, 0, 0, 0],
    [0, 1, 0, 0],
    [0, 0, 1, 0],
    [0, 0, 0, 1]
  ]

  // Process noise covariance (tuning parameter)
  // Higher Q = trust GPS more, lower Q = trust prediction more
  private let Q: [[Double]] = [
    [0.0001, 0, 0, 0],        // Position noise
    [0, 0.0001, 0, 0],
    [0, 0, 0.01, 0],          // Velocity noise (higher)
    [0, 0, 0, 0.01]
  ]

  // Measurement noise covariance (from GPS accuracy)
  // Dynamically updated based on GPS horizontal accuracy
  private var R: [[Double]] = [
    [0.01, 0],
    [0, 0.01]
  ]

  // Time of last update
  private var lastUpdateTime: Date?

  // Initialization flag
  private var isInitialized = false

  // Quality metrics
  private var consecutiveGoodFixes = 0
  private var predictionCount = 0

  // MARK: - Public API

  /**
   * Initialize filter with first GPS fix.
   */
  mutating func initialize(location: CLLocation) {
    x[0] = location.coordinate.latitude
    x[1] = location.coordinate.longitude
    x[2] = 0 // Initial velocity unknown
    x[3] = 0

    // Initial uncertainty is high
    P = [
      [1, 0, 0, 0],
      [0, 1, 0, 0],
      [0, 0, 10, 0],
      [0, 0, 0, 10]
    ]

    lastUpdateTime = location.timestamp
    isInitialized = true
    consecutiveGoodFixes = 1
    predictionCount = 0
  }

  /**
   * Reset filter (new tracking session).
   */
  mutating func reset() {
    isInitialized = false
    consecutiveGoodFixes = 0
    predictionCount = 0
    lastUpdateTime = nil
  }

  /**
   * Process new GPS measurement.
   *
   * Returns: Filtered (smoothed) location
   */
  mutating func update(location: CLLocation) -> CLLocation {
    // First fix - initialize
    guard isInitialized else {
      initialize(location: location)
      return location
    }

    // Reject obviously bad measurements
    if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 100 {
      return predict(at: location.timestamp)
    }

    // Calculate time delta
    let dt = location.timestamp.timeIntervalSince(lastUpdateTime ?? location.timestamp)
    guard dt > 0 else { return location }

    // Prediction step
    predictStep(dt: dt)

    // Update step
    updateStep(measurement: location)

    // Create filtered location
    let filtered = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: x[0], longitude: x[1]),
      altitude: location.altitude,
      horizontalAccuracy: estimatedAccuracy(),
      verticalAccuracy: location.verticalAccuracy,
      course: estimatedCourse(),
      speed: estimatedSpeed(dt: dt),
      timestamp: location.timestamp
    )

    lastUpdateTime = location.timestamp
    consecutiveGoodFixes += 1
    predictionCount = 0

    return filtered
  }

  /**
   * Predict position without GPS measurement.
   *
   * Used when:
   * - GPS signal temporarily lost (tunnel, building)
   * - Maximum prediction: 10 seconds
   * - After 10s, stop predicting (uncertainty too high)
   */
  mutating func predict(at time: Date) -> CLLocation {
    guard isInitialized, let lastUpdate = lastUpdateTime else {
      fatalError("Cannot predict without initialization")
    }

    let dt = time.timeIntervalSince(lastUpdate)

    // Don't predict beyond 10 seconds (too uncertain)
    guard dt <= 10.0 else {
      // Return last known position with low confidence
      return CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: x[0], longitude: x[1]),
        altitude: 0,
        horizontalAccuracy: 999,
        verticalAccuracy: -1,
        course: estimatedCourse(),
        speed: max(0, estimatedSpeed(dt: dt)),
        timestamp: time
      )
    }

    // Prediction step (no update step)
    predictStep(dt: dt)

    predictionCount += 1

    let predicted = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: x[0], longitude: x[1]),
      altitude: 0,
      horizontalAccuracy: estimatedAccuracy() * Double(1 + predictionCount), // Uncertainty grows
      verticalAccuracy: -1,
      course: estimatedCourse(),
      speed: max(0, estimatedSpeed(dt: dt)),
      timestamp: time
    )

    return predicted
  }

  // MARK: - Kalman Algorithm

  /**
   * Prediction step: x_pred = F * x
   *
   * State transition matrix F (constant velocity model):
   * [1  0  dt  0 ]
   * [0  1  0  dt]
   * [0  0  1   0]
   * [0  0  0   1]
   */
  private mutating func predictStep(dt: Double) {
    // x = F * x
    let lat = x[0] + x[2] * dt
    let lng = x[1] + x[3] * dt
    let vLat = x[2]
    let vLng = x[3]

    x = [lat, lng, vLat, vLng]

    // P = F * P * F^T + Q
    let F: [[Double]] = [
      [1, 0, dt, 0],
      [0, 1, 0, dt],
      [0, 0, 1, 0],
      [0, 0, 0, 1]
    ]

    P = matrixAdd(matrixMultiply(matrixMultiply(F, P), transpose(F)), Q)
  }

  /**
   * Update step: x = x_pred + K * (z - H * x_pred)
   *
   * Measurement matrix H (we only measure position, not velocity):
   * [1  0  0  0]
   * [0  1  0  0]
   */
  private mutating func updateStep(measurement: CLLocation) {
    let z = [measurement.coordinate.latitude, measurement.coordinate.longitude]

    // Update measurement noise based on GPS accuracy
    let accuracy = max(1.0, measurement.horizontalAccuracy)
    let r = pow(accuracy / 111320.0, 2) // Convert meters to degrees²
    R = [
      [r, 0],
      [0, r]
    ]

    // Innovation: y = z - H * x
    let H: [[Double]] = [
      [1, 0, 0, 0],
      [0, 1, 0, 0]
    ]
    let Hx = matrixMultiplyVector(H, x)
    let y = [z[0] - Hx[0], z[1] - Hx[1]]

    // Innovation covariance: S = H * P * H^T + R
    let S = matrixAdd(matrixMultiply(matrixMultiply(H, P), transpose(H)), R)

    // Kalman gain: K = P * H^T * S^-1
    let K = matrixMultiply(matrixMultiply(P, transpose(H)), matrixInverse2x2(S))

    // Update state: x = x + K * y
    let Ky = matrixMultiplyVector(K, y)
    x[0] += Ky[0]
    x[1] += Ky[1]
    x[2] += Ky[2]
    x[3] += Ky[3]

    // Update covariance: P = (I - K * H) * P
    let I: [[Double]] = [
      [1, 0, 0, 0],
      [0, 1, 0, 0],
      [0, 0, 1, 0],
      [0, 0, 0, 1]
    ]
    let KH = matrixMultiply(K, H)
    P = matrixMultiply(matrixSubtract(I, KH), P)
  }

  // MARK: - Derived Metrics

  /**
   * Estimate current speed from velocity state.
   */
  private func estimatedSpeed(dt: Double) -> CLLocationSpeed {
    // Convert velocity from degrees/s to m/s
    let vLat = x[2] * 111320.0 // degrees/s to m/s (latitude)
    let vLng = x[3] * 111320.0 * cos(x[0] * .pi / 180.0) // longitude (adjusted for latitude)
    let speed = sqrt(vLat * vLat + vLng * vLng)
    return max(0, speed)
  }

  /**
   * Estimate current course (heading) from velocity state.
   */
  private func estimatedCourse() -> CLLocationDirection {
    let vLat = x[2]
    let vLng = x[3]
    if abs(vLat) < 1e-9 && abs(vLng) < 1e-9 {
      return -1 // No heading
    }
    let heading = atan2(vLng, vLat) * 180.0 / .pi
    return heading >= 0 ? heading : heading + 360
  }

  /**
   * Estimate horizontal accuracy from covariance matrix.
   */
  private func estimatedAccuracy() -> CLLocationAccuracy {
    // Uncertainty is sqrt(P[0][0] + P[1][1])
    let uncertainty = sqrt(P[0][0] + P[1][1])
    return max(1.0, uncertainty * 111320.0) // Convert degrees to meters
  }

  // MARK: - Matrix Math Helpers

  private func matrixMultiply(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    let rowsA = A.count
    let colsA = A[0].count
    let colsB = B[0].count
    var C = Array(repeating: Array(repeating: 0.0, count: colsB), count: rowsA)
    for i in 0..<rowsA {
      for j in 0..<colsB {
        for k in 0..<colsA {
          C[i][j] += A[i][k] * B[k][j]
        }
      }
    }
    return C
  }

  private func matrixMultiplyVector(_ A: [[Double]], _ v: [Double]) -> [Double] {
    return A.map { row in
      zip(row, v).map(*).reduce(0, +)
    }
  }

  private func matrixAdd(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    return zip(A, B).map { zip($0, $1).map(+) }
  }

  private func matrixSubtract(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    return zip(A, B).map { zip($0, $1).map(-) }
  }

  private func transpose(_ A: [[Double]]) -> [[Double]] {
    let rows = A.count
    let cols = A[0].count
    var T = Array(repeating: Array(repeating: 0.0, count: rows), count: cols)
    for i in 0..<rows {
      for j in 0..<cols {
        T[j][i] = A[i][j]
      }
    }
    return T
  }

  /**
   * Inverse of 2x2 matrix (for innovation covariance).
   * inv([a b; c d]) = 1/det * [d -b; -c a]
   */
  private func matrixInverse2x2(_ A: [[Double]]) -> [[Double]] {
    let det = A[0][0] * A[1][1] - A[0][1] * A[1][0]
    guard abs(det) > 1e-10 else {
      // Singular matrix - return identity
      return [[1, 0], [0, 1]]
    }
    return [
      [A[1][1] / det, -A[0][1] / det],
      [-A[1][0] / det, A[0][0] / det]
    ]
  }
}
