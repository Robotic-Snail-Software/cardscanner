/// Fuzzy comparison between an OCR name reading and catalog card names.
///
/// Similarity is `1 − levenshtein / max(length)` over folded strings (see
/// `TextNormalizer.foldedForMatching`), so case, diacritics, and punctuation
/// never count as errors — only genuine OCR character damage does.
nonisolated enum NameMatcher {
    /// Similarity in 0…1 between an OCR reading and a catalog name.
    ///
    /// Multi-face catalog names (`"Fire // Ice"`) are compared face-by-face
    /// as well as whole, and the best score wins — a scan only ever sees one
    /// face's title line.
    static func similarity(ocrName: String, catalogName: String) -> Double {
        let reading = TextNormalizer.foldedForMatching(ocrName)
        guard !reading.isEmpty else { return 0 }

        var comparisons = [TextNormalizer.foldedForMatching(catalogName)]
        if catalogName.contains("//") {
            comparisons += catalogName
                .split(separator: "//")
                .map { TextNormalizer.foldedForMatching(String($0)) }
        }
        return comparisons
            .map { similarity(reading, $0) }
            .max() ?? 0
    }

    /// Plain normalized Levenshtein similarity between two folded strings.
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let distance = levenshteinDistance(Array(a), Array(b))
        let longest = max(a.count, b.count)
        return 1 - Double(distance) / Double(longest)
    }

    /// Classic two-row dynamic-programming edit distance. Card names are
    /// short (< 50 characters), so quadratic cost is negligible.
    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)

        for (i, characterA) in a.enumerated() {
            currentRow[0] = i + 1
            for (j, characterB) in b.enumerated() {
                let substitution = previousRow[j] + (characterA == characterB ? 0 : 1)
                let insertion = currentRow[j] + 1
                let deletion = previousRow[j + 1] + 1
                currentRow[j + 1] = min(substitution, insertion, deletion)
            }
            swap(&previousRow, &currentRow)
        }
        return previousRow[b.count]
    }
}
