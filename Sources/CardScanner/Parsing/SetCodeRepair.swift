/// Generates OCR-confusion variants of a set code for catalog-verified
/// repair.
///
/// Set codes are never digit-repaired at parse time (`"SLD"` must not become
/// `"510"`), but once the catalog has confirmed a miss it is safe to probe
/// look-alike variants — the catalog itself is the safety check, and only a
/// uniquely matching variant is accepted.
nonisolated enum SetCodeRepair {
    /// Bidirectional look-alike substitutions seen in set-code OCR.
    private static let confusions: [Character: [Character]] = [
        "0": ["O"], "O": ["0"],
        "1": ["I", "L"], "I": ["1"], "L": ["1"],
        "5": ["S"], "S": ["5"],
        "8": ["B"], "B": ["8"],
        "2": ["Z"], "Z": ["2"],
        "6": ["G"], "G": ["6"],
    ]

    /// Whether two set codes are plausibly OCR misreads of each other.
    static func areConfusable(_ a: String, _ b: String) -> Bool {
        a == b || variants(of: a).contains(b) || variants(of: b).contains(a)
    }

    /// All single- and multi-character confusion variants of `code`,
    /// excluding the original, capped to keep lookup fan-out bounded.
    static func variants(of code: String, limit: Int = 16) -> [String] {
        var results: [String] = []
        expand(Array(code), index: 0, current: [], into: &results, limit: limit)
        return results.filter { $0 != code }
    }

    private static func expand(
        _ characters: [Character],
        index: Int,
        current: [Character],
        into results: inout [String],
        limit: Int
    ) {
        guard results.count < limit + 1 else { return }
        guard index < characters.count else {
            results.append(String(current))
            return
        }
        let character = characters[index]
        for choice in [character] + (confusions[character] ?? []) {
            expand(characters, index: index + 1, current: current + [choice], into: &results, limit: limit)
        }
    }
}
