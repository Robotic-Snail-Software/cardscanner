@testable import CardScanner
import CoreGraphics
import Testing

struct NameCandidateScorerTests {
    private func candidate(
        _ string: String,
        confidence: Double = 0.9,
        height: Double = 0.6,
        midY: Double = 0.5
    ) -> TextCandidate {
        TextCandidate(
            string: string,
            confidence: confidence,
            boundingBox: CGRect(x: 0.1, y: midY - height / 2, width: 0.8, height: height)
        )
    }

    @Test func picksTheOnlyPlausibleName() {
        let best = NameCandidateScorer.bestName(from: [
            candidate("Lightning Bolt"),
            candidate("117/277"),
            candidate("™"),
        ])
        #expect(best?.name == "Lightning Bolt")
    }

    @Test func prefersHigherConfidence() {
        let best = NameCandidateScorer.bestName(from: [
            candidate("Lightnimg Bolt", confidence: 0.4),
            candidate("Lightning Bolt", confidence: 0.95),
        ])
        #expect(best?.name == "Lightning Bolt")
        #expect(best?.confidence == 0.95)
    }

    @Test func stripsTrailingManaDebris() {
        let best = NameCandidateScorer.bestName(from: [candidate("Counterspell U U")])
        #expect(best?.name == "Counterspell")
    }

    @Test func stripsMixedManaCostDebris() {
        let best = NameCandidateScorer.bestName(from: [candidate("Lightning Bolt 1R")])
        #expect(best?.name == "Lightning Bolt")
    }

    @Test func keepsLegitimateShortFinalWords() {
        // "Rat" is 3 characters — must survive debris stripping.
        let best = NameCandidateScorer.bestName(from: [candidate("Pack Rat")])
        #expect(best?.name == "Pack Rat")
    }

    @Test func neverStripsTheOnlyToken() {
        let best = NameCandidateScorer.bestName(from: [candidate("Ow")])
        #expect(best == nil, "two-character strings are not plausible names")
    }

    @Test(arguments: [
        "12",           // too short
        "117/277",      // collector fraction
        "2024 456",     // digit-heavy
        "™ Wizards",    // legal symbol
        "",             // empty
    ])
    func rejectsImplausibleNames(input: String) {
        let best = NameCandidateScorer.bestName(from: [candidate(input)])
        #expect(best == nil)
    }

    @Test func returnsNilForNoCandidates() {
        #expect(NameCandidateScorer.bestName(from: []) == nil)
    }
}
