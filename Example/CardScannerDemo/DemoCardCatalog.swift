import CardScanner
import Foundation

/// An in-memory `CardCatalog` for tuning the scanner without a real card
/// database. Grows at runtime via `trust(_:)` — see `DemoCards`.
@Observable
final class DemoCardCatalog: CardCatalog {
    private(set) var printings: [CatalogPrinting] = DemoCards.printings

    func printing(setCode: String, collectorNumber: String) async throws -> CatalogPrinting? {
        printings.first { $0.setCode == setCode && $0.collectorNumber == collectorNumber }
    }

    func candidates(forName name: String, limit: Int) async throws -> [CatalogPrinting] {
        // A real host would search an indexed store; the demo list is small
        // enough to hand everything to the scanner's own similarity ranking.
        guard printings.count > limit else { return printings }
        let matches = printings.filter { $0.name.localizedStandardContains(name) }
        return Array(matches.prefix(limit))
    }

    /// Adds the current reading as a trusted printing so exact-lock testing
    /// works with whatever physical card is in front of the camera.
    func trust(_ candidate: ScanCandidate) {
        guard let setCode = candidate.setCode,
              let collectorNumber = candidate.collectorNumber
        else { return }
        let alreadyKnown = printings.contains {
            $0.setCode == setCode && $0.collectorNumber == collectorNumber
        }
        guard alreadyKnown == false else { return }
        printings.append(
            CatalogPrinting(
                id: UUID().uuidString,
                name: candidate.name ?? "\(setCode) \(collectorNumber)",
                setCode: setCode,
                collectorNumber: collectorNumber
            )
        )
    }
}
