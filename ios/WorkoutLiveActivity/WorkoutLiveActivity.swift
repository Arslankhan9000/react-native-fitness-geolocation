import WidgetKit
import SwiftUI

/**
 * Reference Widget Extension entry — host apps copy this into their Widget target.
 * lifeTracker uses WorkoutLiveActivityWidgetBundle in its own extension.
 */
@available(iOS 16.1, *)
@main
struct WorkoutLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    WorkoutLiveActivityWidgetConfig()
  }
}
