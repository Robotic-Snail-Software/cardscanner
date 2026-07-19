/// The pure output of one resolver pass: either a lock, or guidance on what
/// the pipeline should do next (keep scanning, fetch a catalog answer, hint
/// the user).
nonisolated struct ScanDecision: Equatable, Sendable {
    /// A confirmed identification ready to deliver to the host.
    struct Lock: Equatable, Sendable {
        /// The card's canonical (catalog) name.
        var name: String

        /// The resolved printing, when one was pinned down.
        var printing: CatalogPrinting?

        /// How the identification was verified.
        var confidence: ScanConfidence

        /// Other plausible printings for `.nameOnly` locks.
        var alternates: [CatalogPrinting] = []
    }

    /// Catalog work the model must perform before the resolver can progress.
    enum Lookup: Hashable, Sendable {
        case printing(setCode: String, collectorNumber: String)
        case nameCandidates(String)
    }

    var lock: Lock?
    var progress: Double = 0
    var leadingName: String?
    var leadingCollector: CollectorInfo?
    var hint: ScanHint?
    var neededLookups: [Lookup] = []
}
