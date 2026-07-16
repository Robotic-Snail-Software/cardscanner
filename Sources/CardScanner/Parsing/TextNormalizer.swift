/// Pure text-normalization helpers shared by the parsing and matching layers.
///
/// All functions are deterministic and side-effect free so they can be unit
/// tested without any camera or catalog involvement.
nonisolated enum TextNormalizer {
    /// Trims the string and collapses internal runs of whitespace into single spaces.
    static func collapsedWhitespace(_ string: String) -> String {
        string
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Normalizes a string for fuzzy name comparison: ligatures expanded,
    /// diacritics and case folded, punctuation stripped, whitespace collapsed.
    ///
    /// `"Lim-Dûl's Vault"` → `"lim dul s vault"`, `"Æther Vial"` → `"aether vial"`.
    static func foldedForMatching(_ string: String) -> String {
        let expanded = string
            .replacing("Æ", with: "AE")
            .replacing("æ", with: "ae")
        let folded = expanded.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        )
        let alphanumericOnly = folded.map { character in
            character.isLetter || character.isNumber ? character : " "
        }
        return collapsedWhitespace(String(alphanumericOnly))
    }
}
