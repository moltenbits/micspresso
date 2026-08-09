import Foundation

public enum CLICommand: Equatable {
  case run
  case version
  case help
  case unknown(String)
}

public enum CLIArgs {
  public static func parse(_ arguments: [String]) -> CLICommand {
    guard let first = arguments.first else { return .run }
    switch first {
    case "--version", "-v": return .version
    case "--help", "-h": return .help
    default: return .unknown(first)
    }
  }

  public static let helpText = """
    micspresso — keeps your microphone warm so dictation starts instantly

    Bluetooth mics (AirPods especially) drop into a power-saving state when
    idle, adding a 1-2 second delay every time an app engages the mic.
    Micspresso holds the mic open — without recording anything — so it is
    always ready to capture.

    Micspresso is a menu bar app; launch it with no arguments and look for
    the cup icon. Options:

      -v, --version   Print the version and exit
      -h, --help      Show this help and exit
    """
}
