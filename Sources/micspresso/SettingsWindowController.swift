import AppKit
import MicspressoCore
import SwiftUI

/// Owns the (single) settings window.
final class SettingsWindowController {
  private var window: NSWindow?
  private let settings: SettingsStoring
  private let onShortcutChange: (ToggleShortcut?) -> Void

  init(settings: SettingsStoring, onShortcutChange: @escaping (ToggleShortcut?) -> Void) {
    self.settings = settings
    self.onShortcutChange = onShortcutChange
  }

  func show() {
    if let window, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      activateApp()
      return
    }

    let view = SettingsView(settings: settings, onShortcutChange: onShortcutChange)
    let hostingView = NSHostingView(rootView: view)
    let newWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = "Micspresso Settings"
    newWindow.contentView = hostingView
    newWindow.center()
    newWindow.isReleasedWhenClosed = false
    newWindow.makeKeyAndOrderFront(nil)
    activateApp()

    window = newWindow
  }

  private func activateApp() {
    // Accessory apps aren't frontmost when their menu is clicked; without
    // activation the window opens behind others.
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}

struct SettingsView: View {
  let settings: SettingsStoring
  let onShortcutChange: (ToggleShortcut?) -> Void

  var body: some View {
    TabView {
      GeneralPane(settings: settings, onShortcutChange: onShortcutChange)
        .tabItem { Label("General", systemImage: "gearshape") }
      AboutPane()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 420, height: 260)
  }
}

struct GeneralPane: View {
  let settings: SettingsStoring
  let onShortcutChange: (ToggleShortcut?) -> Void

  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var shortcut: ToggleShortcut?

  init(settings: SettingsStoring, onShortcutChange: @escaping (ToggleShortcut?) -> Void) {
    self.settings = settings
    self.onShortcutChange = onShortcutChange
    _shortcut = State(initialValue: settings.toggleShortcut)
  }

  var body: some View {
    Form {
      Section {
        Toggle("Launch at login", isOn: $launchAtLogin)
          .disabled(!LaunchAtLogin.isAvailable)
          .onChange(of: launchAtLogin) { _ in
            LaunchAtLogin.toggle()
            launchAtLogin = LaunchAtLogin.isEnabled
          }
      }

      Section {
        LabeledContent("Toggle shortcut") {
          HStack(spacing: 6) {
            ShortcutRecorderView(shortcut: $shortcut)
              .fixedSize()
            if shortcut != nil {
              Button {
                shortcut = nil
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .help("Remove shortcut")
            }
          }
        }
      } footer: {
        Text("Pauses or resumes Micspresso from anywhere.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onChange(of: shortcut) { newValue in
      settings.toggleShortcut = newValue
      onShortcutChange(newValue)
    }
  }
}

struct AboutPane: View {
  var body: some View {
    VStack(spacing: 8) {
      Spacer()

      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 64, height: 64)

      Text("Micspresso")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Version \(AppInfo.displayVersion)")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Keeps your Bluetooth mic awake so dictation starts instantly.")
        .font(.caption)
        .multilineTextAlignment(.center)

      HStack(spacing: 16) {
        Link("MoltenBits", destination: URL(string: "https://github.com/moltenbits")!)
        Link(
          "GitHub",
          destination: URL(string: "https://github.com/moltenbits/micspresso")!)
        Link(
          "MIT License",
          destination: URL(string: "https://github.com/moltenbits/micspresso/blob/main/LICENSE")!)
      }
      .font(.caption)

      Text("© 2026 MoltenBits")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}
