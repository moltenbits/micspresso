import AppKit
import MicspressoCore

switch CLIArgs.parse(Array(CommandLine.arguments.dropFirst())) {
case .version:
  print(AppInfo.version)
  exit(0)
case .help:
  print(CLIArgs.helpText)
  exit(0)
case .unknown(let argument):
  FileHandle.standardError.write(Data("Unknown option: \(argument)\n\n".utf8))
  print(CLIArgs.helpText)
  exit(64)
case .run:
  break
}

// Single-instance guard: two instances would each hold the mic open and
// fight over restarts. Accessory apps get no automatic protection here.
if let bundleID = Bundle.main.bundleIdentifier {
  let selfPID = ProcessInfo.processInfo.processIdentifier
  let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != selfPID && !$0.isTerminated }
  if let existing = running.first {
    print("Micspresso is already running (pid \(existing.processIdentifier)); exiting.")
    exit(0)
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
