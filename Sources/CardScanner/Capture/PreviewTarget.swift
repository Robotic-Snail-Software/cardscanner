import AVFoundation

/// Adopted by the preview view so the capture session can be attached to its
/// `AVCaptureVideoPreviewLayer` on the main actor.
@MainActor protocol PreviewTarget {
    func setSession(_ session: AVCaptureSession)
}
