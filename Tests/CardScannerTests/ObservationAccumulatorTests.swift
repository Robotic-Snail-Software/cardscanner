@testable import CardScanner
import Testing

struct ObservationAccumulatorTests {
    private let halfLife = Duration.seconds(1.5)
    private var accumulator: ObservationAccumulator

    init() {
        accumulator = ObservationAccumulator(halfLife: halfLife)
    }

    @Test mutating func weightHalvesAfterOneHalfLife() {
        accumulator.recordName("Lightning Bolt", confidence: 1.0, at: .zero)
        let immediate = accumulator.rankedNames(at: .zero).first?.weight
        let later = accumulator.rankedNames(at: halfLife).first?.weight
        #expect(immediate == 1.0)
        #expect(later != nil)
        if let later {
            #expect(abs(later - 0.5) < 0.0001)
        }
    }

    @Test mutating func consistentReadsOvertakeAStaleEarlyLeader() {
        // One early confident misread…
        accumulator.recordName("Lightnimg Bolt", confidence: 1.0, at: .zero)
        // …followed by steady correct reads.
        for tick in 1...4 {
            accumulator.recordName("Lightning Bolt", confidence: 0.8, at: .seconds(tick))
        }
        let leader = accumulator.rankedNames(at: .seconds(4)).first
        #expect(leader?.name == "Lightning Bolt")
    }

    @Test mutating func namesPoolVotesAcrossCaseVariants() {
        accumulator.recordName("LIGHTNING BOLT", confidence: 0.5, at: .zero)
        accumulator.recordName("Lightning Bolt", confidence: 0.9, at: .zero)
        let ranked = accumulator.rankedNames(at: .zero)
        #expect(ranked.count == 1)
        #expect(ranked.first?.name == "Lightning Bolt", "highest-confidence read supplies the display form")
        if let weight = ranked.first?.weight {
            #expect(abs(weight - 1.4) < 0.0001)
        }
    }

    @Test mutating func collectorReadingsMergeAuxiliaryFields() {
        accumulator.recordCollector(
            CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277),
            confidence: 0.9,
            at: .zero
        )
        accumulator.recordCollector(
            CollectorInfo(collectorNumber: "117", setCode: "MID", languageCode: "EN", rarityLetter: "M"),
            confidence: 0.9,
            at: .seconds(1)
        )
        let leader = accumulator.rankedCollectors(at: .seconds(1)).first
        #expect(leader?.info.totalInSet == 277)
        #expect(leader?.info.languageCode == "EN")
        #expect(leader?.info.rarityLetter == "M")
        #expect(accumulator.rankedCollectors(at: .seconds(1)).count == 1)
    }

    @Test mutating func distinctReadingsStaySeparate() {
        accumulator.recordCollector(
            CollectorInfo(collectorNumber: "117", setCode: "MID"),
            confidence: 0.9,
            at: .zero
        )
        accumulator.recordCollector(
            CollectorInfo(collectorNumber: "117", setCode: "M10"),
            confidence: 0.9,
            at: .zero
        )
        #expect(accumulator.rankedCollectors(at: .zero).count == 2)
    }

    @Test mutating func resetClearsAllEvidence() {
        accumulator.recordName("Lightning Bolt", confidence: 1.0, at: .zero)
        accumulator.recordCollector(
            CollectorInfo(collectorNumber: "117", setCode: "MID"),
            confidence: 1.0,
            at: .zero
        )
        accumulator.reset()
        #expect(accumulator.rankedNames(at: .zero).isEmpty)
        #expect(accumulator.rankedCollectors(at: .zero).isEmpty)
    }

    @Test mutating func negligibleWeightsAreDropped() {
        accumulator.recordName("Lightning Bolt", confidence: 0.6, at: .zero)
        // After ~8 half-lives the weight is far below the floor.
        #expect(accumulator.rankedNames(at: .seconds(12)).isEmpty)
    }
}
