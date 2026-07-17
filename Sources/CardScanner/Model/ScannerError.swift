/// Failures the scanner can surface to the host.
public nonisolated enum ScannerError: Error, Equatable, Sendable {
    /// The user denied (or a profile restricts) camera access.
    case cameraPermissionDenied

    /// No usable back camera on this device.
    case cameraUnavailable

    /// The capture session could not be configured.
    case cameraConfigurationFailed

    /// A Vision recognition pass failed unrecoverably.
    case recognitionFailed(String)

    /// The host's `CardCatalog` threw during a lookup.
    case catalogFailed(String)
}
