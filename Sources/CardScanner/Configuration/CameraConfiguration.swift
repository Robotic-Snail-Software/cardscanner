/// Camera-session tunables.
public nonisolated struct CameraConfiguration: Sendable {
    /// Upper bound on capture frame rate. Recognition consumes latest-frame-
    /// only, so higher rates just waste power.
    public var maximumFrameRate: Double = 30

    public init() {}
}
