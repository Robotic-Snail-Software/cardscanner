import CoreGraphics

/// A single recognized text string from one Vision request, carried with the
/// evidence needed for scoring and voting.
nonisolated struct TextCandidate: Equatable, Sendable {
    /// The recognized text as returned by Vision.
    var string: String

    /// Vision's confidence in the recognition, 0…1.
    var confidence: Double

    /// Normalized bounding box within the recognition region, using a
    /// bottom-left origin (y grows toward the top of the image).
    var boundingBox: CGRect
}
