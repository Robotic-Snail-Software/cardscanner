import Foundation

/// A confirmed scan, delivered once per locked card via
/// `CardScannerModel.onCardLocked`.
public nonisolated struct ScannedCard: Identifiable, Equatable, Sendable {
    /// Unique per scan event (scanning four copies yields four cards).
    public let id: UUID

    /// The host catalog's stable identifier for the resolved printing —
    /// `CatalogPrinting.id`. `nil` only for `.nameOnly` results whose
    /// printing is ambiguous; `alternates` then carries the options.
    public var catalogID: String?

    /// Canonical card name from the catalog.
    public var name: String

    /// Uppercase set code of the resolved printing, when known.
    public var setCode: String?

    /// Collector number of the resolved printing, when known.
    public var collectorNumber: String?

    /// How the identification was verified.
    public var confidence: ScanConfidence

    /// Candidate printings for `.nameOnly` results, for host picker UIs.
    public var alternates: [CatalogPrinting]

    public init(
        id: UUID = UUID(),
        catalogID: String?,
        name: String,
        setCode: String?,
        collectorNumber: String?,
        confidence: ScanConfidence,
        alternates: [CatalogPrinting] = []
    ) {
        self.id = id
        self.catalogID = catalogID
        self.name = name
        self.setCode = setCode
        self.collectorNumber = collectorNumber
        self.confidence = confidence
        self.alternates = alternates
    }
}
