import ActivityKit
import Foundation

/**
 * Canonical Live Activity schema — shared by the FitnessGeolocation pod and the host app's
 * Widget Extension target. ActivityKit matches activities by this type name across binaries.
 *
 * Host apps: add this file (and WorkoutLiveActivityViews.swift) to both the main app and
 * Widget Extension targets, or reference them from node_modules with identical paths.
 *
 * iOS 16.1+ (ActivityKit). Timer UI uses snapshot-safe primitives for lock-screen accuracy.
 */
@available(iOS 16.1, *)
public struct WorkoutLiveActivityAttributes: ActivityAttributes {
  public typealias WorkoutStatus = ContentState

  public struct ContentState: Codable, Hashable {
    /// Meters travelled
    public var distance: Double
    /// Formatted pace e.g. "5:23"
    public var pace: String
    /// Speed in km/h
    public var speed: Double
    /// Estimated kcal
    public var calories: Int
    /// Optional BPM
    public var heartRate: Int?
    /// "strong" | "medium" | "weak" | "lost"
    public var gpsStatus: String
    public var isPaused: Bool
    /// Completed pause segments — widget timer anchor = startTime + totalPausedSeconds
    public var totalPausedSeconds: TimeInterval
    /// Active elapsed seconds when paused (frozen snapshot)
    public var frozenElapsedSeconds: TimeInterval

    public init(
      distance: Double,
      pace: String,
      speed: Double,
      calories: Int,
      heartRate: Int?,
      gpsStatus: String,
      isPaused: Bool,
      totalPausedSeconds: TimeInterval,
      frozenElapsedSeconds: TimeInterval
    ) {
      self.distance = distance
      self.pace = pace
      self.speed = speed
      self.calories = calories
      self.heartRate = heartRate
      self.gpsStatus = gpsStatus
      self.isPaused = isPaused
      self.totalPausedSeconds = totalPausedSeconds
      self.frozenElapsedSeconds = frozenElapsedSeconds
    }
  }

  /// Session title e.g. "Morning Run"
  public var workoutName: String
  /// Wall-clock session start — used with `.timer` style for smooth lock-screen elapsed time
  public var startTime: Date
  /// "running" | "cycling" | "walking"
  public var activityType: String
  /// Optional distance goal (meters)
  public var targetDistance: Double?
  /// Optional duration goal (seconds)
  public var targetDuration: TimeInterval?

  public init(
    workoutName: String,
    startTime: Date,
    activityType: String,
    targetDistance: Double?,
    targetDuration: TimeInterval?
  ) {
    self.workoutName = workoutName
    self.startTime = startTime
    self.activityType = activityType
    self.targetDistance = targetDistance
    self.targetDuration = targetDuration
  }
}
