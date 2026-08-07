import Foundation

public final class UserDefaultsSettingsStore: SettingsStoring {
  private enum Key {
    static let enabled = "keepWarmEnabled"
    static let bluetoothOnly = "bluetoothOnly"
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var enabled: Bool {
    get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.enabled) }
  }

  public var bluetoothOnly: Bool {
    get { defaults.object(forKey: Key.bluetoothOnly) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.bluetoothOnly) }
  }
}
