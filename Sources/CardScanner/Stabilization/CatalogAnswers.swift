/// Memoized catalog lookup results, maintained by the scanner model and read
/// by the pure `ScanResolver`.
///
/// Key presence means "this lookup has completed" — a stored `nil` printing
/// records a confirmed miss, which is decision-relevant (it triggers the
/// check-alignment hint instead of a lock).
nonisolated struct CatalogAnswers: Sendable {
    struct PrintingKey: Hashable, Sendable {
        var setCode: String
        var collectorNumber: String
    }

    /// Completed exact-printing lookups. `nil` value = catalog miss.
    var printings: [PrintingKey: CatalogPrinting?] = [:]

    /// Completed name-candidate lookups, keyed by the folded OCR name.
    var nameCandidates: [String: [CatalogPrinting]] = [:]
}
