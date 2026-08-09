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

  func testDefaultsToEnabledWithNoSelection() {
    let store = UserDefaultsSettingsStore(defaults: defaults)

    XCTAssertTrue(store.enabled)
    XCTAssertNil(store.selectedMicUID)
  }

  func testPersistsSelectedMicUID() {
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.selectedMicUID = "airpods-uid"

    let reloaded = UserDefaultsSettingsStore(defaults: defaults)
    XCTAssertEqual(reloaded.selectedMicUID, "airpods-uid")

    reloaded.selectedMicUID = nil
    XCTAssertNil(UserDefaultsSettingsStore(defaults: defaults).selectedMicUID)
  }

  func testPersistsEnabled() {
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.enabled = false

    let reloaded = UserDefaultsSettingsStore(defaults: defaults)
    XCTAssertFalse(reloaded.enabled)
  }
}
