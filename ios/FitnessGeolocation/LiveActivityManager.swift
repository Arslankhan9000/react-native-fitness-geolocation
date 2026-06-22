import ActivityKit
import Foundation
import CoreLocation

/**
 * Live Activity Manager for iOS - Keep tracking visible and prevent GPS loss.
 *
 * CRITICAL PROBLEM (React Native GPS Apps):
 * - JS thread can die/suspend in background
 * - GPS tracking stops when JS is not responding
 * - User doesn't know tracking stopped (no visual feedback)
 *
 * SOLUTION (iOS 16.1+ Live Activities):
 * - Always-visible UI on Lock Screen + Dynamic Island
 * - Native tracking continues even if JS dies
 * - Real-time updates without waking app
 * - User knows tracking is active
 *
 * Benefits:
 * 1. **Visual Confirmation:** User sees tracking is active
 * 2. **JS Independence:** Native tracking doesn't depend on JS
 * 3. **Quick Access:** Tap to open app (resume JS)
 * 4. **Battery Efficient:** No need to wake app for UI updates
 * 5. **Professional UX:** Matches Strava, Apple Fitness
 *
 * Architecture:
 * - Live Activity is OPTIONAL (off by default, user must enable)
 * - Native tracking works with or without Live Activity
 * - Updates via ActivityKit (no push notifications needed)
 *
 * Configuration: User must enable in settings
 */

@available(iOS 16.1, *)
struct WorkoutLiveActivityAttributes: ActivityAttributes {
  public typealias WorkoutStatus = ContentState
  
  public struct ContentState: Codable, Hashable {
    var distance: Double        // meters
    var duration: TimeInterval  // seconds
    var pace: String           // min/km or min/mi
    var speed: Double          // km/h or mph
    var calories: Int          // kcal
    var heartRate: Int?        // bpm (optional)
    var gpsStatus: String      // "strong", "medium", "weak", "lost"
    var isPaused: Bool
    var activityType: String   // "running", "cycling", "walking"
  }
  
  // Static attributes (set once, never change)
  var workoutName: String      // "Morning Run", "Evening Ride"
  var startTime: Date
  var targetDistance: Double?  // meters (optional goal)
  var targetDuration: TimeInterval? // seconds (optional goal)
}

@available(iOS 16.1, *)
final class LiveActivityManager {
  
  static let shared = LiveActivityManager()
  
  private var currentActivity: Activity<WorkoutLiveActivityAttributes>?
  private var isEnabled = false

  // Circuit breaker: if updates fail repeatedly, stop trying to avoid battery drain
  private var consecutiveUpdateFailures = 0
  private let maxConsecutiveFailures = 5
  private var circuitOpen = false           // true = updates suspended
  private var circuitResetTask: Task<Void, Never>? = nil
  
  // User preferences (persisted)
  private let prefsKey = "live_activity_enabled"
  
  private init() {
    // Load user preference
    isEnabled = UserDefaults.standard.bool(forKey: prefsKey)
  }
  
  // MARK: - Configuration
  
  /**
   * Check if Live Activities are enabled by user.
   * Default: OFF (user must explicitly enable)
   */
  var isUserEnabled: Bool {
    return isEnabled
  }
  
  /**
   * Enable/disable Live Activities (user setting).
   */
  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: prefsKey)
    
    if !enabled && currentActivity != nil {
      // User disabled - end current activity
      Task {
        await endActivity()
      }
    }
    // Reset circuit breaker when user re-enables
    if enabled {
      consecutiveUpdateFailures = 0
      circuitOpen = false
      circuitResetTask?.cancel()
      circuitResetTask = nil
    }
  }
  
  /**
   * Check if device supports Live Activities.
   */
  var isSupported: Bool {
    if #available(iOS 16.1, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }
  
  /**
   * Check if Live Activity is currently active.
   */
  var isActive: Bool {
    return currentActivity != nil
  }
  
  // MARK: - Activity Lifecycle
  
  /**
   * Start Live Activity for workout.
   *
   * Called when user starts tracking.
   * Only starts if user has enabled Live Activities.
   */
  @MainActor
  func startActivity(
    workoutName: String,
    activityType: String,
    targetDistance: Double? = nil,
    targetDuration: TimeInterval? = nil
  ) async throws {
    // Respect user preference
    guard isEnabled else {
      print("📍 Live Activity disabled by user")
      return
    }
    
    // Check support
    guard isSupported else {
      print("⚠️ Live Activities not supported on this device")
      return
    }
    
    // End existing activity if any
    if currentActivity != nil {
      try await endActivity()
    }

    // Reset circuit breaker on new session
    consecutiveUpdateFailures = 0
    circuitOpen = false
    circuitResetTask?.cancel()
    circuitResetTask = nil
    
    let attributes = WorkoutLiveActivityAttributes(
      workoutName: workoutName,
      startTime: Date(),
      targetDistance: targetDistance,
      targetDuration: targetDuration
    )
    
    let initialState = WorkoutLiveActivityAttributes.ContentState(
      distance: 0,
      duration: 0,
      pace: "--:--",
      speed: 0,
      calories: 0,
      heartRate: nil,
      gpsStatus: "strong",
      isPaused: false,
      activityType: activityType
    )
    
    // Throws on ActivityKit failure — caller must handle or wrap in do/catch.
    let activity = try Activity.request(
      attributes: attributes,
      content: .init(state: initialState, staleDate: nil),
      pushType: nil // Local updates only (no push notifications)
    )
    
    currentActivity = activity
    print("✅ Live Activity started: \(activity.id)")
  }
  
  /**
   * Update Live Activity with new workout data.
   *
   * Called periodically from native LocationEngine (NOT from JS).
   * This ensures updates continue even if JS thread is dead.
   *
   * Frequency: Every 1-5 seconds (configurable)
   *
   * Circuit breaker: After 5 consecutive failures, suspends updates for 60s
   * so a broken ActivityKit state doesn't drain the battery.
   */
  @MainActor
  func updateActivity(
    distance: Double,
    duration: TimeInterval,
    pace: String,
    speed: Double,
    calories: Int,
    heartRate: Int?,
    gpsStatus: String,
    isPaused: Bool
  ) async {
    // Circuit breaker — stop hammering if ActivityKit is broken
    guard !circuitOpen else { return }
    guard let activity = currentActivity else { return }

    // Check if the activity was dismissed externally (e.g. user swiped it away)
    if activity.activityState == .dismissed || activity.activityState == .ended {
      currentActivity = nil
      consecutiveUpdateFailures = 0
      circuitOpen = false
      return
    }
    
    let updatedState = WorkoutLiveActivityAttributes.ContentState(
      distance: distance,
      duration: duration,
      pace: pace,
      speed: speed,
      calories: calories,
      heartRate: heartRate,
      gpsStatus: gpsStatus,
      isPaused: isPaused,
      activityType: activity.attributes.activityType
    )
    
    // Determine stale date (when to show "may be outdated")
    // If GPS lost, show stale immediately; otherwise 30s
    let staleDate = gpsStatus == "lost" ? Date() : Date().addingTimeInterval(30)
    
    do {
      try await activity.update(
        .init(state: updatedState, staleDate: staleDate)
      )
      // Success — reset failure counter
      consecutiveUpdateFailures = 0
    } catch {
      // Non-fatal: Live Activity update failing must NOT stop GPS tracking
      consecutiveUpdateFailures += 1
      print("⚠️ Live Activity update failed (\(consecutiveUpdateFailures)/\(maxConsecutiveFailures)): \(error.localizedDescription)")

      if consecutiveUpdateFailures >= maxConsecutiveFailures {
        // Open circuit breaker — suspend updates for 60 seconds then retry
        circuitOpen = true
        print("🔴 Live Activity circuit breaker opened — suspending updates for 60s")
        circuitResetTask?.cancel()
        circuitResetTask = Task {
          try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
          guard !Task.isCancelled else { return }
          consecutiveUpdateFailures = 0
          circuitOpen = false
          print("🟢 Live Activity circuit breaker reset — resuming updates")
        }
      }
    }
  }
  
  /**
   * End Live Activity (workout finished).
   *
   * Called when user stops tracking.
   * Shows final summary for 4 hours (iOS limit).
   * Safe to call multiple times — idempotent.
   */
  @MainActor
  func endActivity(
    finalDistance: Double? = nil,
    finalDuration: TimeInterval? = nil,
    finalCalories: Int? = nil
  ) async throws {
    guard let activity = currentActivity else { return }

    // Cancel any circuit breaker reset task
    circuitResetTask?.cancel()
    circuitResetTask = nil
    consecutiveUpdateFailures = 0
    circuitOpen = false

    // Nil out immediately so concurrent calls are safe (idempotent)
    currentActivity = nil
    
    // Create final state with summary
    var finalState = activity.content.state
    if let distance = finalDistance { finalState.distance = distance }
    if let duration = finalDuration { finalState.duration = duration }
    if let calories = finalCalories { finalState.calories = calories }
    finalState.isPaused = false
    
    do {
      // dismissalPolicy: .default = Show for 4 hours then auto-dismiss
      try await activity.end(
        .init(state: finalState, staleDate: nil),
        dismissalPolicy: .default
      )
      print("✅ Live Activity ended")
    } catch {
      // Even if end fails, we've already cleared currentActivity — safe.
      print("⚠️ Live Activity end failed (non-fatal): \(error.localizedDescription)")
      // Attempt immediate dismissal as fallback (non-throwing)
      await activity.end(dismissalPolicy: .immediate)
    }
  }
  
  // MARK: - Native Integration Helpers
  
  /**
   * Format pace for display (e.g., "5:23 min/km").
   */
  static func formatPace(metersPerSecond: Double, useMetric: Bool = true) -> String {
    guard metersPerSecond > 0.1 else { return "--:--" }
    
    let minutesPerUnit: Double
    if useMetric {
      // min/km
      minutesPerUnit = (1000.0 / metersPerSecond) / 60.0
    } else {
      // min/mi
      minutesPerUnit = (1609.34 / metersPerSecond) / 60.0
    }
    
    let minutes = Int(minutesPerUnit)
    let seconds = Int((minutesPerUnit - Double(minutes)) * 60)
    
    return String(format: "%d:%02d", minutes, seconds)
  }
  
  /**
   * Convert GPS accuracy to status string.
   */
  static func gpsStatusFromAccuracy(_ accuracy: Double) -> String {
    if accuracy < 0 {
      return "lost"
    } else if accuracy <= 10 {
      return "strong"
    } else if accuracy <= 30 {
      return "medium"
    } else {
      return "weak"
    }
  }
  
  /**
   * Estimate calories from distance and activity type.
   * Rough approximation (better to use HR if available).
   */
  static func estimateCalories(
    distance: Double,
    activityType: String,
    userWeight: Double = 70.0 // kg
  ) -> Int {
    let distanceKm = distance / 1000.0
    
    let caloriesPerKm: Double
    switch activityType {
    case "running":
      caloriesPerKm = userWeight * 1.03 // MET × weight
    case "cycling":
      caloriesPerKm = userWeight * 0.55
    case "walking":
      caloriesPerKm = userWeight * 0.57
    default:
      caloriesPerKm = userWeight * 0.8
    }
    
    return Int(distanceKm * caloriesPerKm)
  }
}

// MARK: - Fallback for iOS < 16.1

/**
 * Fallback manager for older iOS versions.
 * Does nothing but provides same API.
 */
final class LiveActivityManagerFallback {
  static let shared = LiveActivityManagerFallback()
  
  var isUserEnabled: Bool { false }
  var isSupported: Bool { false }
  var isActive: Bool { false }
  
  func setEnabled(_ enabled: Bool) {}
  func startActivity(workoutName: String, activityType: String, targetDistance: Double?, targetDuration: TimeInterval?) async {}
  func updateActivity(distance: Double, duration: TimeInterval, pace: String, speed: Double, calories: Int, heartRate: Int?, gpsStatus: String, isPaused: Bool) async {}
  func endActivity(finalDistance: Double?, finalDuration: TimeInterval?, finalCalories: Int?) async {}
}

// MARK: - Unified API (handles version check)

/**
 * Unified Live Activity API that works on all iOS versions.
 * Uses real implementation on iOS 16.1+, fallback on older versions.
 */
final class UnifiedLiveActivityManager {
  static let shared: Any = {
    if #available(iOS 16.1, *) {
      return LiveActivityManager.shared
    } else {
      return LiveActivityManagerFallback.shared
    }
  }()
  
  static var manager: LiveActivityManager? {
    if #available(iOS 16.1, *) {
      return shared as? LiveActivityManager
    }
    return nil
  }
}
