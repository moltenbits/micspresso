import Foundation

@testable import MicspressoCore

final class MockAudioInputProvider: AudioInputProviding {
  var bluetoothInputDevices: [AudioInputDevice]
  var defaultInputDevice: AudioInputDevice?

  init(
    bluetoothInputDevices: [AudioInputDevice] = [],
    defaultInputDevice: AudioInputDevice? = nil
  ) {
    self.bluetoothInputDevices = bluetoothInputDevices
    self.defaultInputDevice = defaultInputDevice
  }
}

final class MockMicWarmer: MicWarming {
  private(set) var warmedDeviceID: UInt32?
  var deliveryCount: UInt64 = 0

  private(set) var startedDevices: [AudioInputDevice] = []
  private(set) var stopCount = 0

  /// Errors to throw on successive startWarming calls; nil entries succeed.
  var startErrors: [Error?] = []
  private var startAttempts = 0

  func startWarming(device: AudioInputDevice) throws {
    let error = startAttempts < startErrors.count ? startErrors[startAttempts] : nil
    startAttempts += 1
    if let error { throw error }
    startedDevices.append(device)
    warmedDeviceID = device.id
  }

  func stopWarming() {
    guard warmedDeviceID != nil else { return }
    warmedDeviceID = nil
    stopCount += 1
  }
}

final class MockMicPermission: MicPermissionChecking {
  var status: MicPermissionStatus
  private(set) var requestCount = 0
  private var pendingCompletions: [(Bool) -> Void] = []

  init(status: MicPermissionStatus = .authorized) {
    self.status = status
  }

  func request(_ completion: @escaping (Bool) -> Void) {
    requestCount += 1
    pendingCompletions.append(completion)
  }

  func resolveRequests(granted: Bool) {
    status = granted ? .authorized : .denied
    let completions = pendingCompletions
    pendingCompletions = []
    for completion in completions {
      completion(granted)
    }
  }
}

final class MockSettingsStore: SettingsStoring {
  var enabled: Bool
  var selectedMicUID: String?
  var toggleShortcut: ToggleShortcut?
  var debugLogging = false

  init(enabled: Bool = true, selectedMicUID: String? = nil) {
    self.enabled = enabled
    self.selectedMicUID = selectedMicUID
  }
}

final class MockTimer: EngineTimer {
  let delay: TimeInterval
  let repeats: Bool
  let block: () -> Void
  private(set) var cancelled = false

  init(delay: TimeInterval, repeats: Bool, block: @escaping () -> Void) {
    self.delay = delay
    self.repeats = repeats
    self.block = block
  }

  func cancel() {
    cancelled = true
  }

  func fire() {
    guard !cancelled else { return }
    block()
  }
}

final class MockScheduler: EngineScheduling {
  private(set) var oneShots: [MockTimer] = []
  private(set) var repeating: [MockTimer] = []

  func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer {
    let timer = MockTimer(delay: seconds, repeats: false, block: block)
    oneShots.append(timer)
    return timer
  }

  func scheduleRepeating(every seconds: TimeInterval, _ block: @escaping () -> Void) -> EngineTimer
  {
    let timer = MockTimer(delay: seconds, repeats: true, block: block)
    repeating.append(timer)
    return timer
  }

  /// Pending (not-yet-cancelled) one-shot timers.
  var pendingOneShots: [MockTimer] { oneShots.filter { !$0.cancelled } }

  /// Fires the most recently scheduled pending one-shot.
  func fireLastOneShot() {
    pendingOneShots.last?.fire()
  }

  /// Fires one tick of the repeating heartbeat timer.
  func fireHeartbeat() {
    repeating.first?.fire()
  }
}

enum TestError: Error {
  case boom
}

extension AudioInputDevice {
  static func airPods(id: UInt32 = 42) -> AudioInputDevice {
    AudioInputDevice(id: id, uid: "airpods-uid-\(id)", name: "AirPods Pro", transport: .bluetooth)
  }

  static func airPodsMax(id: UInt32 = 77) -> AudioInputDevice {
    AudioInputDevice(id: id, uid: "airpodsmax-uid", name: "AirPods Max", transport: .bluetooth)
  }

  static func builtIn(id: UInt32 = 7) -> AudioInputDevice {
    AudioInputDevice(
      id: id, uid: "builtin-uid", name: "MacBook Pro Microphone", transport: .builtIn)
  }
}
