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

    let statusLineItem = NSMenuItem(
      title: statusLine(for: currentState), action: nil, keyEquivalent: "")
    statusLineItem.isEnabled = false
    menu.addItem(statusLineItem)

    if currentState == .permissionDenied {
      let openSettings = NSMenuItem(
        title: "Open Microphone Privacy Settings…",
        action: #selector(openPrivacySettings), keyEquivalent: "")
      openSettings.target = self
      menu.addItem(openSettings)
    }

    menu.addItem(.separator())

    let toggle = NSMenuItem(
      title: engine.isEnabled ? "Pause Keeping Warm" : "Resume Keeping Warm",
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

    let version = NSMenuItem(
      title: "Micspresso \(AppInfo.version)", action: nil, keyEquivalent: "")
    version.isEnabled = false
    menu.addItem(version)

    let quit = NSMenuItem(
      title: "Quit Micspresso", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
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
    case .paused:
      return "Paused"
    case .asleep:
      return "Waiting for wake-up…"
    case .awaitingPermission:
      return "Waiting for microphone permission…"
    case .permissionDenied:
      return "Microphone access denied"
    case .noInputDevice:
      return "No input device found"
    case .ineligibleDevice(let device):
      return "\(device.name) isn't Bluetooth — not warming"
    case .warming(let device):
      return "Keeping \(device.name) warm"
    case .warmingFailed(let device):
      return "Can't hold \(device.name) — retrying…"
    }
  }

  @objc private func toggleEnabled() {
    engine.setEnabled(!engine.isEnabled)
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
