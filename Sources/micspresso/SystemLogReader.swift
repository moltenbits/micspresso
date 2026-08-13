import Foundation
import MicspressoCore

/// Reads Micspresso's entries back out of the unified system log.
enum SystemLogReader {
  private static let log = DiagnosticsLog(category: "app")

  /// Fetches the last 24 hours of Micspresso's log entries off the main
  /// thread and delivers the text on the main queue.
  static func fetch(completion: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let text: String
      do {
        text = try readEntries()
      } catch {
        log.error("Log fetch failed: \(error)")
        text = "Could not read the system log: \(error.localizedDescription)"
      }
      DispatchQueue.main.async { completion(text) }
    }
  }

  static var suggestedFileName: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return "Micspresso-logs-\(formatter.string(from: Date())).log"
  }

  private static func readEntries() throws -> String {
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
    return String(decoding: output, as: UTF8.self)
  }
}
