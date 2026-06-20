import Foundation

/// Protocol for DebugMonitor events to be handled by the bridge.
/// Uses AnyObject to avoid compilation order dependency on DebugMonitor class.
@objc protocol DebugMonitorDelegate: AnyObject {
  func debugMonitor(_ monitor: AnyObject, didChangeEnabled enabled: Bool)
  func debugMonitor(_ monitor: AnyObject, didEmitMotionState state: [String: Any])
  func debugMonitor(_ monitor: AnyObject, didEmitHeartbeat event: [String: Any])
  func debugMonitor(_ monitor: AnyObject, didEmitLifecycleEvent event: [String: Any])
}
