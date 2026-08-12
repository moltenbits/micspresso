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
    XCTAssertNil(store.toggleShortcut)
    XCTAssertFalse(store.debugLogging)
  }

  func testPersistsDebugLogging() {
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.debugLogging = true

    XCTAssertTrue(UserDefaultsSettingsStore(defaults: defaults).debugLogging)
  }

  func testPersistsToggleShortcut() {
    let store = UserDefaultsSettingsStore(defaults: defaults)
    store.toggleShortcut = ToggleShortcut(keyCode: 46, modifiers: [.command, .shift])

    let reloaded = UserDefaultsSettingsStore(defaults: defaults)
    XCTAssertEqual(
      reloaded.toggleShortcut, ToggleShortcut(keyCode: 46, modifiers: [.command, .shift]))

    reloaded.toggleShortcut = nil
    XCTAssertNil(UserDefaultsSettingsStore(defaults: defaults).toggleShortcut)
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
