import CoreGraphics

/// The two recognition regions, normalized to the captured image with a
/// lower-left origin (Vision's coordinate space).
///
/// The scanner view recomputes these from the on-screen card guide via
/// `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(fromLayerRect:)`
/// whenever layout changes — never with hand-rolled math (a recurring bug
/// source in earlier prototypes). The static default approximates a centered
/// card guide in a portrait 16:9 frame and only matters before first layout.
nonisolated struct ScanRegions: Equatable, Sendable {
    /// Band over the card's title line.
    var nameBand: CGRect

    /// Band over the bottom-left collector info (number, set code, language).
    var collectorBand: CGRect

    /// Fallback for a card guide ~78% of frame width, centered, in portrait.
    static let `default` = ScanRegions(
        nameBand: CGRect(x: 0.11, y: 0.72, width: 0.78, height: 0.10),
        collectorBand: CGRect(x: 0.11, y: 0.17, width: 0.55, height: 0.12)
    )
}
