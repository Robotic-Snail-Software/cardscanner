@testable import CardScanner
import CoreGraphics
import Testing

/// Runs the real Vision pipeline (RecognitionEngine + production region
/// mapping) over a synthetic card image — verifying ROI placement, the
/// coordinate flip, and parsing end-to-end with no camera.
struct RecognitionEndToEndTests {
    @Test func readsTitleAndCollectorLineFromSyntheticCard() async throws {
        let pixelBuffer = try #require(SyntheticCardImage.render(SyntheticCardImage.bladebackSliver))

        // The synthetic card fills the frame, so the guide is the whole image
        // and the production band + mapping helpers apply directly.
        let bounds = CGRect(origin: .zero, size: SyntheticCardImage.size)
        let nameBand = try #require(CardGuideGeometry.visionRegion(
            forViewRect: CardGuideGeometry.nameBand(inGuide: bounds),
            viewBounds: bounds,
            bufferSize: SyntheticCardImage.size
        ))
        let collectorBand = try #require(CardGuideGeometry.visionRegion(
            forViewRect: CardGuideGeometry.collectorBand(inGuide: bounds),
            viewBounds: bounds,
            bufferSize: SyntheticCardImage.size
        ))

        let engine = RecognitionEngine(
            regions: ScanRegions(nameBand: nameBand, collectorBand: collectorBand)
        )
        let reading = try await engine.read(VideoFrame(pixelBuffer: pixelBuffer, orientation: .up))

        #expect(reading.name?.text == "Bladeback Sliver")
        #expect(reading.collector?.info.setCode == "MH1")
        #expect(reading.collector?.info.collectorNumber == "119")
        #expect(reading.collector?.info.totalInSet == 254)
        #expect(reading.collector?.info.languageCode == "EN")
    }
}
