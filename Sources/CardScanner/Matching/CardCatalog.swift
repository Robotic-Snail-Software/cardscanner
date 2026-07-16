/// The lookup surface a host app provides so the scanner can verify OCR
/// readings against a real card database.
///
/// The protocol is main-actor isolated (the package default), so a SwiftData-
/// backed conformance can use its `ModelContext` directly. Lookups are
/// memoized by the scanner — each distinct reading hits the catalog once, not
/// once per frame.
public protocol CardCatalog {
    /// The printing with this exact set code and collector number, or `nil`.
    ///
    /// - Parameters:
    ///   - setCode: Uppercase set code, e.g. `"MID"`.
    ///   - collectorNumber: Leading zeros stripped, suffix preserved,
    ///     e.g. `"117"` or `"118a"`.
    func printing(setCode: String, collectorNumber: String) async throws -> CatalogPrinting?

    /// Cards whose name plausibly matches an OCR reading, for the name-only
    /// fallback (older frames without printed set information).
    ///
    /// Hosts should search case-insensitively and may return multiple
    /// printings of the same name; the scanner deduplicates and ranks by
    /// string similarity.
    func candidates(forName name: String, limit: Int) async throws -> [CatalogPrinting]
}
