import SwiftUI

/// The banner shown while a locked card is displayed: name, printing,
/// confidence badge, and a continue button for `.manual` resume hosts.
struct ScanResultChip: View {
    let card: ScannedCard
    var onContinue: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: badgeSymbol)
                .foregroundStyle(.green)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let onContinue {
                Spacer(minLength: 4)
                Button("Next Card", systemImage: "arrow.forward.circle.fill", action: onContinue)
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var badgeSymbol: String {
        switch card.confidence {
        case .exactPrinting: "checkmark.seal.fill"
        case .printingOnly: "checkmark.seal"
        case .nameOnly: "textformat"
        }
    }

    private var subtitle: String {
        if let setCode = card.setCode, let number = card.collectorNumber {
            return "\(setCode) · \(number)"
        }
        if card.alternates.count > 1 {
            return String(localized: "Matched by name — \(card.alternates.count) printings")
        }
        return String(localized: "Matched by name")
    }
}
