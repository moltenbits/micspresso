import Foundation

public enum AppInfo {
  /// The app version, stamped into the bundle's Info.plist by the release
  /// build. Falls back to a dev marker when running unbundled (swift run).
  public static var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
  }

  /// The build identifier (CFBundleVersion). Dev builds stamp a build
  /// timestamp here; release builds repeat the version.
  public static var build: String? {
    Bundle.main.infoDictionary?["CFBundleVersion"] as? String
  }

  /// Version for display: "1.0.0" for releases, "1.0.0 (26.08.09.896)" for
  /// dev builds where the build identifier carries extra information.
  public static var displayVersion: String {
    displayVersion(version: version, build: build)
  }

  static func displayVersion(version: String, build: String?) -> String {
    guard let build, !build.isEmpty, build != version else { return version }
    return "\(version) (\(build))"
  }
}
