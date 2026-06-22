import CoreLocation
import UIKit
import os.log

/**
 * Geofence Manager - App kill recovery for iOS.
 *
 * Strava/Garmin-class reliability strategy:
 * - Register MULTIPLE geofences (not just 1)
 * - Use Significant Location Change monitoring
 * - iOS keeps geofences alive even after app termination
 * - When user exits geofence, iOS relaunches app in background
 * - Auto-restart tracking within 15 seconds
 *
 * Reference: Apple Fitness, Strava, Garmin all use this pattern.
 */
final class GeofenceManager: NSObject {
  static let shared = GeofenceManager()

  private let locationManager = CLLocationManager()
  private let oslog = OSLog(subsystem: "com.fitnessgeolocation", category: "geofence")
  private var activeGeofences: [CLCircularRegion] = []
  private var isSignificantLocationChangeActive = false

  weak var delegate: GeofenceManagerDelegate?

  // Multiple radius strategy (Strava-inspired)
  // Closer geofences trigger faster, farther ones catch longer moves
  private let geofenceRadii: [CLLocationDistance] = [
    100,   // 100m - short walk from car
    250,   // 250m - coffee shop distance
    500,   // 500m - neighborhood walk
    1000,  // 1km - short drive
    2000   // 2km - medium drive
  ]

  private override init() {
    super.init()
    locationManager.delegate = self
  }

  // MARK: - Registration

  /**
   * Register multiple geofences around current location.
   *
   * Called when:
   * - App is about to be killed (willTerminate)
   * - User pauses workout (stationary for > 5 min)
   * - App enters background during active tracking
   *
   * iOS Limitation:
   * - Maximum 20 geofences per app
   * - We use 5 concentric circles
   */
  func registerGeofences(around location: CLLocation) {
    removeAllGeofences()

    let coordinate = location.coordinate
    os_log(.info, log: oslog, "Registering %d geofences at lat=%.6f lng=%.6f",
           geofenceRadii.count, coordinate.latitude, coordinate.longitude)

    for (index, radius) in geofenceRadii.enumerated() {
      let identifier = "fitness_geofence_\(index)_\(Int(radius))m"
      let region = CLCircularRegion(
        center: coordinate,
        radius: radius,
        identifier: identifier
      )

      // Critical: Only monitor exit, not entry
      // We want to know when user MOVES, not when they arrive
      region.notifyOnEntry = false
      region.notifyOnExit = true

      locationManager.startMonitoring(for: region)
      activeGeofences.append(region)

      os_log(.debug, log: oslog, "Geofence registered: %@ radius=%.0fm",
             identifier, radius)
    }

    // Also enable Significant Location Change (SLC)
    // SLC uses cell tower triangulation - very low power
    // Triggers every ~500m of movement
    enableSignificantLocationChange()

    logDiagnostic("geofences_registered", [
      "count": geofenceRadii.count,
      "location": ["lat": coordinate.latitude, "lng": coordinate.longitude],
      "radii": geofenceRadii
    ])
  }

  /**
   * Remove all active geofences.
   *
   * Called when:
   * - Tracking stops normally
   * - App returns to foreground (geofences no longer needed)
   */
  func removeAllGeofences() {
    guard !activeGeofences.isEmpty else { return }

    os_log(.info, log: oslog, "Removing %d geofences", activeGeofences.count)

    for region in activeGeofences {
      locationManager.stopMonitoring(for: region)
    }
    activeGeofences.removeAll()

    disableSignificantLocationChange()

    logDiagnostic("geofences_removed", ["count": activeGeofences.count])
  }

  /**
   * Check if any geofences are currently active.
   */
  var hasActiveGeofences: Bool {
    return !activeGeofences.isEmpty || isSignificantLocationChangeActive
  }

  // MARK: - Significant Location Change

  /**
   * Enable Significant Location Change monitoring.
   *
   * SLC Benefits:
   * - Extremely low battery usage (cell tower based)
   * - Works even when GPS is off
   * - Triggers every ~500m of movement
   * - Survives app termination
   *
   * Used by: Strava, Apple Health, Google Fit
   */
  private func enableSignificantLocationChange() {
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
      os_log(.error, log: oslog, "Significant location change not available")
      return
    }

    guard !isSignificantLocationChangeActive else {
      os_log(.debug, log: oslog, "Significant location change already active")
      return
    }

    locationManager.startMonitoringSignificantLocationChanges()
    isSignificantLocationChangeActive = true
    os_log(.info, log: oslog, "Significant location change enabled")

    logDiagnostic("slc_enabled", [:])
  }

  /**
   * Disable Significant Location Change monitoring.
   */
  private func disableSignificantLocationChange() {
    guard isSignificantLocationChangeActive else { return }

    locationManager.stopMonitoringSignificantLocationChanges()
    isSignificantLocationChangeActive = false
    os_log(.info, log: oslog, "Significant location change disabled")

    logDiagnostic("slc_disabled", [:])
  }

  // MARK: - State

  /**
   * Get current geofence state for diagnostics.
   */
  func getState() -> [String: Any] {
    return [
      "activeGeofences": activeGeofences.count,
      "slcActive": isSignificantLocationChangeActive,
      "monitoredRegions": locationManager.monitoredRegions.count,
      "geofenceRadii": geofenceRadii
    ]
  }

  // MARK: - Diagnostic Logging

  private func logDiagnostic(_ event: String, _ data: [String: Any]) {
    var payload = data
    payload["event"] = event
    payload["timestamp"] = Date().timeIntervalSince1970
    delegate?.geofenceManager(self, didLog: payload)
  }
}

// MARK: - CLLocationManagerDelegate

extension GeofenceManager: CLLocationManagerDelegate {

  /**
   * Geofence exit detected.
   *
   * This is the CRITICAL moment:
   * - User has moved significantly while app was killed
   * - iOS has relaunched our app in the background
   * - We have ~10 seconds to restart tracking
   *
   * Industry Standard Response:
   * 1. Restart location tracking immediately
   * 2. Remove geofences (no longer needed - app is running)
   * 3. Log diagnostic event
   * 4. Show background notification (optional)
   */
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard let circularRegion = region as? CLCircularRegion else { return }

    os_log(.info, log: oslog, "🚨 GEOFENCE EXIT DETECTED: %@ (app was killed, now relaunching)",
           region.identifier)

    let coordinate = circularRegion.center
    let radius = circularRegion.radius

    logDiagnostic("geofence_exit", [
      "identifier": region.identifier,
      "location": ["lat": coordinate.latitude, "lng": coordinate.longitude],
      "radius": radius,
      "appState": UIApplication.shared.applicationState.rawValue
    ])

    // Notify delegate to restart tracking
    delegate?.geofenceManagerDidDetectSignificantMovement(self, location: nil)

    // Remove geofences - app is now active
    removeAllGeofences()

    // Show notification if in background
    if UIApplication.shared.applicationState != .active {
      showResumeNotification()
    }
  }

  /**
   * Significant Location Change detected.
   *
   * Lower priority than geofence exit, but still important.
   * Triggered every ~500m using cell towers.
   */
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard isSignificantLocationChangeActive else { return }
    guard let location = locations.last else { return }

    os_log(.info, log: oslog, "📍 Significant location change: lat=%.6f lng=%.6f acc=%.0fm",
           location.coordinate.latitude, location.coordinate.longitude,
           location.horizontalAccuracy)

    logDiagnostic("slc_update", [
      "location": [
        "lat": location.coordinate.latitude,
        "lng": location.coordinate.longitude,
        "accuracy": location.horizontalAccuracy
      ],
      "appState": UIApplication.shared.applicationState.rawValue
    ])

    delegate?.geofenceManagerDidDetectSignificantMovement(self, location: location)
  }

  /**
   * Geofence monitoring failed.
   */
  func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    os_log(.error, log: oslog, "Geofence monitoring failed: %@ error=%@",
           region?.identifier ?? "unknown", error.localizedDescription)

    logDiagnostic("geofence_error", [
      "identifier": region?.identifier ?? "unknown",
      "error": error.localizedDescription
    ])
  }

  /**
   * Geofence region state changed.
   * Used for debugging.
   */
  func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    let stateStr = state == .inside ? "inside" : (state == .outside ? "outside" : "unknown")
    os_log(.debug, log: oslog, "Geofence state: %@ = %@", region.identifier, stateStr)
  }

  // MARK: - Background Notification

  /**
   * Show notification when tracking resumes after app kill.
   *
   * User-friendly feedback:
   * - "Workout tracking resumed"
   * - Shows distance moved
   * - Tap to open app
   */
  private func showResumeNotification() {
    let content = UNMutableNotificationContent()
    content.title = "Workout Tracking Resumed"
    content.body = "Movement detected. GPS tracking has automatically resumed."
    content.sound = .default
    content.categoryIdentifier = "FITNESS_TRACKING"

    let request = UNNotificationRequest(
      identifier: "fitness_tracking_resumed",
      content: content,
      trigger: nil // Immediate
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        os_log(.error, log: self.oslog, "Failed to show notification: %@",
               error.localizedDescription)
      }
    }
  }
}

// MARK: - Delegate Protocol

protocol GeofenceManagerDelegate: AnyObject {
  /**
   * Called when significant movement detected (geofence exit or SLC).
   * Delegate should restart location tracking.
   */
  func geofenceManagerDidDetectSignificantMovement(_ manager: GeofenceManager, location: CLLocation?)

  /**
   * Called for diagnostic logging.
   */
  func geofenceManager(_ manager: GeofenceManager, didLog event: [String: Any])
}
