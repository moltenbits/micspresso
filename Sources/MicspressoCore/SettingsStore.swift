import Foundation

public final class UserDefaultsSettingsStore: SettingsStoring {
  private enum Key {
    static let enabled = "keepWarmEnabled"
    static let selectedMicUID = "selectedMicUID"
    static let shortcutKeyCode = "toggleShortcutKeyCode"
    static let shortcutModifiers = "toggleShortcutModifiers"
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var enabled: Bool {
    get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.enabled) }
  }

  public var selectedMicUID: String? {
    get { defaults.string(forKey: Key.selectedMicUID) }
    set { defaults.set(newValue, forKey: Key.selectedMicUID) }
  }

  public var toggleShortcut: ToggleShortcut? {
    get {
      guard let keyCode = defaults.object(forKey: Key.shortcutKeyCode) as? Int,
        let rawModifiers = defaults.object(forKey: Key.shortcutModifiers) as? Int
      else { return nil }
      return ToggleShortcut(
        keyCode: UInt16(keyCode), modifiers: ToggleShortcut.Modifiers(rawValue: rawModifiers))
    }
    set {
      if let shortcut = newValue {
        defaults.set(Int(shortcut.keyCode), forKey: Key.shortcutKeyCode)
        defaults.set(shortcut.modifiers.rawValue, forKey: Key.shortcutModifiers)
      } else {
        defaults.removeObject(forKey: Key.shortcutKeyCode)
        defaults.removeObject(forKey: Key.shortcutModifiers)
      }
    }
  }
}
