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

  public var bluetoothInputDevices: [AudioInputDevice] {
    allDeviceIDs()
      .filter { hasInputStreams($0) }
      .map { describe(deviceID: $0) }
      .filter(\.isBluetooth)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

  private func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let sizeStatus = AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    guard sizeStatus == noErr, size > 0 else { return [] }

    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let status = ids.withUnsafeMutableBufferPointer { buffer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!)
    }
    guard status == noErr else { return [] }
    return ids
  }

  private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
    return status == noErr && size >= UInt32(MemoryLayout<AudioStreamID>.size)
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
