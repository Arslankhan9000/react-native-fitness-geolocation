import ActivityKit
import WidgetKit
import SwiftUI

/**
 * Workout Live Activity Widget - Lock Screen & Dynamic Island UI.
 *
 * Displays real-time workout data on:
 * - Lock Screen (iOS 16.1+)
 * - Dynamic Island (iPhone 14 Pro+)
 * - StandBy mode
 *
 * Design Philosophy:
 * - Glanceable: See key metrics at a glance
 * - Actionable: Tap to open app
 * - Informative: Shows GPS status, pace, distance
 * - Beautiful: Matches iOS design language
 */

@available(iOS 16.1, *)
struct WorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
      // Lock Screen UI
      LockScreenLiveActivityView(context: context)
    } dynamicIsland: { context in
      // Dynamic Island UI
      DynamicIsland {
        // Expanded view (when tapped)
        DynamicIslandExpandedRegion(.leading) {
          ExpandedLeadingView(context: context)
        }
        DynamicIslandExpandedRegion(.trailing) {
          ExpandedTrailingView(context: context)
        }
        DynamicIslandExpandedRegion(.center) {
          ExpandedCenterView(context: context)
        }
        DynamicIslandExpandedRegion(.bottom) {
          ExpandedBottomView(context: context)
        }
      } compactLeading: {
        // Compact leading (left side of pill)
        CompactLeadingView(context: context)
      } compactTrailing: {
        // Compact trailing (right side of pill)
        CompactTrailingView(context: context)
      } minimal: {
        // Minimal (when multiple activities)
        MinimalView(context: context)
      }
    }
  }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    VStack(spacing: 12) {
      // Header
      HStack {
        Image(systemName: activityIcon)
          .font(.title3)
          .foregroundColor(activityColor)
        
        Text(context.attributes.workoutName)
          .font(.headline)
        
        Spacer()
        
        // GPS Status Indicator
        GPSStatusIndicator(status: context.state.gpsStatus)
      }
      
      // Main Stats
      HStack(spacing: 20) {
        // Distance
        VStack(alignment: .leading, spacing: 4) {
          Text("DISTANCE")
            .font(.caption2)
            .foregroundColor(.secondary)
          Text(formatDistance(context.state.distance))
            .font(.title2)
            .fontWeight(.bold)
        }
        
        Spacer()
        
        // Duration
        VStack(alignment: .center, spacing: 4) {
          Text("TIME")
            .font(.caption2)
            .foregroundColor(.secondary)
          Text(formatDuration(context.state.duration))
            .font(.title2)
            .fontWeight(.bold)
            .monospacedDigit()
        }
        
        Spacer()
        
        // Pace
        VStack(alignment: .trailing, spacing: 4) {
          Text("PACE")
            .font(.caption2)
            .foregroundColor(.secondary)
          Text(context.state.pace)
            .font(.title3)
            .fontWeight(.semibold)
        }
      }
      
      // Progress bar (if target set)
      if let targetDistance = context.attributes.targetDistance {
        ProgressBar(
          current: context.state.distance,
          target: targetDistance,
          color: activityColor
        )
      }
      
      // Pause indicator
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
  }
  
  private var activityIcon: String {
    switch context.state.activityType {
    case "running": return "figure.run"
    case "cycling": return "figure.outdoor.cycle"
    case "walking": return "figure.walk"
    default: return "figure.mixed.cardio"
    }
  }
  
  private var activityColor: Color {
    switch context.state.activityType {
    case "running": return .green
    case "cycling": return .blue
    case "walking": return .orange
    default: return .purple
    }
  }
}

// MARK: - Dynamic Island Views

@available(iOS 16.1, *)
struct CompactLeadingView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: activityIcon)
        .font(.caption)
        .foregroundColor(activityColor)
      
      Text(formatDistance(context.state.distance, short: true))
        .font(.caption)
        .fontWeight(.semibold)
    }
  }
  
  private var activityIcon: String {
    switch context.state.activityType {
    case "running": return "figure.run"
    case "cycling": return "figure.outdoor.cycle"
    case "walking": return "figure.walk"
    default: return "figure.mixed.cardio"
    }
  }
  
  private var activityColor: Color {
    switch context.state.activityType {
    case "running": return .green
    case "cycling": return .blue
    case "walking": return .orange
    default: return .purple
    }
  }
}

@available(iOS 16.1, *)
struct CompactTrailingView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    Text(formatDuration(context.state.duration, short: true))
      .font(.caption)
      .fontWeight(.semibold)
      .monospacedDigit()
  }
}

@available(iOS 16.1, *)
struct MinimalView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    Image(systemName: activityIcon)
      .font(.caption2)
      .foregroundColor(activityColor)
  }
  
  private var activityIcon: String {
    switch context.state.activityType {
    case "running": return "figure.run"
    case "cycling": return "figure.outdoor.cycle"
    case "walking": return "figure.walk"
    default: return "figure.mixed.cardio"
    }
  }
  
  private var activityColor: Color {
    switch context.state.activityType {
    case "running": return .green
    case "cycling": return .blue
    case "walking": return .orange
    default: return .purple
    }
  }
}

@available(iOS 16.1, *)
struct ExpandedLeadingView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("DISTANCE")
        .font(.caption2)
        .foregroundColor(.secondary)
      Text(formatDistance(context.state.distance))
        .font(.title3)
        .fontWeight(.bold)
    }
  }
}

@available(iOS 16.1, *)
struct ExpandedTrailingView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Text("PACE")
        .font(.caption2)
        .foregroundColor(.secondary)
      Text(context.state.pace)
        .font(.title3)
        .fontWeight(.semibold)
    }
  }
}

@available(iOS 16.1, *)
struct ExpandedCenterView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    VStack(spacing: 8) {
      Text(formatDuration(context.state.duration))
        .font(.title)
        .fontWeight(.bold)
        .monospacedDigit()
      
      Text(context.attributes.workoutName)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

@available(iOS 16.1, *)
struct ExpandedBottomView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>
  
  var body: some View {
    HStack {
      // Calories
      if context.state.calories > 0 {
        HStack(spacing: 4) {
          Image(systemName: "flame.fill")
            .font(.caption)
            .foregroundColor(.orange)
          Text("\(context.state.calories) cal")
            .font(.caption)
        }
      }
      
      Spacer()
      
      // Heart Rate (if available)
      if let hr = context.state.heartRate {
        HStack(spacing: 4) {
          Image(systemName: "heart.fill")
            .font(.caption)
            .foregroundColor(.red)
          Text("\(hr) bpm")
            .font(.caption)
        }
      }
      
      Spacer()
      
      // GPS Status
      GPSStatusIndicator(status: context.state.gpsStatus, compact: true)
    }
    .padding(.horizontal)
  }
}

// MARK: - Reusable Components

@available(iOS 16.1, *)
struct GPSStatusIndicator: View {
  let status: String
  var compact: Bool = false
  
  var body: some View {
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

@available(iOS 16.1, *)
struct ProgressBar: View {
  let current: Double
  let target: Double
  let color: Color
  
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Color.secondary.opacity(0.2))
          .frame(height: 4)
          .cornerRadius(2)
        
        Rectangle()
          .fill(color)
          .frame(width: min(CGFloat(current / target) * geometry.size.width, geometry.size.width), height: 4)
          .cornerRadius(2)
      }
    }
    .frame(height: 4)
  }
}

// MARK: - Formatting Helpers

private func formatDistance(_ meters: Double, short: Bool = false) -> String {
  let km = meters / 1000.0
  if short {
    return String(format: "%.1fk", km)
  } else {
    return String(format: "%.2f km", km)
  }
}

private func formatDuration(_ seconds: TimeInterval, short: Bool = false) -> String {
  let hours = Int(seconds) / 3600
  let minutes = Int(seconds) / 60 % 60
  let secs = Int(seconds) % 60
  
  if hours > 0 {
    return String(format: "%d:%02d:%02d", hours, minutes, secs)
  } else {
    return String(format: "%d:%02d", minutes, secs)
  }
}

// MARK: - Preview

@available(iOS 16.1, *)
struct WorkoutLiveActivity_Previews: PreviewProvider {
  static let attributes = WorkoutLiveActivityAttributes(
    workoutName: "Morning Run",
    startTime: Date(),
    targetDistance: 5000,
    targetDuration: nil
  )
  
  static let contentState = WorkoutLiveActivityAttributes.ContentState(
    distance: 2340,
    duration: 720,
    pace: "5:08",
    speed: 11.7,
    calories: 234,
    heartRate: 152,
    gpsStatus: "strong",
    isPaused: false,
    activityType: "running"
  )
  
  static var previews: some View {
    attributes
      .previewContext(contentState, viewKind: .content)
      .previewDisplayName("Lock Screen")
    
    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.compact))
      .previewDisplayName("Dynamic Island Compact")
    
    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
      .previewDisplayName("Dynamic Island Expanded")
  }
}
