import CoreAudio
import Dispatch
import XCTest

@testable import MicspressoCore

final class MicDeliveryCountersTests: XCTestCase {
  func testZeroedBufferAdvancesOnlyCallbackCount() {
    let counters = MicDeliveryCounters()

    record(bytes: [0, 0, 0, 0], into: counters)

    XCTAssertEqual(
      counters.snapshot,
      MicDeliverySnapshot(callbackCount: 1, nonzeroCallbackCount: 0))
  }

  func testAnyNonzeroByteMarksCallbackAsSignalBearing() {
    let counters = MicDeliveryCounters()

    record(bytes: [0, 0, 0, 1], into: counters)

    XCTAssertEqual(
      counters.snapshot,
      MicDeliverySnapshot(callbackCount: 1, nonzeroCallbackCount: 1))
  }

  func testMissingBufferDataDoesNotCountAsSignal() {
    let counters = MicDeliveryCounters()
    var bufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 4, mData: nil))

    withUnsafePointer(to: &bufferList) { counters.record(inputData: $0) }

    XCTAssertEqual(
      counters.snapshot,
      MicDeliverySnapshot(callbackCount: 1, nonzeroCallbackCount: 0))
  }

  func testConcurrentCallbacksAreCountedAtomically() {
    let counters = MicDeliveryCounters()

    DispatchQueue.concurrentPerform(iterations: 10_000) { _ in
      var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
      withUnsafePointer(to: &bufferList) { counters.record(inputData: $0) }
    }

    XCTAssertEqual(counters.snapshot.callbackCount, 10_000)
  }

  private func record(bytes: [UInt8], into counters: MicDeliveryCounters) {
    var bytes = bytes
    bytes.withUnsafeMutableBytes { rawBuffer in
      var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
          mNumberChannels: 1,
          mDataByteSize: UInt32(rawBuffer.count),
          mData: rawBuffer.baseAddress))
      withUnsafePointer(to: &bufferList) { counters.record(inputData: $0) }
    }
  }
}
