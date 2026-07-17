/// The live best guess while evidence accumulates — drives the overlay's
/// caption and progress indicator.
public nonisolated struct ScanCandidate: Equatable, Sendable {
    /// Leading name reading, if any.
    public var name: String?

    /// Leading set-code reading, if any.
    public var setCode: String?

    /// Leading collector-number reading, if any.
    public var collectorNumber: String?

    /// Progress toward the applicable lock threshold, 0…1.
    public var progress: Double

    /// True when a strong reading keeps missing the catalog — the user
    /// should adjust framing.
    public var needsAlignmentHint: Bool
}
