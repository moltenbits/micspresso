import AppKit
import MicspressoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var engine: KeepWarmEngine!
  private var monitor: CoreAudioInputMonitor!
  private var statusItemController: StatusItemController!
  private var settingsWindowController: SettingsWindowController!
  private var hotkeyManager: HotkeyManager!

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = UserDefaultsSettingsStore()
    monitor = CoreAudioInputMonitor()
    engine = KeepWarmEngine(
      provider: monitor,
      warmer: CoreAudioMicWarmer(),
      permission: AVCaptureMicPermission(),
      settings: settings,
      scheduler: MainQueueScheduler()
    )

    hotkeyManager = HotkeyManager()
    hotkeyManager.onToggle = { [weak self] in
      guard let self else { return }
      self.engine.setEnabled(!self.engine.isEnabled)
    }
    hotkeyManager.apply(settings.toggleShortcut)

    settingsWindowController = SettingsWindowController(settings: settings) {
      [weak self] shortcut in
      self?.hotkeyManager.apply(shortcut)
    }
    statusItemController = StatusItemController(engine: engine) { [weak self] in
      self?.settingsWindowController.show()
    }

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
