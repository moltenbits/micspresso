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
    provider = MockAudioInputProvider(defaultInputDevice: .airPods())
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

  // MARK: - Warming and eligibility

  func testWarmsBluetoothDefaultInputOnStart() {
    engine.start()

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(warmer.startedDevices, [.airPods()])
  }

  func testSkipsBuiltInMicWhenBluetoothOnly() {
    provider.defaultInputDevice = .builtIn()

    engine.start()

    XCTAssertEqual(engine.state, .ineligibleDevice(.builtIn()))
    XCTAssertTrue(warmer.startedDevices.isEmpty)
  }

  func testWarmsBuiltInMicWhenPolicyAllowsAllDevices() {
    settings.bluetoothOnly = false
    provider.defaultInputDevice = .builtIn()

    engine.start()

    XCTAssertEqual(engine.state, .warming(.builtIn()))
    XCTAssertEqual(warmer.startedDevices, [.builtIn()])
  }

  func testNoInputDeviceGoesIdle() {
    provider.defaultInputDevice = nil

    engine.start()

    XCTAssertEqual(engine.state, .noInputDevice)
    XCTAssertTrue(warmer.startedDevices.isEmpty)
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

  // MARK: - Device changes (debounced)

  func testFollowsDefaultInputChangeAfterSettleDelay() {
    engine.start()

    provider.defaultInputDevice = .airPods(id: 99)
    engine.deviceEventOccurred()
    XCTAssertEqual(engine.state, .warming(.airPods()), "should not switch before settle delay")

    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPods(id: 99)))
    XCTAssertEqual(warmer.startedDevices.map(\.id), [42, 99])
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

  func testTransientNilDefaultInputDuringHandoffIsAbsorbed() {
    engine.start()

    // Bluetooth handoff: device momentarily vanishes, then returns.
    provider.defaultInputDevice = nil
    engine.deviceEventOccurred()
    provider.defaultInputDevice = .airPods()
    engine.deviceEventOccurred()

    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warming(.airPods()))
    XCTAssertEqual(warmer.startedDevices.count, 1, "same device should not be restarted")
    XCTAssertEqual(warmer.stopCount, 0)
  }

  func testDeviceDisappearanceStopsWarming() {
    engine.start()

    provider.defaultInputDevice = nil
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .noInputDevice)
    XCTAssertNil(warmer.warmedDeviceID)
    XCTAssertEqual(warmer.stopCount, 1)
  }

  func testSwitchToIneligibleDeviceStopsWarming() {
    engine.start()

    provider.defaultInputDevice = .builtIn()
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .ineligibleDevice(.builtIn()))
    XCTAssertNil(warmer.warmedDeviceID)
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

  func testPolicyChangeToBluetoothOnlyStopsWarmingWiredDevice() {
    settings.bluetoothOnly = false
    provider.defaultInputDevice = .usb()
    engine.start()
    XCTAssertEqual(engine.state, .warming(.usb()))

    engine.setBluetoothOnly(true)

    XCTAssertEqual(engine.state, .ineligibleDevice(.usb()))
    XCTAssertNil(warmer.warmedDeviceID)
    XCTAssertTrue(settings.bluetoothOnly)
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
    provider.defaultInputDevice = .airPods(id: 50)
    engine.deviceEventOccurred()
    scheduler.fireLastOneShot()

    XCTAssertEqual(engine.state, .warmingFailed(.airPods(id: 50)))
    XCTAssertEqual(scheduler.pendingOneShots.last?.delay, 1.0)
  }

  // MARK: - Heartbeat watchdog

  func testStalledDeliveryRestartsWarmingAfterTwoTicks() {
    engine.start()
    warmer.deliveryCount = 10
    scheduler.fireHeartbeat()  // records baseline advance

    // Delivery freezes (e.g. coreaudiod restarted).
    scheduler.fireHeartbeat()  // first stalled tick
    XCTAssertEqual(warmer.startedDevices.count, 1)

    scheduler.fireHeartbeat()  // second stalled tick -> restart

    XCTAssertEqual(warmer.stopCount, 1)
    XCTAssertEqual(warmer.startedDevices.count, 2)
    XCTAssertEqual(engine.state, .warming(.airPods()))
  }

  func testHealthyDeliveryNeverRestarts() {
    engine.start()

    for tick in 1...5 {
      warmer.deliveryCount = UInt64(tick * 100)
      scheduler.fireHeartbeat()
    }

    XCTAssertEqual(warmer.startedDevices.count, 1)
    XCTAssertEqual(warmer.stopCount, 0)
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
