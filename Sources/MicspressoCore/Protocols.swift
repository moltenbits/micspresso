import Foundation

/// Answers "which input devices exist right now?"
public protocol AudioInputProviding: AnyObject {
  /// Connected Bluetooth input devices, sorted by name.
  var bluetoothInputDevices: [AudioInputDevice] { get }
  /// The system default input device, used to auto-pick a mic when the
  /// user hasn't selected one.
  var defaultInputDevice: AudioInputDevice? { get }
}

/// Holds an input device open so it stays out of power-saving mode.
/// Implementations must never retain or inspect the captured audio.
public protocol MicWarming: AnyObject {
  /// The device currently being kept warm, if any.
  var warmedDeviceID: UInt32? { get }
  /// Monotonic count of IO callbacks delivered by the warmed device.
  /// Used by the engine's heartbeat to detect silently-dead sessions
  /// (e.g. after a coreaudiod restart, which gives no notification).
  var deliveryCount: UInt64 { get }
  func startWarming(device: AudioInputDevice) throws
  func stopWarming()
}

public enum MicPermissionStatus: Equatable {
  case undetermined
  case authorized
  case denied
}

public protocol MicPermissionChecking: AnyObject {
  var status: MicPermissionStatus { get }
  func request(_ completion: @escaping (Bool) -> Void)
}

public protocol SettingsStoring: AnyObject {
  /// Whether keeping warm is enabled at all (user pause/resume).
  var enabled: Bool { get set }
  /// UID of the mic the user chose to keep awake; nil means auto
  /// (prefer the default input, then the first available Bluetooth mic).
  var selectedMicUID: String? { get set }
  /// Global keyboard shortcut that toggles keep-awake; nil means none set.
  var toggleShortcut: ToggleShortcut? { get set }
}

public protocol EngineTimer: AnyObject {
  func cancel()
}

/// Timer scheduling seam so engine timing logic is unit-testable.
public protocol EngineScheduling: AnyObject {
  func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer
  func scheduleRepeating(every seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer
}
