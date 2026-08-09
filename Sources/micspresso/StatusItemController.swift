import AppKit
import MicspressoCore

final class StatusItemController: NSObject, NSMenuDelegate {
  private let engine: KeepWarmEngine
  private let statusItem: NSStatusItem
  private var currentState: EngineState = .paused

  init(engine: KeepWarmEngine) {
    self.engine = engine
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
      let header = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)

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
      title: engine.isEnabled ? "Pause Keeping Awake" : "Resume Keeping Awake",
      action: #selector(toggleEnabled), keyEquivalent: "")
    toggle.target = self
    menu.addItem(toggle)

    menu.addItem(.separator())

    let launchAtLogin = NSMenuItem(
      title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchAtLogin.target = self
    launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
    launchAtLogin.isEnabled = LaunchAtLogin.isAvailable
    menu.addItem(launchAtLogin)

    menu.addItem(.separator())

    let about = NSMenuItem(
      title: "About Micspresso", action: #selector(showAbout), keyEquivalent: "")
    about.target = self
    menu.addItem(about)

    // Custom selector on purpose: on macOS Tahoe, AppKit auto-attaches an
    // SF Symbol to items with system-known selectors like terminate(_:),
    // which also indents every icon-less item in the same menu section.
    let quit = NSMenuItem(
      title: "Quit Micspresso", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  private func icon(for state: EngineState) -> NSImage? {
    let symbolName: String
    switch state {
    case .warming:
      symbolName = "cup.and.saucer.fill"
    default:
      symbolName = "cup.and.saucer"
    }
    let image =
      NSImage(systemSymbolName: symbolName, accessibilityDescription: "Micspresso")
      ?? NSImage(
        systemSymbolName: state == .paused ? "mic" : "mic.fill",
        accessibilityDescription: "Micspresso")
    image?.isTemplate = true
    return image
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

  @objc private func showAbout() {
    AboutPanel.show()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  @objc private func toggleLaunchAtLogin() {
    LaunchAtLogin.toggle()
  }

  @objc private func openPrivacySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
