import ActivityKit
import Foundation
import CoreLocation

/**
 * Live Activity Manager — native workout visibility on Lock Screen & Dynamic Island.
 *
 * Updates are driven from LocationEngine (not JS). Elapsed time uses snapshot-safe
 * `Text(_:style: .timer)` in the widget; this manager only pushes pause boundaries
 * and metric deltas (distance, pace, GPS).
 *
 * iOS 16.1+ (ActivityKit). Requires NSSupportsLiveActivities in host Info.plist.
 */

@available(iOS 16.1, *)
final class LiveActivityManager {

  static let shared = LiveActivityManager()

  private var currentActivity: Activity<WorkoutLiveActivityAttributes>?
  private var isEnabled = false

  private var consecutiveUpdateFailures = 0
  private let maxConsecutiveFailures = 5
  private var circuitOpen = false
  private var circuitResetTask: Task<Void, Never>? = nil

  private let prefsKey = "live_activity_enabled"

  /// Pause bookkeeping for accurate widget timers
  private var accumulatedPauseSeconds: TimeInterval = 0
  private var pauseBeganAt: Date?
  private var lastIsPaused = false

  private init() {
    isEnabled = UserDefaults.standard.bool(forKey: prefsKey)
  }

  /// End every system Live Activity for this app (e.g. stale lock-screen widget after crash).
  @MainActor
  func dismissAllActivities(immediate: Bool = true) async {
    circuitResetTask?.cancel()
    circuitResetTask = nil
    consecutiveUpdateFailures = 0
    circuitOpen = false
    accumulatedPauseSeconds = 0
    pauseBeganAt = nil
    lastIsPaused = false
    currentActivity = nil

    let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
    for activity in Activity<WorkoutLiveActivityAttributes>.activities {
      if #available(iOS 16.2, *) {
        await activity.end(nil, dismissalPolicy: policy)
      } else {
        await activity.end(dismissalPolicy: policy)
      }
    }
  }

  // MARK: - Configuration

  var isUserEnabled: Bool { isEnabled }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: prefsKey)

    if !enabled && currentActivity != nil {
      Task { try? await endActivity() }
    }
    if enabled {
      consecutiveUpdateFailures = 0
      circuitOpen = false
      circuitResetTask?.cancel()
      circuitResetTask = nil
    }
  }

  var isSupported: Bool {
    if #available(iOS 16.1, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }

  var isActive: Bool { currentActivity != nil }

  // MARK: - Activity Lifecycle

  @MainActor
  func startActivity(
    workoutName: String,
    activityType: String,
    targetDistance: Double? = nil,
    targetDuration: TimeInterval? = nil
  ) async throws {
    guard isEnabled else { return }
    guard isSupported else { return }

    if currentActivity != nil {
      try await endActivity()
    }

    consecutiveUpdateFailures = 0
    circuitOpen = false
    circuitResetTask?.cancel()
    circuitResetTask = nil
    accumulatedPauseSeconds = 0
    pauseBeganAt = nil
    lastIsPaused = false

    let startTime = Date()
    let attributes = WorkoutLiveActivityAttributes(
      workoutName: workoutName,
      startTime: startTime,
      activityType: activityType,
      targetDistance: targetDistance,
      targetDuration: targetDuration
    )

    let initialState = WorkoutLiveActivityAttributes.ContentState(
      distance: 0,
      pace: "--:--",
      speed: 0,
      calories: 0,
      heartRate: nil,
      gpsStatus: "strong",
      isPaused: false,
      totalPausedSeconds: 0,
      frozenElapsedSeconds: 0
    )

    let activity: Activity<WorkoutLiveActivityAttributes>
    if #available(iOS 16.2, *) {
      activity = try Activity.request(
        attributes: attributes,
        content: .init(state: initialState, staleDate: nil),
        pushType: nil
      )
    } else {
      activity = try Activity.request(
        attributes: attributes,
        contentState: initialState,
        pushType: nil
      )
    }

    currentActivity = activity
  }

  /**
   * Push metric updates. `duration` is accepted for bridge compatibility but ignored —
   * the widget derives elapsed time from `attributes.startTime` and pause fields.
   */
  @MainActor
  func updateActivity(
    distance: Double,
    duration: TimeInterval = 0,
    pace: String,
    speed: Double,
    calories: Int,
    heartRate: Int?,
    gpsStatus: String,
    isPaused: Bool
  ) async {
    _ = duration
    guard !circuitOpen else { return }
    guard let activity = currentActivity else { return }

    if activity.activityState == .dismissed || activity.activityState == .ended {
      currentActivity = nil
      consecutiveUpdateFailures = 0
      circuitOpen = false
      return
    }

    let pauseFields = computePauseFields(
      isPaused: isPaused,
      startTime: activity.attributes.startTime
    )
    lastIsPaused = isPaused

    let updatedState = WorkoutLiveActivityAttributes.ContentState(
      distance: distance,
      pace: pace,
      speed: speed,
      calories: calories,
      heartRate: heartRate,
      gpsStatus: gpsStatus,
      isPaused: isPaused,
      totalPausedSeconds: pauseFields.totalPaused,
      frozenElapsedSeconds: pauseFields.frozenElapsed
    )

    let staleDate = gpsStatus == "lost" ? Date() : Date().addingTimeInterval(45)

    if #available(iOS 16.2, *) {
      do {
        try await activity.update(.init(state: updatedState, staleDate: staleDate))
        consecutiveUpdateFailures = 0
      } catch {
        consecutiveUpdateFailures += 1
        if consecutiveUpdateFailures >= maxConsecutiveFailures {
          circuitOpen = true
          circuitResetTask?.cancel()
          circuitResetTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            consecutiveUpdateFailures = 0
            circuitOpen = false
          }
        }
      }
    } else {
      // iOS 16.1 API: non-throwing update without ActivityContent wrapper.
      await activity.update(using: updatedState)
      consecutiveUpdateFailures = 0
    }
  }

  @MainActor
  func endActivity(
    finalDistance: Double? = nil,
    finalDuration: TimeInterval? = nil,
    finalCalories: Int? = nil,
    dismissImmediately: Bool = false
  ) async throws {
    guard let activity = currentActivity else { return }

    circuitResetTask?.cancel()
    circuitResetTask = nil
    consecutiveUpdateFailures = 0
    circuitOpen = false
    accumulatedPauseSeconds = 0
    pauseBeganAt = nil
    lastIsPaused = false
    currentActivity = nil

    var finalState: WorkoutLiveActivityAttributes.ContentState
    if #available(iOS 16.2, *) {
      finalState = activity.content.state
    } else {
      finalState = activity.contentState
    }
    if let distance = finalDistance { finalState.distance = distance }
    if let calories = finalCalories { finalState.calories = calories }
    if let duration = finalDuration, duration > 0 {
      finalState.frozenElapsedSeconds = duration
      finalState.isPaused = true
    } else {
      finalState.isPaused = false
    }

    let policy: ActivityUIDismissalPolicy = dismissImmediately ? .immediate : .default

    if #available(iOS 16.2, *) {
      do {
        try await activity.end(
          .init(state: finalState, staleDate: nil),
          dismissalPolicy: policy
        )
      } catch {
        await activity.end(dismissalPolicy: .immediate)
      }
    } else {
      // iOS 16.1 API: non-throwing end using final state.
      await activity.end(using: finalState, dismissalPolicy: policy)
    }

    // Sweep any orphaned system activities (manager lost reference after relaunch).
    if dismissImmediately {
      await dismissAllActivities(immediate: true)
    }
  }

  // MARK: - Pause math

  private struct PauseFields {
    let totalPaused: TimeInterval
    let frozenElapsed: TimeInterval
  }

  private func computePauseFields(isPaused: Bool, startTime: Date) -> PauseFields {
    let now = Date()

    if isPaused && !lastIsPaused {
      pauseBeganAt = now
    } else if !isPaused && lastIsPaused {
      if let began = pauseBeganAt {
        accumulatedPauseSeconds += now.timeIntervalSince(began)
      }
      pauseBeganAt = nil
    }

    var frozen: TimeInterval = 0
    if isPaused {
      let pauseStart = pauseBeganAt ?? now
      frozen = max(0, pauseStart.timeIntervalSince(startTime) - accumulatedPauseSeconds)
    }

    return PauseFields(totalPaused: accumulatedPauseSeconds, frozenElapsed: frozen)
  }

  // MARK: - Formatting helpers

  static func formatPace(metersPerSecond: Double, useMetric: Bool = true) -> String {
    guard metersPerSecond > 0.1 else { return "--:--" }

    let minutesPerUnit: Double
    if useMetric {
      minutesPerUnit = (1000.0 / metersPerSecond) / 60.0
    } else {
      minutesPerUnit = (1609.34 / metersPerSecond) / 60.0
    }

    let minutes = Int(minutesPerUnit)
    let seconds = Int((minutesPerUnit - Double(minutes)) * 60)
    return String(format: "%d:%02d", minutes, seconds)
  }

  static func gpsStatusFromAccuracy(_ accuracy: Double) -> String {
    if accuracy < 0 { return "lost" }
    if accuracy <= 10 { return "strong" }
    if accuracy <= 30 { return "medium" }
    return "weak"
  }

  static func estimateCalories(
    distance: Double,
    activityType: String,
    userWeight: Double = 70.0
  ) -> Int {
    let distanceKm = distance / 1000.0
    let caloriesPerKm: Double
    switch activityType {
    case "running": caloriesPerKm = userWeight * 1.03
    case "cycling": caloriesPerKm = userWeight * 0.55
    case "walking": caloriesPerKm = userWeight * 0.57
    default: caloriesPerKm = userWeight * 0.8
    }
    return Int(distanceKm * caloriesPerKm)
  }
}

// MARK: - Fallback (iOS < 16.1)

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

final class UnifiedLiveActivityManager {
  static let shared: Any = {
    if #available(iOS 16.1, *) {
      return LiveActivityManager.shared
    }
    return LiveActivityManagerFallback.shared
  }()

  static var manager: LiveActivityManager? {
    if #available(iOS 16.1, *) {
      return shared as? LiveActivityManager
    }
    return nil
  }
}
