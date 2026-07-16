/// The structured result of parsing a card's collector-info line(s).
///
/// The type itself enforces the strict pairing guard learned from earlier
/// prototypes: `collectorNumber` is non-optional while `setCode` is optional,
/// so a set code can never be produced without a collector number backing it.
nonisolated struct CollectorInfo: Hashable, Sendable {
    /// Canonical collector number: leading zeros stripped, lowercase suffix
    /// preserved (`"0117"` → `"117"`, `"118a"` stays `"118a"`).
    /// Matches the MTGJSON `number` convention used by host catalogs.
    var collectorNumber: String

    /// Uppercase printed set code (e.g. `"MID"`), if one was read.
    var setCode: String?

    /// The denominator of a `117/277`-style fraction, if printed.
    var totalInSet: Int?

    /// The printed language token (e.g. `"EN"`, `"JA"`), if read.
    var languageCode: String?

    /// The printed rarity letter (`C`, `U`, `R`, `M`, …), if read.
    var rarityLetter: Character?
}
