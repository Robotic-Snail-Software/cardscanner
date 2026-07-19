@testable import CardScanner
import Testing

struct SetCodeRepairTests {
    @Test(arguments: zip(
        ["NE0", "M1O", "S0I", "ZX2", "8RO"],
        ["NEO", "M10", "SOI", "2X2", "BRO"]
    ))
    func generatesTheExpectedRepair(damaged: String, expected: String) {
        #expect(SetCodeRepair.variants(of: damaged).contains(expected))
    }

    @Test func excludesTheOriginal() {
        #expect(SetCodeRepair.variants(of: "M10").contains("M10") == false)
    }

    @Test func codesWithoutConfusableCharactersHaveNoVariants() {
        #expect(SetCodeRepair.variants(of: "DMU").isEmpty)
        #expect(SetCodeRepair.variants(of: "KHM").isEmpty)
    }

    @Test func fanOutIsCapped() {
        // Every character confusable ("10125") — expansion must stay bounded.
        #expect(SetCodeRepair.variants(of: "10125").count <= 16)
    }
}
