/// The scanner's lifecycle state. Fine-grained live evidence (the emerging
/// name/set/number and lock progress) is published separately as
/// `CardScannerModel.liveCandidate` so the phase only changes on real
/// transitions.
public nonisolated enum ScanPhase: Equatable, Sendable {
    /// Not scanning; call `start()`.
    case idle

    /// Camera running, accumulating evidence for the next card.
    case searching

    /// A card was confirmed. Scanning resumes per `AutoResumeBehavior`.
    case locked(ScannedCard)

    /// Scanning stopped with an unrecoverable problem.
    case failed(ScannerError)
}
