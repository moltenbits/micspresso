import XCTest

@testable import MicspressoCore

final class KeepWarmEngineTests: XCTestCase {
  private var provider: MockAudioInputProvider!
  private var warmer: MockMicWarmer!
  private var permission: MockMicPermission!
  private var settings: MockSettingsStore!
  private var scheduler: MockScheduler!
  private var engine: KeepWarmEngine!
  private var stateChanges: [EngineState] = []

  override func setUp() {
    super.setUp()
    provider = MockAudioInputProvider(
      bluetoothInputDevices: [.airPods()],
      defaultInputDevice: .airPods()
    )
    warmer = MockMicWarmer()
    permission = MockMicPermission(status: .authorized)
    settings = MockSettingsStore()
    scheduler = MockScheduler()
    stateChanges = []
    engine = KeepWarmEngine(
      provider: provider,
      warmer: warmer,
      permission: permission,
      settings: settings,
      scheduler: scheduler
    )
    engine.onStateChange = { [weak self] in self?.stateChanges.append($0) }
  }

  // MARK: - Warming and mic resolution

  func testWarmsBluetoothDefaultInputOnStart() {
    engine.start()

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(warmer.startedDevices, [.airPods()])
  }

  func testNoBluetoothMicsGoesIdle() {
    provider.bluetoothInputDevices = []
    provider.defaultInputDevice = .builtIn()

    engine.start()

    XCTAssertEqual(engine.state, .noBluetoothMic)
    XCTAssertTrue(warmer.startedDevices.isEmpty)
  }

  func testWarmsFirstBluetoothMicWhenDefaultInputIsNotBluetooth() {
    provider.bluetoothInputDevices = [.airPodsMax(), .airPods()]
    provider.defaultInputDevice = .builtIn()

    engine.start()

    XCTAssertEqual(engine.state, .warming(.airPodsMax()))
  }

  func testDefaultInputPreferredOverListOrder() {
    provider.bluetoothInputDevices = [.airPodsMax(), .airPods()]
    provider.defaultInputDevice = .airPods()

    engine.start()

    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  func testStartsPausedWhenDisabledInSettings() {
    settings.enabled = false

    engine.start()

    XCTAssertEqual(engine.state, .paused)
    XCTAssertTrue(warmer.startedDevices.isEmpty)
  }

  func testReconcileWithSameDeviceDoesNotRestart() {
    engine.start()
    engine.reconcile()

    XCTAssertEqual(warmer.startedDevices.count, 1)
    XCTAssertEqual(warmer.stopCount, 0)
  }

  func testAvailableMicsComeFromProvider() {
    provider.bluetoothInputDevices = [.airPodsMax(), .airPods()]

    XCTAssertEqual(engine.availableMics, [.airPodsMax(), .airPods()])
  }

  // MARK: - Mic selection

  func testSelectingMicSwitchesWarmingAndPersists() {
    provider.bluetoothInputDevices = [.airPods(), .airPodsMax()]
    provider.defaultInputDevice = .airPods()
    engine.start()
    XCTAssertEqual(engine.state, .warming(.airPods()))

    engine.selectMic(uid: AudioInputDevice.airPodsMax().uid)

    XCTAssertEqual(engine.state, .warming(.airPodsMax()))
    XCTAssertEqual(
      warmer.startedDevices.map(\.uid),
      [AudioInputDevice.airPods().uid, AudioInputDevice.airPodsMax().uid])
    XCTAssertEqual(settings.selectedMicUID, AudioInputDevice.airPodsMax().uid)
  }

  func testSelectedMicOverridesDefaultInput() {
    settings.selectedMicUID = AudioInputDevice.airPodsMax().uid
    provider.bluetoothInputDevices = [.airPods(), .airPodsMax()]
    provider.defaultInputDevice = .airPods()

    engine.start()

    XCTAssertEqual(engine.state, .warming(.airPodsMax()))
  }

  func testDisconnectedSelectionFallsBackToConnectedMic() {
    settings.selectedMicUID = AudioInputDevice.airPodsMax().uid
    provider.bluetoothInputDevices = [.airPods()]
    provider.defaultInputDevice = nil

    engine.start()

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(
      settings.selectedMicUID, AudioInputDevice.airPodsMax().uid,
      "selection should be remembered for when the mic reconnects")
  }

  func testSelectionAppliesAgainWhenMicReconnects() {
    settings.selectedMicUID = AudioInputDevice.airPodsMax().uid
    provider.bluetoothInputDevices = [.airPods()]
    engine.start()
    XCTAssertEqual(engine.state, .warming(.airPods()))

    provider.bluetoothInputDevices = [.airPods(), .airPodsMax()]
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPodsMax()))
  }

  // MARK: - Device changes (debounced)

  func testFollowsDefaultInputChangeAfterSettleDelay() {
    provider.bluetoothInputDevices = [.airPods(), .airPodsMax()]
    provider.defaultInputDevice = .airPods()
    engine.start()

    provider.defaultInputDevice = .airPodsMax()
    engine.deviceEventOccurred()
    XCTAssertEqual(engine.state, .warming(.airPods()), "should not switch before settle delay")

    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPodsMax()))
    XCTAssertEqual(warmer.stopCount, 1)
  }

  func testRapidDeviceEventsCoalesceIntoOneReconcile() {
    engine.start()
    let initialTimerCount = scheduler.oneShots.count

    engine.deviceEventOccurred()
    engine.deviceEventOccurred()
    engine.deviceEventOccurred()

    XCTAssertEqual(scheduler.oneShots.count - initialTimerCount, 3)
    XCTAssertEqual(
      scheduler.pendingOneShots.count, 1, "earlier debounce timers should be cancelled")
  }

  func testDeviceEventRebuildsHoldEvenForSameDevice() {
    engine.start()
    XCTAssertEqual(warmer.startedDevices.count, 1)

    // AirPods multipoint: a phone call takes the AirPods and gives them
    // back with the same AudioDeviceID. A hold that lived through that is
    // a zombie attached to a dead link — and it blocks every other app's
    // mic from renegotiating — so the settle reconcile must always rebuild.
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(warmer.stopCount, 1)
    XCTAssertEqual(warmer.startedDevices.count, 2)
  }

  func testDeviceEventStormRebuildsHoldExactlyOnce() {
    engine.start()

    // Bluetooth handoff: device momentarily vanishes, then returns. The
    // debounce absorbs the storm into a single rebuild.
    provider.bluetoothInputDevices = []
    provider.defaultInputDevice = nil
    engine.deviceEventOccurred()
    provider.bluetoothInputDevices = [.airPods()]
    provider.defaultInputDevice = .airPods()
    engine.deviceEventOccurred()

    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(warmer.stopCount, 1)
    XCTAssertEqual(warmer.startedDevices.count, 2)
  }

  func testDeviceDisappearanceStopsWarming() {
    engine.start()

    provider.bluetoothInputDevices = []
    provider.defaultInputDevice = nil
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .noBluetoothMic)
    XCTAssertNil(warmer.warmedDeviceID)
    XCTAssertEqual(warmer.stopCount, 1)
  }

  // MARK: - Pause / resume

  func testPauseStopsWarming() {
    engine.start()

    engine.setEnabled(false)

    XCTAssertEqual(engine.state, .paused)
    XCTAssertNil(warmer.warmedDeviceID)
    XCTAssertFalse(settings.enabled)
  }

  func testResumeRewarms() {
    engine.start()
    engine.setEnabled(false)

    engine.setEnabled(true)

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(warmer.startedDevices.count, 2)
  }

  // MARK: - Sleep / wake

  func testSleepStopsWarming() {
    engine.start()

    engine.systemWillSleep()

    XCTAssertEqual(engine.state, .asleep)
    XCTAssertNil(warmer.warmedDeviceID)
  }

  func testWakeRewarnsAfterSettleDelay() {
    engine.start()
    engine.systemWillSleep()

    engine.systemDidWake()
    XCTAssertEqual(engine.state, .asleep, "should wait for devices to settle after wake")
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  // MARK: - Permission

  func testUndeterminedPermissionRequestsThenWarmsWhenGranted() {
    permission.status = .undetermined

    engine.start()

    XCTAssertEqual(engine.state, .awaitingPermission)
    XCTAssertEqual(permission.requestCount, 1)
    XCTAssertTrue(warmer.startedDevices.isEmpty)

    permission.resolveRequests(granted: true)

    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  func testDeniedPermissionNeverStartsWarming() {
    permission.status = .denied

    engine.start()

    XCTAssertEqual(engine.state, .permissionDenied)
    XCTAssertTrue(warmer.startedDevices.isEmpty)
  }

  func testPermissionRequestDeniedGoesToDeniedState() {
    permission.status = .undetermined
    engine.start()

    permission.resolveRequests(granted: false)

    XCTAssertEqual(engine.state, .permissionDenied)
    XCTAssertTrue(warmer.startedDevices.isEmpty)
  }

  func testPermissionNotRequestedWhilePaused() {
    settings.enabled = false
    permission.status = .undetermined

    engine.start()

    XCTAssertEqual(engine.state, .paused)
    XCTAssertEqual(permission.requestCount, 0)
  }

  // MARK: - Start failure and retry

  func testStartFailureSchedulesRetryWithBackoff() {
    warmer.startErrors = [TestError.boom, TestError.boom, nil]

    engine.start()

    XCTAssertEqual(engine.state, .warmingFailed(.airPods()))
    let firstRetry = scheduler.pendingOneShots.last
    XCTAssertEqual(firstRetry?.delay, 1.0)

    firstRetry?.fire()
    XCTAssertEqual(engine.state, .warmingFailed(.airPods()))
    let secondRetry = scheduler.pendingOneShots.last
    XCTAssertEqual(secondRetry?.delay, 2.0, "retry delay should back off")

    secondRetry?.fire()
    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  func testRetryBackoffIsCapped() {
    warmer.startErrors = Array(repeating: TestError.boom, count: 10)

    engine.start()
    for _ in 0..<9 {
      scheduler.fireLastOneShot()
    }

    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 30.0)
  }

  func testSuccessfulWarmResetsBackoff() {
    warmer.startErrors = [TestError.boom, nil, TestError.boom]

    engine.start()
    scheduler.fireLastOneShot()
    XCTAssertEqual(engine.state, .warming(.airPods()))

    // Force a restart that fails again: backoff should start over at 1s.
    provider.bluetoothInputDevices = [.airPods(id: 50)]
    provider.defaultInputDevice = .airPods(id: 50)
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warmingFailed(.airPods(id: 50)))
    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 1.0)
  }

  // MARK: - Heartbeat watchdog

  func testStalledDeliveryReleasesWarmingAfterTwoTicksAndReacquiresAfterCooldown() {
    engine.start()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 10, nonzeroCallbackCount: 10)
    scheduler.fireHeartbeat()  // records baseline advance

    // Delivery freezes (e.g. coreaudiod restarted).
    scheduler.fireHeartbeat()  // first stalled tick
    XCTAssertEqual(warmer.startedDevices.count, 1)

    scheduler.fireHeartbeat()  // second stalled tick -> release

    XCTAssertEqual(warmer.stopCount, 1)
    XCTAssertEqual(warmer.startedDevices.count, 1, "device must remain released during cooldown")
    XCTAssertEqual(engine.state, .warmingFailed(.airPods()))
    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 2.0)

    scheduler.fireLastOneShot()

    XCTAssertEqual(warmer.startedDevices.count, 2)
    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  func testHealthyDeliveryNeverRestarts() {
    engine.start()

    for tick in 1...5 {
      warmer.deliverySnapshot = MicDeliverySnapshot(
        callbackCount: UInt64(tick * 100), nonzeroCallbackCount: UInt64(tick))
      scheduler.fireHeartbeat()
    }

    XCTAssertEqual(warmer.startedDevices.count, 1)
    XCTAssertEqual(warmer.stopCount, 0)
  }

  func testAllZeroDeliveryReleasesDeviceAndReacquiresAfterCooldown() {
    engine.start()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 100, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    XCTAssertEqual(warmer.stopCount, 0)

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 200, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()

    XCTAssertEqual(warmer.stopCount, 1)
    XCTAssertNil(warmer.warmedDeviceID)
    XCTAssertEqual(warmer.startedDevices.count, 1, "recovery must include a released interval")
    XCTAssertEqual(engine.state, .warmingFailed(.airPods()))
    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 2.0)

    scheduler.fireLastOneShot()

    XCTAssertEqual(warmer.startedDevices.count, 2)
    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  func testNonzeroDeliveryResetsAllZeroDetection() {
    engine.start()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 100, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 200, nonzeroCallbackCount: 1)
    scheduler.fireHeartbeat()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 300, nonzeroCallbackCount: 1)
    scheduler.fireHeartbeat()
    XCTAssertEqual(warmer.stopCount, 0, "first zero-only interval after signal must be tolerated")

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 400, nonzeroCallbackCount: 1)
    scheduler.fireHeartbeat()
    XCTAssertEqual(warmer.stopCount, 1)
  }

  func testUnhealthySessionRecoveryBacksOffUntilSignalReturns() {
    engine.start()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 100, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 200, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 2.0)
    scheduler.fireLastOneShot()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 300, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 400, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 4.0)
    scheduler.fireLastOneShot()

    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 500, nonzeroCallbackCount: 1)
    scheduler.fireHeartbeat()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 600, nonzeroCallbackCount: 1)
    scheduler.fireHeartbeat()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 700, nonzeroCallbackCount: 1)
    scheduler.fireHeartbeat()

    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 2.0)
  }

  func testUnhealthySessionRecoveryBackoffIsCapped() {
    engine.start()
    var callbackCount: UInt64 = 0

    for expectedDelay in [2.0, 4.0, 8.0, 16.0, 30.0, 30.0] {
      callbackCount += 100
      warmer.deliverySnapshot = MicDeliverySnapshot(
        callbackCount: callbackCount, nonzeroCallbackCount: 0)
      scheduler.fireHeartbeat()
      callbackCount += 100
      warmer.deliverySnapshot = MicDeliverySnapshot(
        callbackCount: callbackCount, nonzeroCallbackCount: 0)
      scheduler.fireHeartbeat()

      XCTAssertEqual(scheduler.pendingOneShots.last?.delay, expectedDelay)
      scheduler.fireLastOneShot()
    }
  }

  func testPausingCancelsPendingHealthRecovery() {
    engine.start()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 100, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    warmer.deliverySnapshot = MicDeliverySnapshot(callbackCount: 200, nonzeroCallbackCount: 0)
    scheduler.fireHeartbeat()
    let recoveryTimer = scheduler.pendingOneShots.last

    engine.setEnabled(false)
    recoveryTimer?.fire()

    XCTAssertTrue(recoveryTimer?.cancelled == true)
    XCTAssertEqual(engine.state, .paused)
    XCTAssertEqual(warmer.startedDevices.count, 1)
  }

  func testHeartbeatIgnoredWhenNotWarming() {
    settings.enabled = false
    engine.start()

    scheduler.fireHeartbeat()
    scheduler.fireHeartbeat()
    scheduler.fireHeartbeat()

    XCTAssertTrue(warmer.startedDevices.isEmpty)
  }

  // MARK: - State change notifications

  func testStateChangesAreNotified() {
    engine.start()
    engine.setEnabled(false)
    engine.setEnabled(true)

    XCTAssertEqual(
      stateChanges,
      [.warming(.airPods()), .paused, .warming(.airPods())]
    )
  }

  func testUnchangedStateIsNotRenotified() {
    engine.start()
    engine.reconcile()
    engine.reconcile()

    XCTAssertEqual(stateChanges, [.warming(.airPods())])
  }
}
