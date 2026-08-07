import XCTest

@testable import MicspressoCore

final class SettingsStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "MicspressoTests-\(name)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testDefaultsToEnabledAndBluetoothOnly() {
    let store = UserDefaultsSettingsStore(defaults: defaults)

    XCTAssertTrue(store.enabled)
    XCTAssertTrue(store.bluetoothOnly)
  }

  func testPersistsEnabled() {
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.enabled = false

    let reloaded = UserDefaultsSettingsStore(defaults: defaults)
    XCTAssertFalse(reloaded.enabled)
  }

  func testPersistsBluetoothOnly() {
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.bluetoothOnly = false

    let reloaded = UserDefaultsSettingsStore(defaults: defaults)
    XCTAssertFalse(reloaded.bluetoothOnly)
  }
}
