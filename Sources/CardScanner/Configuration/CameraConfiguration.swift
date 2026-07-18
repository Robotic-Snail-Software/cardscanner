/// Camera-session tunables.
public nonisolated struct CameraConfiguration: Sendable {
    /// Upper bound on capture frame rate. Recognition consumes latest-frame-
    /// only, so higher rates just waste power.
    public var maximumFrameRate: Double = 30

    /// Capture at 4K when the device supports it (falling back to 1080p).
    /// The collector line is ~1.5 mm tall; at guide-filling distance it spans
    /// only ~17 px in a 1080p frame — below reliable recognition — versus
    /// ~34 px at 4K. Vision cost stays low because recognition is restricted
    /// to two small regions.
    public var prefersUltraHighResolutionCapture = true

    public init() {}
}
