/// Parses OCR lines from a card's collector-info region into a `CollectorInfo`.
///
/// Modern (post-M15) cards print two short lines in the bottom-left corner:
///
///     0117/0277 M          ← collector number [/set total] + rarity letter
///     MID • EN  Artist…    ← set code • language, then artist credit
///
/// Vision may deliver these as separate observations, merge them into one
/// line, or garble digits into look-alike letters. The parser runs a ladder
/// of patterns from most to least specific and stops at the first match:
///
/// 1. Merged single line: `number[/total] [rarity] SET • LANG`
/// 2. Line pair: a number-only line plus a `SET • LANG` line
/// 3. `SET number[suffix]/total` within a line
/// 4. Bare fraction `number[suffix]/total` (3–4 digit denominator)
/// 5. `SET number[suffix]` as a whole line
/// 6. Standalone `number[suffix] [rarity]` line
///
/// Structural matching happens on the raw text; only captured numeric slots
/// are digit-deconfused (see `DigitDeconfuser`), so set codes are never
/// corrupted. Validity gates reject P/T-shaped fractions, year-like numbers,
/// language codes and legal-text words posing as set codes.
nonisolated enum CollectorLineParser {
    /// Language tokens printed on cards. `ZHS`/`ZHT` precede `ZH` so the
    /// longer alternation wins.
    private static let languageCodes: Set<String> = [
        "EN", "DE", "FR", "IT", "ES", "PT", "JA", "JP", "KO", "RU",
        "ZHS", "ZHT", "ZH", "PH",
    ]

    /// Words from surrounding legal text that must never be read as set codes.
    private static let setCodeDenylist: Set<String> = [
        "THE", "MAGIC", "WOTC", "AND", "FOR", "TM", "INC", "LLC",
    ]

    // MARK: Entry point

    /// Parses the OCR lines from the collector band (in reading order) into
    /// the best single interpretation, or `nil` when nothing trustworthy was
    /// read. A set code is never returned without a collector number.
    static func parse(lines: [String]) -> CollectorInfo? {
        let cleaned = lines
            .map(TextNormalizer.collapsedWhitespace)
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        if let merged = firstResult(in: cleaned, using: parseMergedLine) { return merged }
        if let paired = parseLinePair(cleaned) { return paired }
        if let setFraction = firstResult(in: cleaned, using: parseSetFraction) { return setFraction }
        if let fraction = firstResult(in: cleaned, using: parseBareFraction) { return fraction }
        if let setNumber = firstResult(in: cleaned, using: parseSetNumber) { return setNumber }
        return firstResult(in: cleaned, using: parseStandaloneNumber)
    }

    private static func firstResult(
        in lines: [String],
        using parser: (String) -> CollectorInfo?
    ) -> CollectorInfo? {
        for line in lines {
            if let info = parser(line) { return info }
        }
        return nil
    }

    // MARK: Ladder rungs

    /// Rung 1: everything on one line, e.g. `"0117/0277 M MID • EN"`.
    private static func parseMergedLine(_ line: String) -> CollectorInfo? {
        // Numeric slots accept OCR-confusable letters; see DigitDeconfuser.
        let pattern = #/
            ^(?<num>[0-9DOQILSB|oqils]{1,4})(?<suffix>[a-e★†]?)
            (?:\/(?<total>[0-9DOQILSB|oqils]{1,4}))?
            (?:\s+(?<rarity>[CULRMSTP]))?
            \s+(?<set>[A-Za-z0-9]{2,5})\s*[•·∙.*—–-]?\s*
            (?<lang>ZHS|ZHT|ZH|EN|DE|FR|IT|ES|PT|JA|JP|KO|RU|PH)\b
        /#
        guard let match = line.firstMatch(of: pattern),
              let setCode = validatedSetCode(match.set),
              let number = canonicalNumber(slot: match.num, suffix: match.suffix)
        else { return nil }

        var total: Int?
        if let totalSlot = match.total {
            guard let validated = validatedTotal(totalSlot, numerator: number.value) else { return nil }
            total = validated
        }
        return CollectorInfo(
            collectorNumber: number.canonical,
            setCode: setCode,
            totalInSet: total,
            languageCode: String(match.lang),
            rarityLetter: match.rarity.flatMap(\.first)
        )
    }

    /// Rung 2: a number-only line combined with a `SET • LANG` line elsewhere
    /// in the band, in either reading order.
    private static func parseLinePair(_ lines: [String]) -> CollectorInfo? {
        for (numberIndex, line) in lines.enumerated() {
            guard let number = parseNumberLine(line) else { continue }
            for (setIndex, other) in lines.enumerated() where setIndex != numberIndex {
                guard let setLanguage = parseSetLanguagePrefix(other) else { continue }
                return CollectorInfo(
                    collectorNumber: number.canonical,
                    setCode: setLanguage.setCode,
                    totalInSet: number.total,
                    languageCode: setLanguage.language,
                    rarityLetter: number.rarity
                )
            }
        }
        return nil
    }

    /// Rung 3: `"OTJ 0123a/0271"` anywhere in a line.
    private static func parseSetFraction(_ line: String) -> CollectorInfo? {
        let pattern = #/
            \b(?<set>[A-Za-z0-9]{2,5})\s+
            (?<num>[0-9DOQILSB|oqils]{1,4})(?<suffix>[a-e★†]?)
            \/(?<total>[0-9DOQILSB|oqils]{1,4})\b
        /#
        guard let match = line.firstMatch(of: pattern),
              let setCode = validatedSetCode(match.set),
              let number = canonicalNumber(slot: match.num, suffix: match.suffix),
              let total = validatedTotal(match.total, numerator: number.value)
        else { return nil }
        return CollectorInfo(
            collectorNumber: number.canonical,
            setCode: setCode,
            totalInSet: total
        )
    }

    /// Rung 4: a bare `"123a/271"` fraction. The 3–4 digit denominator
    /// requirement keeps power/toughness like `"2/2"` out.
    private static func parseBareFraction(_ line: String) -> CollectorInfo? {
        let pattern = #/
            \b(?<num>[0-9DOQILSB|oqils]{1,4})(?<suffix>[a-e★†]?)
            \/(?<total>[0-9DOQILSB|oqils]{3,4})\b
        /#
        guard let match = line.firstMatch(of: pattern),
              let number = canonicalNumber(slot: match.num, suffix: match.suffix),
              let total = validatedTotal(match.total, numerator: number.value)
        else { return nil }
        return CollectorInfo(
            collectorNumber: number.canonical,
            setCode: nil,
            totalInSet: total
        )
    }

    /// Rung 5: `"TSR 411"` as a complete line.
    private static func parseSetNumber(_ line: String) -> CollectorInfo? {
        let pattern = #/
            (?<set>[A-Za-z0-9]{2,5})\s+
            (?<num>[0-9DOQILSB|oqils]{1,4})(?<suffix>[a-e★†]?)
        /#
        guard let match = line.wholeMatch(of: pattern),
              let setCode = validatedSetCode(match.set),
              let number = canonicalNumber(slot: match.num, suffix: match.suffix)
        else { return nil }
        return CollectorInfo(collectorNumber: number.canonical, setCode: setCode)
    }

    /// Rung 6: a line that is only a collector number (plus optional rarity),
    /// with a guard against standalone copyright years like `"1997"`.
    private static func parseStandaloneNumber(_ line: String) -> CollectorInfo? {
        guard let number = parseNumberLine(line) else { return nil }
        let isYearLike = number.rawSlotLength == 4
            && number.total == nil
            && (1990...1999).contains(number.value)
        guard !isYearLike else { return nil }
        return CollectorInfo(
            collectorNumber: number.canonical,
            setCode: nil,
            totalInSet: number.total,
            rarityLetter: number.rarity
        )
    }

    // MARK: Component parsers

    private struct NumberLine {
        var canonical: String
        var value: Int
        var total: Int?
        var rarity: Character?
        var rawSlotLength: Int
    }

    /// Matches a whole line of the shape `number[suffix][/total] [rarity]`.
    private static func parseNumberLine(_ line: String) -> NumberLine? {
        let pattern = #/
            (?<num>[0-9DOQILSB|oqils]{1,4})(?<suffix>[a-e★†]?)
            (?:\/(?<total>[0-9DOQILSB|oqils]{1,4}))?
            (?:\s+(?<rarity>[CULRMSTP]))?
        /#
        guard let match = line.wholeMatch(of: pattern),
              let number = canonicalNumber(slot: match.num, suffix: match.suffix)
        else { return nil }

        var total: Int?
        if let totalSlot = match.total {
            guard let validated = validatedTotal(totalSlot, numerator: number.value) else { return nil }
            total = validated
        }
        return NumberLine(
            canonical: number.canonical,
            value: number.value,
            total: total,
            rarity: match.rarity.flatMap(\.first),
            rawSlotLength: match.num.count
        )
    }

    /// Matches a line beginning `SET • LANG`, tolerating bullet variants
    /// (`•`, `·`, `*`, `.`, dashes) or a missing bullet, and ignoring the
    /// artist credit that follows.
    private static func parseSetLanguagePrefix(_ line: String) -> (setCode: String, language: String)? {
        let pattern = #/
            ^(?<set>[A-Za-z0-9]{2,5})\s*[•·∙.*—–-]?\s*
            (?<lang>ZHS|ZHT|ZH|EN|DE|FR|IT|ES|PT|JA|JP|KO|RU|PH)\b
        /#
        guard let match = line.firstMatch(of: pattern),
              let setCode = validatedSetCode(match.set)
        else { return nil }
        return (setCode, String(match.lang))
    }

    // MARK: Validity gates

    /// Canonicalizes a numeric slot + suffix into a collector number,
    /// enforcing the 1…1999 range and stripping leading zeros.
    private static func canonicalNumber(
        slot: Substring,
        suffix: Substring
    ) -> (canonical: String, value: Int)? {
        guard let digits = DigitDeconfuser.canonicalDigits(slot),
              let value = Int(digits),
              (1...1999).contains(value)
        else { return nil }
        return ("\(value)\(suffix)", value)
    }

    /// Validates a fraction denominator: at least 20 (rejects power/toughness
    /// shapes) and not wildly smaller than the numerator.
    private static func validatedTotal(_ slot: Substring, numerator: Int) -> Int? {
        guard let digits = DigitDeconfuser.canonicalDigits(slot),
              let total = Int(digits),
              total >= 20, total <= 2999,
              numerator <= total + 50
        else { return nil }
        return total
    }

    /// Validates a set-code slot: 2–5 ASCII alphanumerics with at least one
    /// letter, and not a language code or legal-text word. Never deconfused.
    private static func validatedSetCode(_ slot: Substring) -> String? {
        let code = slot.uppercased()
        guard (2...5).contains(code.count),
              code.contains(where: \.isLetter),
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !setCodeDenylist.contains(code),
              !languageCodes.contains(code)
        else { return nil }
        return code
    }
}
