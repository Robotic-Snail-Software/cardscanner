@testable import CardScanner
import Testing

struct NameMatcherTests {
    @Test func exactMatchIsPerfect() {
        #expect(NameMatcher.similarity(ocrName: "Lightning Bolt", catalogName: "Lightning Bolt") == 1.0)
    }

    @Test func caseAndDiacriticsNeverCount() {
        #expect(NameMatcher.similarity(ocrName: "AEther Vial", catalogName: "Æther Vial") == 1.0)
        #expect(NameMatcher.similarity(ocrName: "lim-dul's vault", catalogName: "Lim-Dûl's Vault") == 1.0)
    }

    @Test func singleOCRErrorScoresHigh() {
        let score = NameMatcher.similarity(ocrName: "Lightnimg Bolt", catalogName: "Lightning Bolt")
        #expect(score >= 0.85)
        #expect(score < 1.0)
    }

    @Test func doubleFacedCardMatchesFrontFace() {
        let score = NameMatcher.similarity(
            ocrName: "Delver of Secrets",
            catalogName: "Delver of Secrets // Insectile Aberration"
        )
        #expect(score == 1.0)
    }

    @Test func splitCardMatchesEitherHalf() {
        #expect(NameMatcher.similarity(ocrName: "Fire", catalogName: "Fire // Ice") == 1.0)
        #expect(NameMatcher.similarity(ocrName: "Ice", catalogName: "Fire // Ice") == 1.0)
    }

    @Test func garbageScoresLow() {
        let score = NameMatcher.similarity(ocrName: "xQz7 pT", catalogName: "Lightning Bolt")
        #expect(score < 0.3)
    }

    @Test func emptyReadingScoresZero() {
        #expect(NameMatcher.similarity(ocrName: "", catalogName: "Lightning Bolt") == 0)
        #expect(NameMatcher.similarity(ocrName: "  ", catalogName: "Lightning Bolt") == 0)
    }

    @Test func distinctNamesAreDistinguishable() {
        // The name-only lock rule requires the best candidate to beat the
        // runner-up by a margin; sibling cycle names must not tie.
        let reading = "Fanatic of Mogis"
        let match = NameMatcher.similarity(ocrName: reading, catalogName: "Fanatic of Mogis")
        let sibling = NameMatcher.similarity(ocrName: reading, catalogName: "Fanatic of Xenagos")
        #expect(match - sibling >= 0.1)
    }
}
