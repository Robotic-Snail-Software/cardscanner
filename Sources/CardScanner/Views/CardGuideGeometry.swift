import CoreGraphics

/// Single source of truth for the on-screen card guide and its recognition
/// bands, plus the pure view→buffer coordinate mapping.
///
/// Earlier prototypes duplicated untested aspect-fill math across files and
/// it was a recurring bug source. Here the mapping is one deterministic,
/// unit-tested function shared by the overlay (which draws the guide) and
/// the preview view (which converts bands into Vision regions).
nonisolated enum CardGuideGeometry {
    /// A Magic card is 63 mm × 88 mm.
    static let cardAspectRatio: CGFloat = 63.0 / 88.0

    /// The card-shaped guide, centered in the view at 78% width (clamped to
    /// 70% of the height for short/wide layouts). View coordinates.
    static func guideRect(in bounds: CGRect) -> CGRect {
        var width = bounds.width * 0.78
        var height = width / cardAspectRatio
        let maximumHeight = bounds.height * 0.70
        if height > maximumHeight {
            height = maximumHeight
            width = height * cardAspectRatio
        }
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Band over the title line: the top ~12% of the card, inset from the
    /// guide edges so frame border art stays out.
    static func nameBand(inGuide guide: CGRect) -> CGRect {
        CGRect(
            x: guide.minX + guide.width * 0.03,
            y: guide.minY + guide.height * 0.025,
            width: guide.width * 0.94,
            height: guide.height * 0.12
        )
    }

    /// Band over the collector info: the bottom ~12% of the card, left 70%
    /// only — the bottom-right holds power/toughness, which is pure noise.
    static func collectorBand(inGuide guide: CGRect) -> CGRect {
        CGRect(
            x: guide.minX + guide.width * 0.01,
            y: guide.maxY - guide.height * 0.125,
            width: guide.width * 0.70,
            height: guide.height * 0.12
        )
    }

    /// Title band derived from a detected card rectangle in Vision space
    /// (lower-left origin — the card's top is its `maxY` side).
    ///
    /// Detection sometimes returns the card's printed *inner frame* rather
    /// than its outer edge (high-contrast on white-frame cards), so the
    /// band extends slightly beyond the rect to keep the title covered
    /// either way.
    static func visionNameBand(inCard card: CGRect) -> CGRect {
        clampedToUnitSquare(
            CGRect(
                x: card.minX + card.width * 0.03,
                y: card.maxY - card.height * 0.135,
                width: card.width * 0.94,
                height: card.height * 0.17
            )
        )
    }

    /// Collector band derived from a detected card rectangle in Vision
    /// space. Extends below the rect's bottom edge: when detection returns
    /// the inner frame, the collector line sits *outside* it on the border.
    static func visionCollectorBand(inCard card: CGRect) -> CGRect {
        clampedToUnitSquare(
            CGRect(
                x: card.minX + card.width * 0.01,
                y: card.minY - card.height * 0.07,
                width: card.width * 0.70,
                height: card.height * 0.19
            )
        )
    }

    private static func clampedToUnitSquare(_ rect: CGRect) -> CGRect {
        rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Maps a rect in view coordinates (top-left origin) to a normalized
    /// Vision region (lower-left origin) of an aspect-filled capture buffer.
    ///
    /// `.resizeAspectFill` scales the buffer uniformly to cover the view and
    /// centers the overflow; this inverts that transform. Returns `nil` for
    /// degenerate geometry.
    static func visionRegion(
        forViewRect viewRect: CGRect,
        viewBounds: CGRect,
        bufferSize: CGSize
    ) -> CGRect? {
        guard viewBounds.width > 0, viewBounds.height > 0,
              bufferSize.width > 0, bufferSize.height > 0
        else { return nil }

        let scale = max(
            viewBounds.width / bufferSize.width,
            viewBounds.height / bufferSize.height
        )
        let displayedSize = CGSize(
            width: bufferSize.width * scale,
            height: bufferSize.height * scale
        )
        let overflow = CGPoint(
            x: (displayedSize.width - viewBounds.width) / 2,
            y: (displayedSize.height - viewBounds.height) / 2
        )

        let bufferRect = CGRect(
            x: (viewRect.minX - viewBounds.minX + overflow.x) / scale / bufferSize.width,
            y: (viewRect.minY - viewBounds.minY + overflow.y) / scale / bufferSize.height,
            width: viewRect.width / scale / bufferSize.width,
            height: viewRect.height / scale / bufferSize.height
        )

        // Flip from top-left view convention to Vision's lower-left origin.
        let flipped = CGRect(
            x: bufferRect.minX,
            y: 1 - bufferRect.maxY,
            width: bufferRect.width,
            height: bufferRect.height
        )
        let clamped = flipped.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return clamped.isEmpty ? nil : clamped
    }
}
