import AppKit
import MicspressoCore

/// Exports Micspresso's system-log entries to a file and opens it in
/// Console.app. Console has no API for opening pre-filtered to a subsystem,
/// but it renders log files handed to it — so exporting just our entries
/// gets the same result.
enum LogViewer {
  private static let log = DiagnosticsLog(category: "app")

  static func exportAndOpen(completion: @escaping (Bool) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let fileURL: URL
      do {
        fileURL = try export()
      } catch {
        log.error("Log export failed: \(error)")
        DispatchQueue.main.async { completion(false) }
        return
      }
      DispatchQueue.main.async {
        openInConsole(fileURL)
        completion(true)
      }
    }
  }

  private static func export() throws -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Micspresso-logs-\(formatter.string(from: Date())).log")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
      "show",
      "--predicate", "subsystem == \"com.moltenbits.micspresso\"",
      "--last", "24h",
      "--info", "--debug",
      "--style", "compact",
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    // Drain before waiting so a large export can't deadlock on a full pipe.
    let output = try pipe.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()

    try output.write(to: fileURL)
    return fileURL
  }

  private static func openInConsole(_ fileURL: URL) {
    let console = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
    NSWorkspace.shared.open(
      [fileURL], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration()
    ) { _, error in
      if error != nil {
        // No Console at the expected path (unlikely) — fall back to Finder.
        DispatchQueue.main.async {
          NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
      }
    }
  }
}
