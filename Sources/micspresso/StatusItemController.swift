import AppKit
import MicspressoCore

final class StatusItemController: NSObject, NSMenuDelegate {
  private let engine: KeepWarmEngine
  private let openSettings: () -> Void
  private let statusItem: NSStatusItem
  private var currentState: EngineState = .paused

  init(engine: KeepWarmEngine, openSettings: @escaping () -> Void) {
    self.engine = engine
    self.openSettings = openSettings
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu

    update(for: engine.state)
  }

  func update(for state: EngineState) {
    currentState = state
    statusItem.button?.image = icon(for: state)
    statusItem.button?.toolTip = statusLine(for: state)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    let mics = engine.availableMics
    if !mics.isEmpty {
      for mic in mics {
        let item = NSMenuItem(title: mic.name, action: #selector(selectMic(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mic.uid
        if case .warming(let device) = currentState, device.uid == mic.uid {
          item.state = .on
        }
        menu.addItem(item)
      }
    }

    if let line = statusMenuLine(for: currentState) {
      let statusLineItem = NSMenuItem(title: line, action: nil, keyEquivalent: "")
      statusLineItem.isEnabled = false
      menu.addItem(statusLineItem)
    }

    if currentState == .permissionDenied {
      let openSettings = NSMenuItem(
        title: "Open Microphone Privacy Settings…",
        action: #selector(openPrivacySettings), keyEquivalent: "")
      openSettings.target = self
      menu.addItem(openSettings)
    }

    menu.addItem(.separator())

    let toggle = NSMenuItem(
      title: engine.isEnabled ? "Pause Micspresso" : "Resume Micspresso",
      action: #selector(toggleEnabled), keyEquivalent: "")
    toggle.target = self
    menu.addItem(toggle)

    menu.addItem(.separator())

    let settings = NSMenuItem(
      title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)

    menu.addItem(.separator())

    // Custom selector on purpose: on macOS Tahoe, AppKit auto-attaches an
    // SF Symbol to items with system-known selectors like terminate(_:),
    // which also indents every icon-less item in the same menu section.
    let quit = NSMenuItem(
      title: "Quit Micspresso", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  private func icon(for state: EngineState) -> NSImage {
    switch state {
    case .warming:
      return MenuBarIcon.active
    default:
      return MenuBarIcon.idle
    }
  }

  private func statusLine(for state: EngineState) -> String {
    switch state {
    case .warming(let device):
      return "Keeping \(device.name) awake"
    default:
      return statusMenuLine(for: state) ?? "Micspresso"
    }
  }

  /// The disabled explainer line in the menu; nil while warming, where the
  /// checkmark in the mic list already tells the story.
  private func statusMenuLine(for state: EngineState) -> String? {
    switch state {
    case .warming:
      return nil
    case .paused:
      return "Paused"
    case .asleep:
      return "Waiting for wake-up…"
    case .awaitingPermission:
      return "Waiting for microphone permission…"
    case .permissionDenied:
      return "Microphone access denied"
    case .noBluetoothMic:
      return "No Bluetooth mic connected"
    case .warmingFailed(let device):
      return "Can't hold \(device.name) — retrying…"
    }
  }

  @objc private func toggleEnabled() {
    engine.setEnabled(!engine.isEnabled)
  }

  @objc private func selectMic(_ sender: NSMenuItem) {
    guard let uid = sender.representedObject as? String else { return }
    engine.selectMic(uid: uid)
  }

  @objc private func showSettings() {
    openSettings()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  @objc private func openPrivacySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
