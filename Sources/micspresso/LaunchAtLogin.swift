import Foundation
import ServiceManagement
import os

enum LaunchAtLogin {
  private static let log = Logger(
    subsystem: "com.moltenbits.micspresso", category: "launch-at-login")

  /// SMAppService only works from a real .app bundle; when running the
  /// bare binary (swift run), registration would fail confusingly.
  static var isAvailable: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
  }

  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func toggle() {
    do {
      if isEnabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      log.error("Launch-at-login toggle failed: \(String(describing: error), privacy: .public)")
    }
  }
}
