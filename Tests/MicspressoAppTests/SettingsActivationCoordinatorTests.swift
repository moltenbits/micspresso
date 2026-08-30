import AppKit
import XCTest

@testable import micspresso

final class SettingsActivationCoordinatorTests: XCTestCase {
  func testShowingSettingsMakesApplicationRegular() {
    let application = MockActivationPolicyApplication()
    let coordinator = SettingsActivationCoordinator(application: application)

    coordinator.settingsWillShow()

    XCTAssertEqual(application.policies, [.regular])
  }

  func testClosingSettingsRestoresAccessoryPolicy() {
    let application = MockActivationPolicyApplication()
    let coordinator = SettingsActivationCoordinator(application: application)

    coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification))

    XCTAssertEqual(application.policies, [.accessory])
  }
}

private final class MockActivationPolicyApplication: ApplicationActivationPolicySetting {
  private(set) var policies: [NSApplication.ActivationPolicy] = []

  func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
    policies.append(activationPolicy)
    return true
  }
}
