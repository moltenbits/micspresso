import AppKit
import MicspressoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var engine: KeepWarmEngine!
  private var monitor: CoreAudioInputMonitor!
  private var statusItemController: StatusItemController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    monitor = CoreAudioInputMonitor()
    engine = KeepWarmEngine(
      provider: monitor,
      warmer: CoreAudioMicWarmer(),
      permission: AVCaptureMicPermission(),
      settings: UserDefaultsSettingsStore(),
      scheduler: MainQueueScheduler()
    )
    statusItemController = StatusItemController(engine: engine)

    engine.onStateChange = { [weak self] state in
      self?.statusItemController.update(for: state)
    }
    monitor.onChange = { [weak self] in
      self?.engine.deviceEventOccurred()
    }
    monitor.startMonitoring()

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.engine.systemWillSleep()
    }
    workspaceCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.engine.systemDidWake()
    }

    engine.start()
  }

  // No teardown on quit: process exit is the safest way to release the
  // device (deliberate — see keep-warm teardown deadlock history).
}
