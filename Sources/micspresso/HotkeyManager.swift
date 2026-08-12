import Carbon.HIToolbox
import MicspressoCore

/// Registers the global toggle shortcut via Carbon's RegisterEventHotKey —
/// the one global-hotkey mechanism that needs no Accessibility or Input
/// Monitoring permission.
final class HotkeyManager {
  var onToggle: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private let log = DiagnosticsLog(category: "hotkey")

  init() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, _, userData in
      guard let userData else { return noErr }
      let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
      manager.log.notice("Global shortcut pressed; toggling")
      manager.onToggle?()
      return noErr
    }
    InstallEventHandler(
      GetApplicationEventTarget(), callback, 1, &eventType,
      Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
  }

  deinit {
    unregister()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  /// Registers `shortcut` as the global toggle, replacing any previous one.
  /// Pass nil to just unregister.
  func apply(_ shortcut: ToggleShortcut?) {
    unregister()
    guard let shortcut else { return }

    // The signature is the four-char code "MCSP".
    let hotKeyID = EventHotKeyID(signature: OSType(0x4D43_5350), id: 1)
    let status = RegisterEventHotKey(
      UInt32(shortcut.keyCode), shortcut.carbonModifiers, hotKeyID,
      GetApplicationEventTarget(), 0, &hotKeyRef)
    if status == noErr {
      log.notice("Registered global shortcut \(shortcut.displayString)")
    } else {
      log.error(
        "Could not register global shortcut \(shortcut.displayString) (OSStatus \(status))")
    }
  }

  private func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
  }
}
