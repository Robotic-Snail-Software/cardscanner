@testable import CardScanner
import Testing

/// A corpus entry: the OCR lines Vision might deliver from the collector
/// band, and the exact parse we expect.
nonisolated struct CollectorLineCase: Sendable, CustomTestStringConvertible {
    var lines: [String]
    var expected: CollectorInfo

    var testDescription: String { lines.joined(separator: " ⏎ ") }
}

/// A corpus entry that must NOT parse — power/toughness, years, legal text,
/// and the strict pairing guard (set code without a collector number).
nonisolated struct CollectorLineRejection: Sendable, CustomTestStringConvertible {
    var lines: [String]
    var reason: String

    var testDescription: String { "\(lines.joined(separator: " ⏎ ")) — \(reason)" }
}

/// Realistic OCR reads of collector-info regions, compiler-checked.
nonisolated enum CollectorLineCorpus {
    static let accepted: [CollectorLineCase] = [
        // Canonical modern two-line reads.
        CollectorLineCase(
            lines: ["0117/0277 M", "MID • EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        CollectorLineCase(
            lines: ["123/269 R", "DOM • EN"],
            expected: CollectorInfo(collectorNumber: "123", setCode: "DOM", totalInSet: 269, languageCode: "EN", rarityLetter: "R")
        ),
        // Bullet variants and a missing bullet.
        CollectorLineCase(
            lines: ["0117/0277 M", "MID · EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        CollectorLineCase(
            lines: ["0117/0277 M", "MID * EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        CollectorLineCase(
            lines: ["0117/0277 M", "MID EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        // Lines delivered in reverse reading order.
        CollectorLineCase(
            lines: ["MID • EN", "0117/0277 M"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        // No printed total (newer collector lines).
        CollectorLineCase(
            lines: ["0123 M", "WOE • EN"],
            expected: CollectorInfo(collectorNumber: "123", setCode: "WOE", totalInSet: nil, languageCode: "EN", rarityLetter: "M")
        ),
        // Both printed lines merged into one observation.
        CollectorLineCase(
            lines: ["0117/0277 M MID • EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        CollectorLineCase(
            lines: ["0117/0277 MID • EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: nil)
        ),
        // Merged observation that swallowed the artist credit too.
        CollectorLineCase(
            lines: ["0117/0277 M MID • EN JOHN AVON"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        // OCR digit confusions repaired in numeric slots only.
        CollectorLineCase(
            lines: ["O117/O277 M", "MID • EN"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "EN", rarityLetter: "M")
        ),
        CollectorLineCase(
            lines: ["0123/026I R", "OTJ • EN"],
            expected: CollectorInfo(collectorNumber: "123", setCode: "OTJ", totalInSet: 261, languageCode: "EN", rarityLetter: "R")
        ),
        // Set codes containing digits must never be "repaired".
        CollectorLineCase(
            lines: ["0033/0264 R", "M21 • EN"],
            expected: CollectorInfo(collectorNumber: "33", setCode: "M21", totalInSet: 264, languageCode: "EN", rarityLetter: "R")
        ),
        CollectorLineCase(
            lines: ["0123/0578 C", "2X2 • EN"],
            expected: CollectorInfo(collectorNumber: "123", setCode: "2X2", totalInSet: 578, languageCode: "EN", rarityLetter: "C")
        ),
        // Non-English language tokens.
        CollectorLineCase(
            lines: ["0117/0277 M", "MID • JA"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "JA", rarityLetter: "M")
        ),
        CollectorLineCase(
            lines: ["0117/0277 M", "MID • ZHS"],
            expected: CollectorInfo(collectorNumber: "117", setCode: "MID", totalInSet: 277, languageCode: "ZHS", rarityLetter: "M")
        ),
        // Collector-number suffix preserved through pairing.
        CollectorLineCase(
            lines: ["118a", "SOI • EN"],
            expected: CollectorInfo(collectorNumber: "118a", setCode: "SOI", totalInSet: nil, languageCode: "EN", rarityLetter: nil)
        ),
        // Single-line set + fraction.
        CollectorLineCase(
            lines: ["OTJ 0123/0271"],
            expected: CollectorInfo(collectorNumber: "123", setCode: "OTJ", totalInSet: 271, languageCode: nil, rarityLetter: nil)
        ),
        // Bare fraction (pre-set-code era bottom line).
        CollectorLineCase(
            lines: ["123/280"],
            expected: CollectorInfo(collectorNumber: "123", setCode: nil, totalInSet: 280, languageCode: nil, rarityLetter: nil)
        ),
        CollectorLineCase(
            lines: ["117a/277"],
            expected: CollectorInfo(collectorNumber: "117a", setCode: nil, totalInSet: 277, languageCode: nil, rarityLetter: nil)
        ),
        // Set + number as a whole line.
        CollectorLineCase(
            lines: ["TSR 411"],
            expected: CollectorInfo(collectorNumber: "411", setCode: "TSR", totalInSet: nil, languageCode: nil, rarityLetter: nil)
        ),
        // Standalone collector numbers.
        CollectorLineCase(
            lines: ["411"],
            expected: CollectorInfo(collectorNumber: "411", setCode: nil, totalInSet: nil, languageCode: nil, rarityLetter: nil)
        ),
        CollectorLineCase(
            lines: ["117 R"],
            expected: CollectorInfo(collectorNumber: "117", setCode: nil, totalInSet: nil, languageCode: nil, rarityLetter: "R")
        ),
        CollectorLineCase(
            lines: ["0007"],
            expected: CollectorInfo(collectorNumber: "7", setCode: nil, totalInSet: nil, languageCode: nil, rarityLetter: nil)
        ),
        // Promo star suffix.
        CollectorLineCase(
            lines: ["21★"],
            expected: CollectorInfo(collectorNumber: "21★", setCode: nil, totalInSet: nil, languageCode: nil, rarityLetter: nil)
        ),
        // Mystery Booster-scale numbers above 999 are legitimate.
        CollectorLineCase(
            lines: ["1694"],
            expected: CollectorInfo(collectorNumber: "1694", setCode: nil, totalInSet: nil, languageCode: nil, rarityLetter: nil)
        ),
    ]

    static let rejected: [CollectorLineRejection] = [
        CollectorLineRejection(lines: ["2/2"], reason: "power/toughness"),
        CollectorLineRejection(lines: ["13/13"], reason: "power/toughness"),
        CollectorLineRejection(lines: ["1997"], reason: "standalone year"),
        CollectorLineRejection(lines: ["EN"], reason: "bare language code"),
        CollectorLineRejection(lines: ["MID • EN"], reason: "set code without collector number"),
        CollectorLineRejection(lines: ["WOTC EN"], reason: "denylisted set code, no number"),
        CollectorLineRejection(lines: ["THE 100"], reason: "denylisted set code"),
        CollectorLineRejection(lines: ["SLD"], reason: "letters-only slot must not be deconfused"),
        CollectorLineRejection(lines: ["Wizards of the Coast"], reason: "legal text"),
        CollectorLineRejection(lines: ["©1993-2024 Wizards of the Coast"], reason: "copyright line"),
        CollectorLineRejection(lines: [], reason: "no input"),
        CollectorLineRejection(lines: ["", "  "], reason: "blank input"),
    ]
}
