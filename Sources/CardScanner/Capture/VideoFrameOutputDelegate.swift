import AVFoundation

/// Bridges AVFoundation's sample-buffer delegate into an `AsyncStream` of
/// `VideoFrame`s.
///
/// `setSampleBufferDelegate(_:queue:)` requires a serial dispatch queue by
/// API contract, making this the package's one unavoidable GCD touchpoint —
/// it contains no logic beyond the hand-off into structured concurrency.
nonisolated final class VideoFrameOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let orientation: CGImagePropertyOrientation
    private let continuation: AsyncStream<VideoFrame>.Continuation

    init(orientation: CGImagePropertyOrientation, continuation: AsyncStream<VideoFrame>.Continuation) {
        self.orientation = orientation
        self.continuation = continuation
    }

    /// Ends the stream, releasing any consumer loop.
    func finish() {
        continuation.finish()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        continuation.yield(VideoFrame(pixelBuffer: pixelBuffer, orientation: orientation))
    }
}
