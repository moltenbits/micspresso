import XCTest

@testable import MicspressoCore

final class ToggleShortcutTests: XCTestCase {
  func testRequiresARealModifier() {
    XCTAssertNil(ToggleShortcut(keyCode: 46, modifiers: []))
    XCTAssertNil(ToggleShortcut(keyCode: 46, modifiers: [.shift]))
    XCTAssertNotNil(ToggleShortcut(keyCode: 46, modifiers: [.command]))
    XCTAssertNotNil(ToggleShortcut(keyCode: 46, modifiers: [.option]))
    XCTAssertNotNil(ToggleShortcut(keyCode: 46, modifiers: [.control]))
    XCTAssertNotNil(ToggleShortcut(keyCode: 46, modifiers: [.shift, .command]))
  }

  func testDisplayStringUsesStandardModifierOrder() {
    let shortcut = ToggleShortcut(
      keyCode: 46, modifiers: [.command, .shift, .option, .control])
    XCTAssertEqual(shortcut?.displayString, "⌃⌥⇧⌘M")
  }

  func testDisplayStringForNamedKeys() {
    XCTAssertEqual(ToggleShortcut(keyCode: 49, modifiers: [.option])?.displayString, "⌥Space")
    XCTAssertEqual(ToggleShortcut(keyCode: 122, modifiers: [.command])?.displayString, "⌘F1")
    XCTAssertEqual(
      ToggleShortcut(keyCode: 200, modifiers: [.command])?.displayString, "⌘Key 200")
  }

  func testCarbonModifierMask() {
    XCTAssertEqual(ToggleShortcut(keyCode: 46, modifiers: [.command])?.carbonModifiers, 0x100)
    XCTAssertEqual(
      ToggleShortcut(keyCode: 46, modifiers: [.command, .shift])?.carbonModifiers, 0x300)
    XCTAssertEqual(
      ToggleShortcut(keyCode: 46, modifiers: [.control, .option])?.carbonModifiers, 0x1800)
  }
}
