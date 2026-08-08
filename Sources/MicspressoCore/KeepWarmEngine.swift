import Foundation
import os

public enum EngineState: Equatable {
  /// User has paused keeping warm.
  case paused
  /// System is asleep (or waking up and waiting for devices to settle).
  case asleep
  /// Waiting for the user to answer the microphone permission prompt.
  case awaitingPermission
  /// Microphone access denied; nothing can be warmed until granted.
  case permissionDenied
  /// No input device present at all.
  case noInputDevice
  /// Default input exists but isn't Bluetooth, so there's nothing to warm:
  /// wired and built-in mics have no wake-up delay, and holding them open
  /// would just light the privacy indicator for nothing.
  case ineligibleDevice(AudioInputDevice)
  /// Actively holding this device open.
  case warming(AudioInputDevice)
  /// Holding the device open failed; retrying with backoff.
  case warmingFailed(AudioInputDevice)
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
  private let log = Logger(subsystem: "com.moltenbits.micspresso", category: "engine")

  public var onStateChange: ((EngineState) -> Void)?
  public private(set) var state: EngineState = .paused {
    didSet {
      if state != oldValue {
        onStateChange?(state)
      }
    }
  }

  public var isEnabled: Bool { settings.enabled }

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
    debounceTimer?.cancel()
    debounceTimer = scheduler.schedule(after: timing.deviceSettleDelay) { [weak self] in
      guard let self else { return }
      self.debounceTimer = nil
      self.reconcile()
    }
  }

  /// Re-evaluates what should be warm and makes it so.
  public func reconcile() {
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

    guard let device = provider.defaultInputDevice else {
      stopWarming()
      state = .noInputDevice
      return
    }
    guard device.isBluetooth else {
      stopWarming()
      state = .ineligibleDevice(device)
      return
    }

    if warmer.warmedDeviceID == device.id {
      state = .warming(device)
      return
    }

    stopWarming()
    do {
      try warmer.startWarming(device: device)
      retryAttempts = 0
      resetHeartbeat()
      state = .warming(device)
      log.info("Keeping \(device.name, privacy: .public) warm")
    } catch {
      state = .warmingFailed(device)
      scheduleRetry()
      log.error(
        "Failed to warm \(device.name, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  private func stopWarming() {
    warmer.stopWarming()
    stalledHeartbeats = 0
  }

  private func scheduleRetry() {
    retryAttempts += 1
    let exponential = timing.retryBaseDelay * pow(2.0, Double(retryAttempts - 1))
    let delay = min(exponential, timing.retryMaxDelay)
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
      stalledHeartbeats = 0
      return
    }
    stalledHeartbeats += 1
    guard stalledHeartbeats >= timing.stalledTicksBeforeRestart else { return }

    log.warning("Warm session stalled (no IO callbacks); restarting")
    stopWarming()
    reconcile()
  }
}
