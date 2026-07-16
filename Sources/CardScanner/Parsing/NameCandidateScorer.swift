/// Selects the most plausible card-name reading from the name-band
/// observations of a single frame.
///
/// The name band is a narrow strip over the card's title line, so most
/// observations *are* the title — the scorer's job is to reject debris
/// (mana-cost glyph misreads, digit-heavy noise, legal symbols) and prefer
/// the tallest, topmost, most confident line when several survive.
nonisolated enum NameCandidateScorer {
    /// Characters that appear when OCR misreads mana-cost symbols trailing
    /// the title (`{2}{W}{U}` debris like `"2 W U"`).
    private static let manaDebrisCharacters = Set("0123456789WUBRGXCPwubrgxcp")

    /// The best name reading for this frame, cleaned of trailing mana debris,
    /// with its Vision confidence — or `nil` when nothing name-like was read.
    static func bestName(from candidates: [TextCandidate]) -> (name: String, confidence: Double)? {
        let scored: [(name: String, confidence: Double, score: Double)] = candidates.compactMap { candidate in
            guard let cleaned = plausibleName(from: candidate.string) else { return nil }
            return (cleaned, candidate.confidence, score(for: candidate))
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        return (best.name, best.confidence)
    }

    /// Cleans a raw reading and returns it only if it plausibly is a card name.
    private static func plausibleName(from raw: String) -> String? {
        let collapsed = TextNormalizer.collapsedWhitespace(raw)
        let cleaned = strippingTrailingManaDebris(collapsed)
        guard cleaned.count >= 3 else { return nil }
        guard !cleaned.contains(where: { "™®©".contains($0) }) else { return nil }
        let letterCount = cleaned.count(where: \.isLetter)
        let digitCount = cleaned.count(where: \.isNumber)
        guard letterCount > digitCount else { return nil }
        guard cleaned.wholeMatch(of: #/\d+\s*\/\s*\d+/#) == nil else { return nil }
        return cleaned
    }

    /// Removes trailing 1–2 character mana-ish tokens (e.g. `"Counterspell U U"`
    /// → `"Counterspell"`), always preserving at least one token.
    private static func strippingTrailingManaDebris(_ name: String) -> String {
        var tokens = name.split(separator: " ")
        while tokens.count > 1,
              let last = tokens.last,
              last.count <= 2,
              last.allSatisfy(manaDebrisCharacters.contains) {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }

    /// Taller and higher-placed text wins ties; Vision confidence dominates.
    /// Bounding boxes use a bottom-left origin, so a larger `midY` is closer
    /// to the top of the band.
    private static func score(for candidate: TextCandidate) -> Double {
        let heightFactor = 0.5 + min(candidate.boundingBox.height, 1.0)
        let topFactor = 0.5 + 0.5 * min(max(candidate.boundingBox.midY, 0), 1)
        return candidate.confidence * heightFactor * topFactor
    }
}
