import AppKit
import MicspressoCore
import SwiftUI

/// A click-to-record well for the global toggle shortcut.
struct ShortcutRecorderView: NSViewRepresentable {
  @Binding var shortcut: ToggleShortcut?

  func makeNSView(context: Context) -> ShortcutRecorderNSView {
    let view = ShortcutRecorderNSView()
    view.shortcut = shortcut
    view.onShortcutRecorded = { shortcut = $0 }
    return view
  }

  func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
    nsView.shortcut = shortcut
    nsView.updateDisplay()
  }
}

final class ShortcutRecorderNSView: NSView {
  var shortcut: ToggleShortcut?
  var onShortcutRecorded: ((ToggleShortcut) -> Void)?

  private var recording = false
  private let label = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  private func setup() {
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.borderWidth = 1

    label.translatesAutoresizingMaskIntoConstraints = false
    label.alignment = .center
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.isEditable = false
    label.isSelectable = false
    label.isBezeled = false
    label.drawsBackground = false
    addSubview(label)

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: 24),
      widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
    ])

    updateDisplay()
  }

  func updateDisplay() {
    if recording {
      label.stringValue = "Type shortcut (⌘/⌥/⌃ + key)"
      label.textColor = .selectedControlTextColor
      layer?.backgroundColor = NSColor.controlAccentColor.cgColor
      layer?.borderColor = NSColor.controlAccentColor.cgColor
    } else {
      label.stringValue = shortcut?.displayString ?? "Click to record"
      label.textColor = shortcut == nil ? .secondaryLabelColor : .labelColor
      layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
      layer?.borderColor = NSColor.separatorColor.cgColor
    }
  }

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    if !recording {
      recording = true
      window?.makeFirstResponder(self)
      updateDisplay()
    }
  }

  override func resignFirstResponder() -> Bool {
    if recording {
      recording = false
      updateDisplay()
    }
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    guard recording else {
      super.keyDown(with: event)
      return
    }

    // Escape cancels recording.
    if event.keyCode == 53 {
      recording = false
      updateDisplay()
      return
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
      return
    }

    recording = false
    shortcut = recorded
    onShortcutRecorded?(recorded)
    updateDisplay()
  }

  // Swallow key equivalents (⌘-based chords) while recording so they set
  // the shortcut instead of triggering menu items or beeping.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if recording {
      keyDown(with: event)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
