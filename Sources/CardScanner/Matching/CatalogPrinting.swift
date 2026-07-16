/// A single printing in the host app's card catalog, identified the same way
/// the scanner reads cards: set code plus collector number.
public nonisolated struct CatalogPrinting: Hashable, Sendable, Identifiable {
    /// The host's stable identifier for this printing (the MTGJSON `uuid` in
    /// MyMTG). Returned unchanged in scan results so the host can resolve the
    /// full card model without another search.
    public var id: String

    /// The card's full English name. Multi-face cards use the joined form,
    /// e.g. `"Delver of Secrets // Insectile Aberration"`.
    public var name: String

    /// Uppercase set code, e.g. `"MID"`.
    public var setCode: String

    /// Collector number with leading zeros stripped and any suffix preserved,
    /// e.g. `"117"` or `"118a"` — the MTGJSON `number` convention.
    public var collectorNumber: String

    public init(id: String, name: String, setCode: String, collectorNumber: String) {
        self.id = id
        self.name = name
        self.setCode = setCode
        self.collectorNumber = collectorNumber
    }
}
