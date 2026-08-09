import CoreAudio
import XCTest

@testable import MicspressoCore

final class TransportTests: XCTestCase {
  func testMapsKnownTransportTypes() {
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeBuiltIn), .builtIn)
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeBluetooth), .bluetooth)
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeBluetoothLE), .bluetoothLE)
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeUSB), .usb)
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeVirtual), .virtual)
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeAggregate), .aggregate)
    XCTAssertEqual(Transport(rawTransportType: kAudioDeviceTransportTypeAirPlay), .airPlay)
    XCTAssertEqual(
      Transport(rawTransportType: kAudioDeviceTransportTypeContinuityCaptureWired),
      .continuityCapture
    )
    XCTAssertEqual(
      Transport(rawTransportType: kAudioDeviceTransportTypeContinuityCaptureWireless),
      .continuityCapture
    )
  }

  func testUnknownTransportTypeIsPreserved() {
    XCTAssertEqual(Transport(rawTransportType: 0xDEAD_BEEF), .other(0xDEAD_BEEF))
  }

  func testOnlyBluetoothTransportsAreBluetooth() {
    XCTAssertTrue(AudioInputDevice(id: 1, uid: "u", name: "n", transport: .bluetooth).isBluetooth)
    XCTAssertTrue(AudioInputDevice(id: 1, uid: "u", name: "n", transport: .bluetoothLE).isBluetooth)
    XCTAssertFalse(AudioInputDevice(id: 1, uid: "u", name: "n", transport: .builtIn).isBluetooth)
    XCTAssertFalse(AudioInputDevice(id: 1, uid: "u", name: "n", transport: .usb).isBluetooth)
    XCTAssertFalse(
      AudioInputDevice(id: 1, uid: "u", name: "n", transport: .continuityCapture).isBluetooth)
  }
}
