import XCTest

@testable import MicspressoCore

final class CLIArgsTests: XCTestCase {
  func testNoArgumentsRunsApp() {
    XCTAssertEqual(CLIArgs.parse([]), .run)
  }

  func testVersionFlags() {
    XCTAssertEqual(CLIArgs.parse(["--version"]), .version)
    XCTAssertEqual(CLIArgs.parse(["-v"]), .version)
  }

  func testHelpFlags() {
    XCTAssertEqual(CLIArgs.parse(["--help"]), .help)
    XCTAssertEqual(CLIArgs.parse(["-h"]), .help)
  }

  func testUnknownArgumentIsReported() {
    XCTAssertEqual(CLIArgs.parse(["--bogus"]), .unknown("--bogus"))
  }

  func testFirstArgumentWins() {
    XCTAssertEqual(CLIArgs.parse(["--version", "--help"]), .version)
  }
}
