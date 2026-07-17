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

    var isEmpty: Bool { name == nil && collector == nil }
}
