import SwiftUI

/// The scanning chrome drawn over the camera preview: dimmed surround,
/// card-shaped guide, live candidate caption, and lock progress.
struct ScannerGuideOverlay: View {
    var candidate: ScanCandidate?
    var isLocked: Bool

    var body: some View {
        GeometryReader { proxy in
            let guide = CardGuideGeometry.guideRect(in: CGRect(origin: .zero, size: proxy.size))
            ZStack {
                GuideDimmingShape(guide: guide, cornerRadius: guide.width * 0.05)
                    .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: guide.width * 0.05)
                    .strokeBorder(isLocked ? .green : .white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: guide.width, height: guide.height)
                    .position(x: guide.midX, y: guide.midY)
                    .animation(.smooth, value: isLocked)
                GuideCaption(candidate: candidate)
                    .frame(width: guide.width)
                    .position(x: guide.midX, y: guide.maxY + 44)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Live feedback under the guide: the emerging reading and lock progress,
/// or framing guidance until something is read.
struct GuideCaption: View {
    var candidate: ScanCandidate?

    var body: some View {
        VStack(spacing: 6) {
            Text(captionText)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            ProgressView(value: min(max(candidate?.progress ?? 0, 0), 1))
                .tint(.green)
                .frame(maxWidth: 180)
        }
        .padding(.horizontal)
    }

    private var captionText: String {
        guard let candidate else { return String(localized: "Center the card in the frame") }
        if candidate.needsAlignmentHint {
            return String(localized: "No match — adjust framing")
        }
        var parts: [String] = []
        if let name = candidate.name {
            parts.append(name)
        }
        if let number = candidate.collectorNumber {
            let printing = [candidate.setCode, number].compactMap(\.self).joined(separator: " ")
            parts.append(printing)
        }
        guard parts.isEmpty == false else {
            return String(localized: "Reading…")
        }
        return parts.joined(separator: " · ")
    }
}
