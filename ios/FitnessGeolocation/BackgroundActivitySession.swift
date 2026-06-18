import Foundation
import CoreLocation

#if canImport(_LocationEssentials)
import _LocationEssentials
#endif

/// iOS 17+ CLBackgroundActivitySession — keeps location pipeline alive in background (Apple recommended)
final class BackgroundActivitySession {
  static let shared = BackgroundActivitySession()

  private var session: AnyObject?

  func start() {
    if #available(iOS 17.0, *) {
      let s = CLBackgroundActivitySession()
      session = s
    }
  }

  func stop() {
    if #available(iOS 17.0, *) {
      (session as? CLBackgroundActivitySession)?.invalidate()
    }
    session = nil
  }

  var isActive: Bool { session != nil }
}
