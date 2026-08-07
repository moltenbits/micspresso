import CoreAudio

/// A snapshot of an audio input device as seen by the HAL.
public struct AudioInputDevice: Equatable {
  public let id: AudioDeviceID
  public let uid: String
  public let name: String
  public let transport: Transport

  public init(id: AudioDeviceID, uid: String, name: String, transport: Transport) {
    self.id = id
    self.uid = uid
    self.name = name
    self.transport = transport
  }

  /// Bluetooth devices are the ones that power-save their mic link and
  /// benefit from being kept warm.
  public var isBluetooth: Bool {
    transport == .bluetooth || transport == .bluetoothLE
  }
}

public enum Transport: Equatable {
  case builtIn
  case bluetooth
  case bluetoothLE
  case usb
  case continuityCapture
  case virtual
  case aggregate
  case airPlay
  case other(UInt32)

  public init(rawTransportType: UInt32) {
    switch rawTransportType {
    case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
    case kAudioDeviceTransportTypeBluetooth: self = .bluetooth
    case kAudioDeviceTransportTypeBluetoothLE: self = .bluetoothLE
    case kAudioDeviceTransportTypeUSB: self = .usb
    case kAudioDeviceTransportTypeContinuityCaptureWired,
      kAudioDeviceTransportTypeContinuityCaptureWireless:
      self = .continuityCapture
    case kAudioDeviceTransportTypeVirtual: self = .virtual
    case kAudioDeviceTransportTypeAggregate: self = .aggregate
    case kAudioDeviceTransportTypeAirPlay: self = .airPlay
    default: self = .other(rawTransportType)
    }
  }
}
