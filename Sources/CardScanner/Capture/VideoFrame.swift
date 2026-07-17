import CoreVideo
import ImageIO

/// A single camera frame on its way to recognition.
///
/// `@unchecked Sendable`: `CVPixelBuffer` carries no Sendable annotation, but
/// the buffer is retained by this wrapper, treated as strictly read-only, and
/// consumed by exactly one recognition pass. The frame stream's
/// `.bufferingNewest(1)` policy drops stale frames immediately, so buffers
/// never accumulate and the capture pool cannot starve.
nonisolated struct VideoFrame: @unchecked Sendable {
    /// The camera image.
    let pixelBuffer: CVPixelBuffer

    /// How to rotate the buffer for upright recognition. `.up` when the
    /// capture connection already rotates buffers.
    let orientation: CGImagePropertyOrientation
}
