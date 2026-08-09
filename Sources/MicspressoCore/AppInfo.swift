import Foundation

public enum AppInfo {
  /// The app version, stamped into the bundle's Info.plist by the release
  /// build. Falls back to a dev marker when running unbundled (swift run).
  public static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
  }
}
