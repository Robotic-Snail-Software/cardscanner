/// How a locked scan was verified against the catalog.
public nonisolated enum ScanConfidence: Equatable, Sendable {
    /// Set code + collector number resolved to a printing whose name agrees
    /// with the OCR reading — the exact physical printing is known.
    case exactPrinting

    /// Set code + collector number resolved to a printing, but no usable
    /// name reading confirmed it.
    case printingOnly

    /// No collector line was readable; the card was identified by name.
    /// `ScannedCard.alternates` carries the possible printings.
    case nameOnly
}
