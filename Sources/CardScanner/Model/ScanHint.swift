/// User-correctable problems the scanner can detect while evidence
/// accumulates, surfaced through `ScanCandidate.hint`.
public nonisolated enum ScanHint: Equatable, Sendable {
    /// A strong collector reading keeps missing the catalog — the framing
    /// is probably off or the read is wrong.
    case checkAlignment

    /// The title reads but the small collector print never does —
    /// characteristic of dim lighting; the torch usually fixes it.
    case needsMoreLight
}
