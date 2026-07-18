#if os(iOS)
import AVFoundation

/// Hands the capture session to a main-actor preview view without exposing
/// the session across the rest of the package (Apple's AVCam pattern).
///
/// `@unchecked Sendable`: `AVCaptureSession` is not Sendable-annotated, but
/// this wrapper only carries the reference from the capture actor to the main
/// actor once, where it is attached to a preview layer — AVFoundation
/// documents the session as safe to share for exactly this purpose.
nonisolated struct PreviewSource: @unchecked Sendable {
    private let session: AVCaptureSession

    init(session: AVCaptureSession) {
        self.session = session
    }

    /// Attaches the session to the preview view.
    @MainActor func connect(to target: some PreviewTarget) {
        target.setSession(session)
    }
}
#endif
