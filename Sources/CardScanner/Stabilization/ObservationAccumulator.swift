/// Accumulates per-frame readings into decayed vote tallies so that noisy
/// single-frame results stabilize into a clear leader over ~1–2 seconds.
///
/// Names vote under their folded form (so `"LIGHTNING BOLT"` and
/// `"Lightning Bolt"` pool their evidence) while remembering the
/// highest-confidence display string. Collector readings vote under their
/// set-code + number identity, merging auxiliary fields (total, language,
/// rarity) from whichever frames managed to read them.
nonisolated struct ObservationAccumulator: Sendable {
    /// Entries below this decayed weight are omitted from rankings.
    private static let negligibleWeight = 0.05

    private struct NameVotes {
        var display: String
        var displayConfidence: Double
        var tally = VoteTally()
    }

    private struct CollectorKey: Hashable {
        var setCode: String?
        var collectorNumber: String
    }

    private struct CollectorVotes {
        var representative: CollectorInfo
        var tally = VoteTally()
    }

    private let halfLife: Duration
    private var names: [String: NameVotes] = [:]
    private var collectors: [CollectorKey: CollectorVotes] = [:]

    init(halfLife: Duration) {
        self.halfLife = halfLife
    }

    // MARK: Recording

    mutating func recordName(_ name: String, confidence: Double, at time: Duration) {
        let key = TextNormalizer.foldedForMatching(name)
        guard !key.isEmpty else { return }
        var votes = names[key] ?? NameVotes(display: name, displayConfidence: confidence)
        if confidence >= votes.displayConfidence {
            votes.display = name
            votes.displayConfidence = confidence
        }
        votes.tally.add(confidence, at: time, halfLife: halfLife)
        names[key] = votes
    }

    mutating func recordCollector(_ info: CollectorInfo, confidence: Double, at time: Duration) {
        let key = CollectorKey(setCode: info.setCode, collectorNumber: info.collectorNumber)
        var votes = collectors[key] ?? CollectorVotes(representative: info)
        votes.representative.totalInSet = info.totalInSet ?? votes.representative.totalInSet
        votes.representative.languageCode = info.languageCode ?? votes.representative.languageCode
        votes.representative.rarityLetter = info.rarityLetter ?? votes.representative.rarityLetter
        votes.tally.add(confidence, at: time, halfLife: halfLife)
        collectors[key] = votes
    }

    // MARK: Rankings

    /// Display names by decayed weight, strongest first.
    func rankedNames(at time: Duration) -> [(name: String, weight: Double)] {
        names.values
            .map { (name: $0.display, weight: $0.tally.decayedWeight(at: time, halfLife: halfLife)) }
            .filter { $0.weight > Self.negligibleWeight }
            .sorted { $0.weight > $1.weight }
    }

    /// Collector readings by decayed weight, strongest first.
    func rankedCollectors(at time: Duration) -> [(info: CollectorInfo, weight: Double)] {
        collectors.values
            .map { (info: $0.representative, weight: $0.tally.decayedWeight(at: time, halfLife: halfLife)) }
            .filter { $0.weight > Self.negligibleWeight }
            .sorted { $0.weight > $1.weight }
    }

    /// Clears all evidence — called when scanning resumes for the next card.
    mutating func reset() {
        names.removeAll()
        collectors.removeAll()
    }
}
