import AppKit
import MicspressoCore
import SwiftUI

/// Owns the (single) settings window.
final class SettingsWindowController {
  private var window: NSWindow?
  private let settings: SettingsStoring
  private let onShortcutChange: (ToggleShortcut?) -> Void
  private let activationCoordinator = SettingsActivationCoordinator()

  private static let windowWidth: CGFloat = 540
  private static let sidebarWidth: CGFloat = 150

  init(settings: SettingsStoring, onShortcutChange: @escaping (ToggleShortcut?) -> Void) {
    self.settings = settings
    self.onShortcutChange = onShortcutChange
  }

  func show() {
    activationCoordinator.settingsWillShow()

    if let window, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      activateApp()
      return
    }

    // Size the window so the tallest form pane fits without scrolling; the
    // sidebar and the About pane stretch to whatever height that yields.
    let contentWidth = Self.windowWidth - Self.sidebarWidth - 1
    func paneHeight<Pane: View>(_ pane: Pane) -> CGFloat {
      NSHostingView(
        rootView:
          pane
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: contentWidth)
      ).fittingSize.height
    }
    let height = max(
      paneHeight(GeneralPane(settings: settings, onShortcutChange: onShortcutChange)),
      paneHeight(LoggingPane(settings: settings)),
      320)

    let view = SettingsView(settings: settings, onShortcutChange: onShortcutChange)
    let newWindow = NSWindow(
      contentRect: NSRect(
        origin: .zero, size: NSSize(width: Self.windowWidth, height: height)),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = "Micspresso Settings"
    newWindow.delegate = activationCoordinator
    newWindow.contentView = NSHostingView(rootView: view)
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

// MARK: - Panes

enum SettingsPane: String, CaseIterable, Identifiable {
  case general
  case logging
  case about

  var id: String { rawValue }

  var label: String {
    switch self {
    case .general: return "General"
    case .logging: return "Logging"
    case .about: return "About"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .logging: return "doc.text"
    case .about: return "info.circle"
    }
  }
}

struct SettingsView: View {
  let settings: SettingsStoring
  let onShortcutChange: (ToggleShortcut?) -> Void

  @State private var selectedPane: SettingsPane = .general

  var body: some View {
    HStack(spacing: 0) {
      List(SettingsPane.allCases, selection: $selectedPane) { pane in
        Label(pane.label, systemImage: pane.icon)
          .tag(pane)
      }
      .listStyle(.sidebar)
      .frame(width: 150)

      Divider()

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch selectedPane {
    case .general:
      GeneralPane(settings: settings, onShortcutChange: onShortcutChange)
    case .logging:
      LoggingPane(settings: settings)
    case .about:
      AboutPane()
    }
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
        Text("Micspresso will start automatically when you log in.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        LabeledContent("Toggle shortcut") {
          HStack(spacing: 6) {
            ShortcutRecorderView(shortcut: $shortcut)
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

struct LoggingPane: View {
  let settings: SettingsStoring

  @State private var debugLogging: Bool
  @State private var logText = ""
  @State private var isLoading = false

  init(settings: SettingsStoring) {
    self.settings = settings
    _debugLogging = State(initialValue: settings.debugLogging)
  }

  var body: some View {
    Form {
      Section {
        Toggle("Verbose logging", isOn: $debugLogging)
          .onChange(of: debugLogging) { newValue in
            settings.debugLogging = newValue
          }
        Text("Writes detailed diagnostics to the system log.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        logView
          .frame(height: 200)
        HStack {
          Button {
            load()
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .disabled(isLoading)
          Spacer()
          Button("Save Logs…") {
            saveLogs()
          }
          .disabled(isLoading || logText.isEmpty)
        }
        Text("Micspresso's system log entries from the last 24 hours.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      if logText.isEmpty {
        load()
      }
    }
  }

  private var logView: some View {
    ScrollViewReader { proxy in
      ScrollView {
        Text(isLoading && logText.isEmpty ? "Loading logs…" : logText)
          .font(.system(size: 10, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        Color.clear.frame(height: 1).id("bottom")
      }
      .onChange(of: logText) { _ in
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
  }

  private func load() {
    isLoading = true
    SystemLogReader.fetch { text in
      logText = text
      isLoading = false
    }
  }

  private func saveLogs() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = SystemLogReader.suggestedFileName
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try logText.write(to: url, atomically: true, encoding: .utf8)
      } catch {
        DiagnosticsLog(category: "app").error("Saving logs failed: \(error)")
      }
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
