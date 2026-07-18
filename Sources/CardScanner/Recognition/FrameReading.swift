/// Everything one camera frame yielded after recognition and parsing —
/// the unit of evidence fed into the vote accumulator.
nonisolated struct FrameReading: Equatable, Sendable {
    struct NameReading: Equatable, Sendable {
        var text: String
        var confidence: Double
    }

    struct CollectorReading: Equatable, Sendable {
        var info: CollectorInfo
        var confidence: Double
    }

    var name: NameReading?
    var collector: CollectorReading?

    /// Raw OCR lines from the collector band in reading order, before
    /// parsing — surfaced for on-device tuning and host debug UIs.
    var collectorLines: [String] = []

    /// Whether the text bands tracked a detected card rectangle this frame
    /// (versus falling back to the on-screen guide).
    var cardDetected = false

    var isEmpty: Bool { name == nil && collector == nil }
}
