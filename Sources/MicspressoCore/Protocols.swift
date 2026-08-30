import Foundation

/// Answers "which input devices exist right now?"
public protocol AudioInputProviding: AnyObject {
  /// Connected Bluetooth input devices, sorted by name.
  var bluetoothInputDevices: [AudioInputDevice] { get }
  /// The system default input device, used to auto-pick a mic when the
  /// user hasn't selected one.
  var defaultInputDevice: AudioInputDevice? { get }
}

/// Bounded health metadata derived from the warmed input stream. No audio
/// samples are retained: the counters only distinguish callback delivery from
/// callbacks whose buffers contain at least one nonzero byte.
public struct MicDeliverySnapshot: Equatable {
  public let callbackCount: UInt64
  public let nonzeroCallbackCount: UInt64

  public init(callbackCount: UInt64 = 0, nonzeroCallbackCount: UInt64 = 0) {
    self.callbackCount = callbackCount
    self.nonzeroCallbackCount = nonzeroCallbackCount
  }
}

/// Holds an input device open so it stays out of power-saving mode.
/// Implementations must never retain, copy, log, or transmit captured audio.
/// They may inspect buffers only to derive bounded delivery-health metadata.
public protocol MicWarming: AnyObject {
  /// The device currently being kept warm, if any.
  var warmedDeviceID: UInt32? { get }
  /// Monotonic callback and signal-bearing callback counters used by the
  /// engine to detect both dead and all-zero sessions.
  var deliverySnapshot: MicDeliverySnapshot { get }
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
  /// Promote verbose diagnostics into the persisted system log.
  var debugLogging: Bool { get set }
}

public protocol EngineTimer: AnyObject {
  func cancel()
}

/// Timer scheduling seam so engine timing logic is unit-testable.
public protocol EngineScheduling: AnyObject {
  func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer
  func scheduleRepeating(every seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer
}
