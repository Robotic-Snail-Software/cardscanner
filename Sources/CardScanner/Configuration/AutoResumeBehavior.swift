/// What the scanner does after locking a card.
public nonisolated enum AutoResumeBehavior: Equatable, Sendable {
    /// Stay on the locked result until the host calls `resumeScanning()`.
    /// Suits single-card confirm flows.
    case manual

    /// Automatically resume scanning after the given pause — the default,
    /// tuned for scanning a stack of cards in one session.
    case after(Duration)
}
