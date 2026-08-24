import AppKit
import MicspressoCore

protocol ApplicationActivationPolicySetting: AnyObject {
  @discardableResult
  func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
}

extension NSApplication: ApplicationActivationPolicySetting {}

/// Keeps Micspresso in Command-Tab while Settings is open without making the
/// menu-bar-only process permanently visible in the Dock.
final class SettingsActivationCoordinator: NSObject, NSWindowDelegate {
  private let application: ApplicationActivationPolicySetting
  private let log = DiagnosticsLog(category: "app")

  init(application: ApplicationActivationPolicySetting = NSApplication.shared) {
    self.application = application
  }

  func settingsWillShow() {
    setActivationPolicy(.regular)
  }

  func windowWillClose(_ notification: Notification) {
    setActivationPolicy(.accessory)
  }

  private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
    guard application.setActivationPolicy(policy) else {
      log.error("Failed to change application activation policy to \(String(describing: policy))")
      return
    }
  }
}
