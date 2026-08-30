import CoreAudio
import Darwin
import Foundation

public enum MicWarmerError: Error, LocalizedError, Equatable {
  case createIOProcFailed(OSStatus)
  case startFailed(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .createIOProcFailed(let status):
      return "Could not attach to the input device (OSStatus \(status))"
    case .startFailed(let status):
      return "Could not start the input device (OSStatus \(status))"
    }
  }
}

/// Keeps a device warm by running a no-op HAL IOProc on it. The device sees
/// an active capture client — which is what keeps Bluetooth mics out of
/// power-saving. The IOProc checks only whether each buffer is entirely zero;
/// it never retains, copies, logs, or transmits audio samples.
///
/// Deliberately uses the HAL directly instead of AVCaptureSession: session
/// teardown on an already-disconnected Bluetooth device is entangled with
/// CMIO/coreaudiod semaphores and has a documented history of deadlocking.
/// The HAL calls below return errors on dead devices instead of blocking.
public final class CoreAudioMicWarmer: MicWarming {
  public private(set) var warmedDeviceID: UInt32?
  private var procID: AudioDeviceIOProcID?
  private let log = DiagnosticsLog(category: "audio")

  /// Written by the IOProc on HAL's realtime thread and sampled by the engine
  /// on the main thread. The counters use lock-free atomic operations so the
  /// realtime callback never waits on the heartbeat reader.
  private let deliveryCounters = MicDeliveryCounters()

  public init() {}

  deinit {
    stopWarming()
  }

  public var deliverySnapshot: MicDeliverySnapshot { deliveryCounters.snapshot }

  public func startWarming(device: AudioInputDevice) throws {
    stopWarming()

    var newProcID: AudioDeviceIOProcID?
    let createStatus = AudioDeviceCreateIOProcID(
      device.id, warmIOProc, Unmanaged.passUnretained(deliveryCounters).toOpaque(), &newProcID)
    guard createStatus == noErr, let newProcID else {
      throw MicWarmerError.createIOProcFailed(createStatus)
    }

    let startStatus = AudioDeviceStart(device.id, newProcID)
    guard startStatus == noErr else {
      AudioDeviceDestroyIOProcID(device.id, newProcID)
      throw MicWarmerError.startFailed(startStatus)
    }

    procID = newProcID
    warmedDeviceID = device.id
  }

  public func stopWarming() {
    guard let procID, let deviceID = warmedDeviceID else { return }
    // Best effort: on a disconnected device these return errors, which is
    // fine — the HAL has already torn the IO down.
    let stopStatus = AudioDeviceStop(deviceID, procID)
    let destroyStatus = AudioDeviceDestroyIOProcID(deviceID, procID)
    if stopStatus != noErr || destroyStatus != noErr {
      log.warning(
        "HAL release for device [\(deviceID)] returned stop=\(stopStatus), destroy=\(destroyStatus)"
      )
    }
    self.procID = nil
    warmedDeviceID = nil
  }
}

/// Fixed-size metadata updated by the realtime callback without allocation,
/// locking, copying, or retaining any audio.
final class MicDeliveryCounters {
  private let callbackCount: UnsafeMutablePointer<Int64>
  private let nonzeroCallbackCount: UnsafeMutablePointer<Int64>

  init() {
    callbackCount = .allocate(capacity: 1)
    callbackCount.initialize(to: 0)
    nonzeroCallbackCount = .allocate(capacity: 1)
    nonzeroCallbackCount.initialize(to: 0)
  }

  deinit {
    callbackCount.deinitialize(count: 1)
    callbackCount.deallocate()
    nonzeroCallbackCount.deinitialize(count: 1)
    nonzeroCallbackCount.deallocate()
  }

  var snapshot: MicDeliverySnapshot {
    MicDeliverySnapshot(
      callbackCount: UInt64(bitPattern: OSAtomicAdd64(0, callbackCount)),
      nonzeroCallbackCount: UInt64(bitPattern: OSAtomicAdd64(0, nonzeroCallbackCount)))
  }

  func record(inputData: UnsafePointer<AudioBufferList>) {
    OSAtomicIncrement64(callbackCount)

    let buffers = UnsafeMutableAudioBufferListPointer(
      UnsafeMutablePointer(mutating: inputData))
    for buffer in buffers {
      guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
      let bytes = data.assumingMemoryBound(to: UInt8.self)
      for index in 0..<Int(buffer.mDataByteSize) where bytes[index] != 0 {
        OSAtomicIncrement64(nonzeroCallbackCount)
        return
      }
    }
  }
}

private let warmIOProc: AudioDeviceIOProc = { _, _, inputData, _, _, _, clientData in
  if let clientData {
    Unmanaged<MicDeliveryCounters>.fromOpaque(clientData).takeUnretainedValue().record(
      inputData: inputData)
  }
  return noErr
}
