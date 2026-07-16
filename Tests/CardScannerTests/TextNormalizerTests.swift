@testable import CardScanner
import Testing

struct TextNormalizerTests {
    @Test(arguments: zip(
        ["  a   b\t c ", "single", "", "line\nbreak"],
        ["a b c", "single", "", "line break"]
    ))
    func collapsesWhitespace(input: String, expected: String) {
        #expect(TextNormalizer.collapsedWhitespace(input) == expected)
    }

    @Test(arguments: zip(
        [
            "Lim-Dûl's Vault",
            "Æther Vial",
            "Circle of Protection: Red",
            "Lightning Bolt",
            "JÖTUN GRUNT",
            "Fire // Ice",
        ],
        [
            "lim dul s vault",
            "aether vial",
            "circle of protection red",
            "lightning bolt",
            "jotun grunt",
            "fire ice",
        ]
    ))
    func foldsForMatching(input: String, expected: String) {
        #expect(TextNormalizer.foldedForMatching(input) == expected)
    }
}
