import Foundation
import Network
import UIKit

/// Lightweight provider/connectivity monitor for background engine events.
final class ProviderMonitor {
  static let shared = ProviderMonitor()

  var onEvent: (([String: Any]) -> Void)?

  private let pathMonitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.fitnessgeolocation.provider", qos: .utility)
  private var lastPowerSave: Bool?
  private var lastConnected: Bool?

  private init() {}

  func start() {
    lastPowerSave = ProcessInfo.processInfo.isLowPowerModeEnabled
    NotificationCenter.default.addObserver(
      self, selector: #selector(powerChanged),
      name: .NSProcessInfoPowerStateDidChange, object: nil
    )
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let connected = path.status == .satisfied
      guard let self = self, connected != self.lastConnected else { return }
      self.lastConnected = connected
      self.onEvent?(["event": "connectivityChange", "connected": connected])
    }
    pathMonitor.start(queue: queue)
  }

  func stop() {
    pathMonitor.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func powerChanged() {
    let save = ProcessInfo.processInfo.isLowPowerModeEnabled
    guard save != lastPowerSave else { return }
    lastPowerSave = save
    onEvent?(["event": "powerSaveChange", "enabled": save])
  }

  func emitProviderChange(_ state: [String: Any]) {
    var event = state
    event["event"] = "providerChange"
    onEvent?(event)
  }
}
