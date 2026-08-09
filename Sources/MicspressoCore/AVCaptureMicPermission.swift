import AVFoundation
import Foundation

public final class AVCaptureMicPermission: MicPermissionChecking {
  public init() {}

  public var status: MicPermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return .authorized
    case .denied, .restricted: return .denied
    case .notDetermined: return .undetermined
    @unknown default: return .denied
    }
  }

  public func request(_ completion: @escaping (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        completion(granted)
      }
    }
  }
}
