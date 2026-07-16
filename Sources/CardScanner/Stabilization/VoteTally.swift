import Foundation

/// One candidate's accumulated evidence with exponential time decay.
///
/// Weights halve every `halfLife`, so a burst of consistent fresh reads
/// overtakes a stale early leader instead of being locked out by it.
/// Time is always passed in by the caller (as elapsed scan time), keeping
/// the math fully deterministic for tests.
nonisolated struct VoteTally: Equatable, Sendable {
    private(set) var weight: Double = 0
    private(set) var lastUpdated: Duration = .zero

    /// Adds evidence at `time`, first decaying the existing weight.
    mutating func add(_ amount: Double, at time: Duration, halfLife: Duration) {
        weight = decayedWeight(at: time, halfLife: halfLife) + amount
        lastUpdated = max(time, lastUpdated)
    }

    /// The weight as of `time`, with decay applied but not stored.
    func decayedWeight(at time: Duration, halfLife: Duration) -> Double {
        guard time > lastUpdated else { return weight }
        let elapsed = (time - lastUpdated).portableSeconds
        return weight * pow(0.5, elapsed / halfLife.portableSeconds)
    }
}

nonisolated extension Duration {
    /// The duration in fractional seconds, for decay-ratio math.
    var portableSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
