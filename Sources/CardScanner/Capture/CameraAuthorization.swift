import AVFoundation

/// Camera permission state, published by `CardScannerModel` so hosts can
/// drive a settings-redirect UI when access is denied.
public nonisolated enum CameraAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized

    /// The current system authorization for video capture.
    static var current: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    /// Prompts for camera access when undetermined; otherwise returns the
    /// existing state.
    static func request() async -> CameraAuthorization {
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}
