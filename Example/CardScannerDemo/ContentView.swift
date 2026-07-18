import CardScanner
import SwiftUI

/// The demo harness: scanner on top, scanned stack below, plus a
/// "Trust Reading" control that teaches the in-memory catalog the card
/// currently in front of the camera.
struct ContentView: View {
    @State private var catalog: DemoCardCatalog
    @State private var scanner: CardScannerModel
    @State private var scannedCards: [ScannedCard] = []

    init() {
        let catalog = DemoCardCatalog()
        _catalog = State(initialValue: catalog)
        _scanner = State(initialValue: CardScannerModel(catalog: catalog))
    }

    var body: some View {
        VStack(spacing: 0) {
            CardScannerView(model: scanner)
                .frame(maxHeight: .infinity)
            DemoControlBar(
                scanner: scanner,
                catalogCount: catalog.printings.count,
                onTrustReading: trustCurrentReading
            )
            ScannedStackList(cards: scannedCards)
                .frame(maxHeight: 220)
        }
        .onAppear(perform: configureCallbacks)
    }

    private func configureCallbacks() {
        scanner.onCardLocked = { scannedCards.insert($0, at: 0) }
    }

    private func trustCurrentReading() {
        guard let candidate = scanner.liveCandidate else { return }
        catalog.trust(candidate)
    }
}

/// Catalog size, live-reading state, and the trust action.
struct DemoControlBar: View {
    var scanner: CardScannerModel
    var catalogCount: Int
    var onTrustReading: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Catalog: \(catalogCount) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Trust Reading", systemImage: "plus.viewfinder", action: onTrustReading)
                    .buttonStyle(.borderedProminent)
                    .disabled(canTrust == false)
            }
            Text(debugText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// What Vision read in the collector band on the latest frame, prefixed
    /// with whether the bands tracked a detected card (▣) or fell back to
    /// the guide (□).
    private var debugText: String {
        let tracking = scanner.isTrackingCard ? "▣" : "□"
        let lines = scanner.debugCollectorLines
        return lines.isEmpty ? "\(tracking) OCR: —" : "\(tracking) OCR: \(lines.joined(separator: " ⏎ "))"
    }

    private var canTrust: Bool {
        guard let candidate = scanner.liveCandidate else { return false }
        return candidate.setCode != nil && candidate.collectorNumber != nil
    }
}

/// The cards locked so far this session, newest first.
struct ScannedStackList: View {
    var cards: [ScannedCard]

    var body: some View {
        List(cards) { card in
            ScannedCardRow(card: card)
        }
        .listStyle(.plain)
        .overlay {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No cards scanned yet",
                    systemImage: "rectangle.stack",
                    description: Text("Center a card in the frame above.")
                )
            }
        }
    }
}

struct ScannedCardRow: View {
    var card: ScannedCard

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(confidenceText)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: .capsule)
        }
    }

    private var detailText: String {
        if let setCode = card.setCode, let number = card.collectorNumber {
            return "\(setCode) · \(number)"
        }
        return "Matched by name (\(card.alternates.count) printings)"
    }

    private var confidenceText: String {
        switch card.confidence {
        case .exactPrinting: "Exact"
        case .printingOnly: "Printing"
        case .nameOnly: "Name"
        }
    }
}
