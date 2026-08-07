import CoreAudio
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
/// power-saving — but the audio buffers are never read, copied, or stored.
///
/// Deliberately uses the HAL directly instead of AVCaptureSession: session
/// teardown on an already-disconnected Bluetooth device is entangled with
/// CMIO/coreaudiod semaphores and has a documented history of deadlocking.
/// The HAL calls below return errors on dead devices instead of blocking.
public final class CoreAudioMicWarmer: MicWarming {
  public private(set) var warmedDeviceID: UInt32?
  private var procID: AudioDeviceIOProcID?

  /// Written by the IOProc on the HAL's realtime thread, read by the
  /// engine's heartbeat on the main thread. Aligned 64-bit loads/stores
  /// are atomic on arm64 and x86_64, and an occasionally-stale read only
  /// delays the heartbeat by one tick, so no lock is needed.
  private let callbackCounter: UnsafeMutablePointer<UInt64>

  public init() {
    callbackCounter = .allocate(capacity: 1)
    callbackCounter.initialize(to: 0)
  }

  deinit {
    stopWarming()
    callbackCounter.deallocate()
  }

  public var deliveryCount: UInt64 { callbackCounter.pointee }

  public func startWarming(device: AudioInputDevice) throws {
    stopWarming()

    var newProcID: AudioDeviceIOProcID?
    let createStatus = AudioDeviceCreateIOProcID(
      device.id, warmIOProc, UnsafeMutableRawPointer(callbackCounter), &newProcID)
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
    AudioDeviceStop(deviceID, procID)
    AudioDeviceDestroyIOProcID(deviceID, procID)
    self.procID = nil
    warmedDeviceID = nil
  }
}

/// Runs on the HAL realtime thread: count the callback and ignore the audio.
private let warmIOProc: AudioDeviceIOProc = { _, _, _, _, _, _, clientData in
  if let clientData {
    clientData.assumingMemoryBound(to: UInt64.self).pointee &+= 1
  }
  return noErr
}
