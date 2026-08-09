import Foundation

/// A global keyboard shortcut for toggling keep-awake on and off.
public struct ToggleShortcut: Equatable {
  public struct Modifiers: OptionSet, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
  }

  public let keyCode: UInt16
  public let modifiers: Modifiers

  /// Fails without at least one of ⌘/⌥/⌃ — a bare or shift-only key would
  /// hijack normal typing system-wide.
  public init?(keyCode: UInt16, modifiers: Modifiers) {
    guard !modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Rendered in the standard macOS modifier order: ⌃⌥⇧⌘.
  public var displayString: String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    return text + Self.keyName(for: keyCode)
  }

  /// Carbon modifier mask for RegisterEventHotKey. Raw values are the
  /// (stable-since-forever) HIToolbox constants, spelled out here to keep
  /// Carbon out of the core module.
  public var carbonModifiers: UInt32 {
    var mask: UInt32 = 0
    if modifiers.contains(.command) { mask |= 0x100 }  // cmdKey
    if modifiers.contains(.shift) { mask |= 0x200 }  // shiftKey
    if modifiers.contains(.option) { mask |= 0x800 }  // optionKey
    if modifiers.contains(.control) { mask |= 0x1000 }  // controlKey
    return mask
  }

  public static func keyName(for keyCode: UInt16) -> String {
    keyNames[keyCode] ?? "Key \(keyCode)"
  }

  private static let keyNames: [UInt16: String] = [
    // Navigation
    48: "Tab", 49: "Space", 36: "Return", 76: "Enter",
    51: "Delete", 117: "Forward Delete",

    // Arrows
    123: "←", 124: "→", 125: "↓", 126: "↑",

    // Letters
    0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
    34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
    35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
    13: "W", 7: "X", 16: "Y", 6: "Z",

    // Numbers
    29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
    22: "6", 26: "7", 28: "8", 25: "9",

    // Punctuation
    50: "`", 27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
    41: ";", 39: "'", 43: ",", 47: ".", 44: "/",

    // F-keys
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
  ]
}
