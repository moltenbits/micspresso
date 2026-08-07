import CoreAudio
import Foundation

/// Queries and watches the system default input device via the HAL.
///
/// Listens only to input-related properties on the system object. Property
/// listeners on *output* devices trigger a separate "record system audio"
/// TCC prompt on recent macOS versions, so no per-device or output listeners
/// are ever registered.
public final class CoreAudioInputMonitor: AudioInputProviding {
  /// Fired (on the main queue) whenever the default input or the device
  /// list changes. One physical change can fire this several times.
  public var onChange: (() -> Void)?

  private var listeningAddresses: [AudioObjectPropertyAddress] = []
  private var listenerBlock: AudioObjectPropertyListenerBlock?

  public init() {}

  deinit {
    stopMonitoring()
  }

  public var defaultInputDevice: AudioInputDevice? {
    var deviceID = kAudioObjectUnknown
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return describe(deviceID: deviceID)
  }

  public func startMonitoring() {
    guard listenerBlock == nil else { return }

    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.onChange?()
    }
    listenerBlock = block
    listeningAddresses = [
      AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain),
      AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain),
    ]
    for var address in listeningAddresses {
      AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }
  }

  public func stopMonitoring() {
    guard let block = listenerBlock else { return }
    for var address in listeningAddresses {
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }
    listenerBlock = nil
    listeningAddresses = []
  }

  private func describe(deviceID: AudioDeviceID) -> AudioInputDevice {
    AudioInputDevice(
      id: deviceID,
      uid: stringProperty(deviceID, kAudioDevicePropertyDeviceUID) ?? "unknown-\(deviceID)",
      name: stringProperty(deviceID, kAudioObjectPropertyName) ?? "Unknown Device",
      transport: Transport(
        rawTransportType: uint32Property(deviceID, kAudioDevicePropertyTransportType) ?? 0))
  }

  private func uint32Property(
    _ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector
  ) -> UInt32? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
    guard status == noErr else { return nil }
    return value
  }

  private func stringProperty(
    _ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
    }
    guard status == noErr, let value else { return nil }
    return value as String
  }
}
