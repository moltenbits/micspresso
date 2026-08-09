import XCTest

@testable import MicspressoCore

final class AppInfoTests: XCTestCase {
  func testDisplayVersionAppendsDistinctBuild() {
    XCTAssertEqual(
      AppInfo.displayVersion(version: "1.0.0", build: "26.08.09.896"),
      "1.0.0 (26.08.09.896)")
  }

  func testDisplayVersionOmitsRedundantBuild() {
    XCTAssertEqual(AppInfo.displayVersion(version: "1.0.0", build: "1.0.0"), "1.0.0")
    XCTAssertEqual(AppInfo.displayVersion(version: "1.0.0", build: nil), "1.0.0")
    XCTAssertEqual(AppInfo.displayVersion(version: "1.0.0", build: ""), "1.0.0")
  }
}
