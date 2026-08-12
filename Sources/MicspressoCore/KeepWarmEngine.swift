import Foundation

public enum EngineState: Equatable {
  /// User has paused keeping warm.
  case paused
  /// System is asleep (or waking up and waiting for devices to settle).
  case asleep
  /// Waiting for the user to answer the microphone permission prompt.
  case awaitingPermission
  /// Microphone access denied; nothing can be warmed until granted.
  case permissionDenied
  /// No Bluetooth mic connected, so there's nothing to keep awake: wired
  /// and built-in mics have no wake-up delay, and holding them open would
  /// just light the privacy indicator for nothing.
  case noBluetoothMic
  /// Actively holding this device open.
  case warming(AudioInputDevice)
  /// Holding the device open failed; retrying with backoff.
  case warmingFailed(AudioInputDevice)
}

extension EngineState {
  /// Compact form for the system log.
  public var logDescription: String {
    switch self {
    case .paused: return "paused"
    case .asleep: return "asleep"
    case .awaitingPermission: return "awaiting mic permission"
    case .permissionDenied: return "mic permission denied"
    case .noBluetoothMic: return "no Bluetooth mic"
    case .warming(let device): return "warming \(device.name) [\(device.id)]"
    case .warmingFailed(let device): return "warming failed on \(device.name) [\(device.id)]"
    }
  }
}

/// Timing knobs, injectable for tests.
public struct EngineTiming {
  /// How long to let device-change event storms settle before reacting.
  /// A single Bluetooth handoff fires several rapid HAL events, sometimes
  /// with a transient nil default device in the middle.
  public var deviceSettleDelay: TimeInterval = 2.0
  /// How often the heartbeat checks that IO callbacks are still flowing.
  public var heartbeatInterval: TimeInterval = 5.0
  /// Consecutive stalled heartbeats tolerated before restarting the warm
  /// session. coreaudiod restarts kill sessions without any notification,
  /// so a stalled delivery count is the only signal.
  public var stalledTicksBeforeRestart = 2
  public var retryBaseDelay: TimeInterval = 1.0
  public var retryMaxDelay: TimeInterval = 30.0

  public init() {}
}

/// Decides which device (if any) should be kept warm and drives the warmer
/// accordingly. Pure orchestration over injected seams; must be used from a
/// single thread (the main thread in the app).
public final class KeepWarmEngine {
  private let provider: AudioInputProviding
  private let warmer: MicWarming
  private let permission: MicPermissionChecking
  private let settings: SettingsStoring
  private let scheduler: EngineScheduling
  private let timing: EngineTiming
  private let log: DiagnosticsLog

  public var onStateChange: ((EngineState) -> Void)?
  public private(set) var state: EngineState = .paused {
    didSet {
      if state != oldValue {
        log.notice("State: \(state.logDescription)")
        onStateChange?(state)
      }
    }
  }

  public var isEnabled: Bool { settings.enabled }

  /// The connected Bluetooth mics to offer in the UI.
  public var availableMics: [AudioInputDevice] { provider.bluetoothInputDevices }

  private var isAsleep = false
  private var debounceTimer: EngineTimer?
  private var retryTimer: EngineTimer?
  private var heartbeatTimer: EngineTimer?
  private var retryAttempts = 0
  private var lastDeliveryCount: UInt64 = 0
  private var stalledHeartbeats = 0

  public init(
    provider: AudioInputProviding,
    warmer: MicWarming,
    permission: MicPermissionChecking,
    settings: SettingsStoring,
    scheduler: EngineScheduling,
    timing: EngineTiming = EngineTiming()
  ) {
    self.provider = provider
    self.warmer = warmer
    self.permission = permission
    self.settings = settings
    self.scheduler = scheduler
    self.timing = timing
    self.log = DiagnosticsLog(category: "engine", isVerbose: { settings.debugLogging })
  }

  public func start() {
    heartbeatTimer = scheduler.scheduleRepeating(every: timing.heartbeatInterval) { [weak self] in
      self?.heartbeatTick()
    }
    reconcile()
  }

  public func setEnabled(_ enabled: Bool) {
    settings.enabled = enabled
    reconcile()
  }

  /// Pins keeping-awake to the mic with this UID. The choice is remembered
  /// even while the mic is disconnected (another connected mic is warmed in
  /// the meantime) and applies again when it returns.
  public func selectMic(uid: String) {
    settings.selectedMicUID = uid
    reconcile()
  }

  public func systemWillSleep() {
    // Stop before the Bluetooth link dies with us attached — tearing down
    // a session on an already-dead device is where keep-warm tools
    // historically deadlocked.
    isAsleep = true
    reconcile()
  }

  public func systemDidWake() {
    isAsleep = false
    // Devices re-enumerate and Bluetooth re-handshakes after wake; treat
    // it like any other device-change storm and let things settle.
    deviceEventOccurred()
  }

  /// Called on any HAL device-list or default-input change. Debounced,
  /// because one physical change fires several events.
  public func deviceEventOccurred() {
    log.debug("Device change event; settling for \(timing.deviceSettleDelay)s")
    debounceTimer?.cancel()
    debounceTimer = scheduler.schedule(after: timing.deviceSettleDelay) { [weak self] in
      guard let self else { return }
      self.debounceTimer = nil
      // Device changes always rebuild the hold, even when the same device
      // resolves: AirPods multipoint hands the mic to a phone and back
      // while keeping the same AudioDeviceID, and a hold that lived
      // through that is a zombie on a dead link. Worse than useless — as
      // long as it runs, other apps join the dead IO cycle instead of
      // renegotiating the Bluetooth mic link, so the mic looks broken
      // system-wide until the hold is released.
      self.reconcile(rebuildingWarmHold: true)
    }
  }

  /// Re-evaluates what should be warm and makes it so.
  public func reconcile() {
    reconcile(rebuildingWarmHold: false)
  }

  private func reconcile(rebuildingWarmHold: Bool) {
    retryTimer?.cancel()
    retryTimer = nil

    guard settings.enabled else {
      stopWarming()
      state = .paused
      return
    }
    guard !isAsleep else {
      stopWarming()
      state = .asleep
      return
    }

    switch permission.status {
    case .denied:
      stopWarming()
      state = .permissionDenied
      return
    case .undetermined:
      stopWarming()
      state = .awaitingPermission
      permission.request { [weak self] _ in
        self?.reconcile()
      }
      return
    case .authorized:
      break
    }

    guard let device = resolveMic() else {
      stopWarming()
      state = .noBluetoothMic
      return
    }

    if warmer.warmedDeviceID == device.id {
      if !rebuildingWarmHold {
        state = .warming(device)
        return
      }
      log.notice("Rebuilding hold on \(device.name) after device changes")
    }

    stopWarming()
    do {
      try warmer.startWarming(device: device)
      retryAttempts = 0
      resetHeartbeat()
      state = .warming(device)
      log.notice("Holding \(device.name) [\(device.id)] open")
    } catch {
      state = .warmingFailed(device)
      scheduleRetry()
      log.error("Failed to hold \(device.name): \(error)")
    }
  }

  /// The mic that should be kept awake: the user's selection when connected,
  /// else the default input if it's one of the Bluetooth mics, else the
  /// first available one.
  private func resolveMic() -> AudioInputDevice? {
    let mics = provider.bluetoothInputDevices
    if let uid = settings.selectedMicUID, let selected = mics.first(where: { $0.uid == uid }) {
      return selected
    }
    if let defaultInput = provider.defaultInputDevice,
      let match = mics.first(where: { $0.uid == defaultInput.uid })
    {
      return match
    }
    return mics.first
  }

  private func stopWarming() {
    warmer.stopWarming()
    stalledHeartbeats = 0
  }

  private func scheduleRetry() {
    retryAttempts += 1
    let exponential = timing.retryBaseDelay * pow(2.0, Double(retryAttempts - 1))
    let delay = min(exponential, timing.retryMaxDelay)
    log.debug("Retrying in \(delay)s (attempt \(retryAttempts))")
    retryTimer = scheduler.schedule(after: delay) { [weak self] in
      self?.reconcile()
    }
  }

  private func resetHeartbeat() {
    lastDeliveryCount = warmer.deliveryCount
    stalledHeartbeats = 0
  }

  private func heartbeatTick() {
    guard case .warming = state else {
      stalledHeartbeats = 0
      return
    }
    let count = warmer.deliveryCount
    defer { lastDeliveryCount = count }

    guard count == lastDeliveryCount else {
      log.debug("Heartbeat: \(count) IO callbacks delivered")
      stalledHeartbeats = 0
      return
    }
    stalledHeartbeats += 1
    log.debug("Heartbeat: stalled at \(count) callbacks (\(stalledHeartbeats) ticks)")
    guard stalledHeartbeats >= timing.stalledTicksBeforeRestart else { return }

    log.warning("Warm session stalled (no IO callbacks); restarting")
    stopWarming()
    reconcile()
  }
}
