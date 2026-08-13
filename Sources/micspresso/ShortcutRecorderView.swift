import AppKit
import MicspressoCore
import SwiftUI

/// A click-to-record well for the global toggle shortcut.
///
/// Pure SwiftUI on purpose: an earlier AppKit-backed version resolved its
/// layer colors outside the window's appearance context (rendering black on
/// reopen) and its autolayout constraints fought LabeledContent's layout.
/// Key capture uses a local event monitor, active only while recording.
struct ShortcutRecorderView: View {
  @Binding var shortcut: ToggleShortcut?

  @State private var isRecording = false
  @State private var keyMonitor: Any?

  var body: some View {
    Button {
      isRecording ? stopRecording() : startRecording()
    } label: {
      Text(labelText)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(labelColor)
        .frame(minWidth: 130)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isRecording ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor))
        )
    }
    .buttonStyle(.plain)
    .onDisappear { stopRecording() }
    .onReceive(
      NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
    ) { _ in
      stopRecording()
    }
  }

  private var labelText: String {
    if isRecording {
      return "Type shortcut (⌘/⌥/⌃ + key)"
    }
    return shortcut?.displayString ?? "Click to record"
  }

  private var labelColor: Color {
    if isRecording {
      return .white
    }
    return shortcut == nil ? Color.secondary : Color.primary
  }

  private func startRecording() {
    isRecording = true
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handle(event) ? nil : event
    }
  }

  private func stopRecording() {
    isRecording = false
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  /// Returns true when the event was consumed by the recorder.
  private func handle(_ event: NSEvent) -> Bool {
    guard isRecording else { return false }

    // Escape cancels recording.
    if event.keyCode == 53 {
      stopRecording()
      return true
    }

    var modifiers: ToggleShortcut.Modifiers = []
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.shift) { modifiers.insert(.shift) }

    // Chords without a real modifier are rejected by the model; stay in
    // recording mode so the hint keeps showing what's expected.
    guard let recorded = ToggleShortcut(keyCode: event.keyCode, modifiers: modifiers) else {
      NSSound.beep()
      return true
    }

    shortcut = recorded
    stopRecording()
    return true
  }
}
