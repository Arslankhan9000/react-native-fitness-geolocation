import ActivityKit
import SwiftUI
import WidgetKit

/// Deep link opened when the user taps the Live Activity / Dynamic Island.
public enum WorkoutLiveActivityDeepLink {
  public static let url = URL(string: "fitnessgeolocation://workout")!
}

// MARK: - Formatting

@available(iOS 16.1, *)
public enum WorkoutFormat {
  public static func distance(_ meters: Double, short: Bool = false) -> String {
    let km = meters / 1000.0
    if short { return String(format: "%.1fk", km) }
    return String(format: "%.2f km", km)
  }

  public static func elapsed(_ seconds: TimeInterval, short: Bool = false) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total / 60) % 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    if short && minutes >= 10 {
      return String(format: "%d:%02d", minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  public static func timerAnchor(
    startTime: Date,
    totalPausedSeconds: TimeInterval
  ) -> Date {
    startTime.addingTimeInterval(totalPausedSeconds)
  }
}

// MARK: - Snapshot-safe elapsed timer (iOS 16+)

/// Uses `Text(_:style: .timer)` when running — interpolates on lock screen without frequent pushes.
/// Shows frozen elapsed text when paused.
@available(iOS 16.1, *)
public struct WorkoutElapsedView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  var short: Bool = false
  var font: Font = .title2
  var weight: Font.Weight = .bold

  public init(
    context: ActivityViewContext<WorkoutLiveActivityAttributes>,
    short: Bool = false,
    font: Font = .title2,
    weight: Font.Weight = .bold
  ) {
    self.context = context
    self.short = short
    self.font = font
    self.weight = weight
  }

  public var body: some View {
    Group {
      if context.state.isPaused {
        Text(WorkoutFormat.elapsed(context.state.frozenElapsedSeconds, short: short))
      } else {
        Text(
          WorkoutFormat.timerAnchor(
            startTime: context.attributes.startTime,
            totalPausedSeconds: context.state.totalPausedSeconds
          ),
          style: .timer
        )
      }
    }
    .font(font)
    .fontWeight(weight)
    .monospacedDigit()
    .multilineTextAlignment(.center)
  }
}

// MARK: - Goal progress

@available(iOS 16.1, *)
public struct WorkoutDurationGoalProgressView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  let color: Color

  public var body: some View {
    if let target = context.attributes.targetDuration, target > 0 {
      if context.state.isPaused {
        WorkoutRatioProgressView(
          progress: min(1, context.state.frozenElapsedSeconds / target),
          color: color
        )
      } else {
        let anchor = WorkoutFormat.timerAnchor(
          startTime: context.attributes.startTime,
          totalPausedSeconds: context.state.totalPausedSeconds
        )
        let end = anchor.addingTimeInterval(target)
        ProgressView(timerInterval: anchor...end, countsDown: false)
          .progressViewStyle(.linear)
          .tint(color)
          .scaleEffect(x: 1, y: 2, anchor: .center)
          .clipShape(Capsule())
      }
    }
  }
}

@available(iOS 16.1, *)
public struct WorkoutDistanceGoalProgressView: View {
  let current: Double
  let target: Double
  let color: Color

  public var body: some View {
    WorkoutRatioProgressView(
      progress: target > 0 ? min(1, current / target) : 0,
      color: color
    )
  }
}

@available(iOS 16.1, *)
public struct WorkoutRatioProgressView: View {
  let progress: Double
  let color: Color

  public var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.secondary.opacity(0.25))
        Capsule()
          .fill(color)
          .frame(width: max(0, CGFloat(progress)) * geometry.size.width)
      }
    }
    .frame(height: 6)
  }
}

// MARK: - Activity styling

@available(iOS 16.1, *)
public enum WorkoutActivityStyle {
  public static func icon(for activityType: String) -> String {
    switch activityType {
    case "running": return "figure.run"
    case "cycling": return "figure.outdoor.cycle"
    case "walking": return "figure.walk"
    default: return "figure.mixed.cardio"
    }
  }

  public static func color(for activityType: String) -> Color {
    switch activityType {
    case "running": return .green
    case "cycling": return .blue
    case "walking": return .orange
    default: return .purple
    }
  }
}

@available(iOS 16.1, *)
public struct GPSStatusIndicator: View {
  let status: String
  var compact: Bool = false

  public var body: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(statusColor)
        .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
      if !compact {
        Text(statusText)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
  }

  private var statusColor: Color {
    switch status {
    case "strong": return .green
    case "medium": return .yellow
    case "weak": return .orange
    case "lost": return .red
    default: return .gray
    }
  }

  private var statusText: String {
    switch status {
    case "strong": return "GPS Strong"
    case "medium": return "GPS Medium"
    case "weak": return "GPS Weak"
    case "lost": return "GPS Lost"
    default: return "GPS"
    }
  }
}

// MARK: - Lock Screen

@available(iOS 16.1, *)
public struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>

  private var activityColor: Color {
    WorkoutActivityStyle.color(for: context.attributes.activityType)
  }

  public var body: some View {
    VStack(spacing: 12) {
      HStack {
        Image(systemName: WorkoutActivityStyle.icon(for: context.attributes.activityType))
          .font(.title3)
          .foregroundColor(activityColor)
        Text(context.attributes.workoutName)
          .font(.headline)
        Spacer()
        GPSStatusIndicator(status: context.state.gpsStatus)
      }

      HStack(spacing: 20) {
        VStack(alignment: .leading, spacing: 4) {
          Text("DISTANCE")
            .font(.caption2)
            .foregroundColor(.secondary)
          Text(WorkoutFormat.distance(context.state.distance))
            .font(.title2)
            .fontWeight(.bold)
        }
        Spacer()
        VStack(alignment: .center, spacing: 4) {
          Text("TIME")
            .font(.caption2)
            .foregroundColor(.secondary)
          WorkoutElapsedView(context: context)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text("PACE")
            .font(.caption2)
            .foregroundColor(.secondary)
          Text(context.state.pace)
            .font(.title3)
            .fontWeight(.semibold)
        }
      }

      if context.attributes.targetDuration != nil {
        WorkoutDurationGoalProgressView(context: context, color: activityColor)
      } else if let targetDistance = context.attributes.targetDistance {
        WorkoutDistanceGoalProgressView(
          current: context.state.distance,
          target: targetDistance,
          color: activityColor
        )
      }

      if context.state.isPaused {
        HStack {
          Image(systemName: "pause.circle.fill")
            .foregroundColor(.orange)
          Text("Paused")
            .font(.subheadline)
            .foregroundColor(.orange)
        }
        .padding(.vertical, 4)
      }
    }
    .padding()
    .activityBackgroundTint(Color.black.opacity(0.3))
    .widgetURL(WorkoutLiveActivityDeepLink.url)
  }
}

// MARK: - Widget configuration helper

@available(iOS 16.1, *)
public struct WorkoutLiveActivityWidgetConfig: Widget {
  public init() {}

  private func activityColor(for context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> Color {
    WorkoutActivityStyle.color(for: context.attributes.activityType)
  }

  public var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
      LockScreenLiveActivityView(context: context)
    } dynamicIsland: { context in
      let tint = activityColor(for: context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 4) {
            Text("DISTANCE")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(WorkoutFormat.distance(context.state.distance))
              .font(.title3)
              .fontWeight(.bold)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 4) {
            Text("PACE")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(context.state.pace)
              .font(.title3)
              .fontWeight(.semibold)
          }
        }
        DynamicIslandExpandedRegion(.center) {
          WorkoutElapsedView(context: context, font: .title, weight: .bold)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            if context.state.calories > 0 {
              Label("\(context.state.calories) cal", systemImage: "flame.fill")
                .font(.caption)
                .foregroundColor(.orange)
            }
            Spacer()
            if let hr = context.state.heartRate {
              Label("\(hr) bpm", systemImage: "heart.fill")
                .font(.caption)
                .foregroundColor(.red)
            }
            Spacer()
            GPSStatusIndicator(status: context.state.gpsStatus, compact: true)
            Spacer()
            Link(destination: WorkoutLiveActivityDeepLink.url) {
              Label("Open", systemImage: "arrow.up.forward.app")
                .font(.caption)
            }
          }
          .padding(.horizontal)
        }
      } compactLeading: {
        HStack(spacing: 4) {
          Image(systemName: WorkoutActivityStyle.icon(for: context.attributes.activityType))
            .font(.caption)
            .foregroundColor(tint)
          Text(WorkoutFormat.distance(context.state.distance, short: true))
            .font(.caption)
            .fontWeight(.semibold)
        }
      } compactTrailing: {
        WorkoutElapsedView(
          context: context,
          short: true,
          font: .caption,
          weight: .semibold
        )
        .frame(maxWidth: 52)
      } minimal: {
        VStack(spacing: 2) {
          Image(systemName: WorkoutActivityStyle.icon(for: context.attributes.activityType))
            .font(.caption2)
            .foregroundColor(tint)
          WorkoutElapsedView(
            context: context,
            short: true,
            font: .caption2,
            weight: .semibold
          )
        }
      }
      .keylineTint(tint)
      .widgetURL(WorkoutLiveActivityDeepLink.url)
    }
  }
}

// MARK: - Previews (iOS 16.2+)

@available(iOS 16.2, *)
public struct WorkoutLiveActivityPreviews: PreviewProvider {
  public static let attributes = WorkoutLiveActivityAttributes(
    workoutName: "Morning Run",
    startTime: Date().addingTimeInterval(-720),
    activityType: "running",
    targetDistance: 5000,
    targetDuration: 1800
  )

  public static let contentState = WorkoutLiveActivityAttributes.ContentState(
    distance: 2340,
    pace: "5:08",
    speed: 11.7,
    calories: 234,
    heartRate: 152,
    gpsStatus: "strong",
    isPaused: false,
    totalPausedSeconds: 0,
    frozenElapsedSeconds: 0
  )

  public static var previews: some View {
    attributes
      .previewContext(contentState, viewKind: .content)
      .previewDisplayName("Lock Screen")

    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.compact))
      .previewDisplayName("Compact")

    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
      .previewDisplayName("Expanded")

    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
      .previewDisplayName("Minimal")
  }
}
