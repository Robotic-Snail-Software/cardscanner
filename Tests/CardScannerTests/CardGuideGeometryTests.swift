@testable import CardScanner
import CoreGraphics
import Testing

struct CardGuideGeometryTests {
    private let portraitView = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let portraitBuffer = CGSize(width: 1080, height: 1920)

    @Test func guideKeepsCardAspectRatio() {
        let guide = CardGuideGeometry.guideRect(in: portraitView)
        #expect(abs(guide.width / guide.height - CardGuideGeometry.cardAspectRatio) < 0.001)
        #expect(abs(guide.midX - portraitView.midX) < 0.001)
        #expect(abs(guide.midY - portraitView.midY) < 0.001)
    }

    @Test func guideClampsToShortViews() {
        let squarish = CGRect(x: 0, y: 0, width: 800, height: 500)
        let guide = CardGuideGeometry.guideRect(in: squarish)
        #expect(guide.height <= squarish.height * 0.70 + 0.001)
        #expect(abs(guide.width / guide.height - CardGuideGeometry.cardAspectRatio) < 0.001)
    }

    @Test func bandsStayInsideTheGuide() {
        let guide = CardGuideGeometry.guideRect(in: portraitView)
        #expect(guide.contains(CardGuideGeometry.nameBand(inGuide: guide)))
        #expect(guide.contains(CardGuideGeometry.collectorBand(inGuide: guide)))
    }

    @Test func collectorBandExcludesThePowerToughnessCorner() {
        let guide = CardGuideGeometry.guideRect(in: portraitView)
        let band = CardGuideGeometry.collectorBand(inGuide: guide)
        #expect(band.maxX < guide.minX + guide.width * 0.75)
        #expect(band.minY > guide.midY, "collector band sits in the lower half")
    }

    @Test func identityMappingWhenBufferMatchesView() {
        // 540×960 shares the buffer's 0.5625 aspect ratio, so aspect-fill has
        // no crop and the mapping reduces to normalization plus the Y flip.
        let matchedView = CGRect(x: 0, y: 0, width: 540, height: 960)
        let viewRect = CGRect(x: 135, y: 720, width: 270, height: 120)
        let region = CardGuideGeometry.visionRegion(
            forViewRect: viewRect,
            viewBounds: matchedView,
            bufferSize: portraitBuffer
        )
        #expect(region != nil)
        if let region {
            #expect(abs(region.minX - 0.25) < 0.001)
            #expect(abs(region.width - 0.50) < 0.001)
            // View y 720–840 of 960, flipped: 1 − 840/960 = 0.125.
            #expect(abs(region.minY - 0.125) < 0.001)
            #expect(abs(region.height - 0.125) < 0.001)
        }
    }

    @Test func aspectFillCropIsCompensated() {
        // A wider view than the buffer forces vertical overflow: the buffer
        // is scaled to cover the width and cropped top/bottom equally.
        let wideView = CGRect(x: 0, y: 0, width: 400, height: 400)
        let viewRect = CGRect(x: 0, y: 0, width: 400, height: 400)
        let region = CardGuideGeometry.visionRegion(
            forViewRect: viewRect,
            viewBounds: wideView,
            bufferSize: portraitBuffer
        )
        #expect(region != nil)
        if let region {
            // Full width survives; height is the visible middle band.
            #expect(abs(region.minX - 0) < 0.001)
            #expect(abs(region.width - 1) < 0.001)
            #expect(abs(region.height - (400.0 / (1920.0 * (400.0 / 1080.0)))) < 0.001)
            #expect(abs(region.midY - 0.5) < 0.001, "crop is centered")
        }
    }

    @Test func degenerateInputsReturnNil() {
        #expect(CardGuideGeometry.visionRegion(
            forViewRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            viewBounds: .zero,
            bufferSize: portraitBuffer
        ) == nil)
        #expect(CardGuideGeometry.visionRegion(
            forViewRect: CGRect(x: -500, y: -500, width: 10, height: 10),
            viewBounds: CGRect(x: 0, y: 0, width: 400, height: 800),
            bufferSize: portraitBuffer
        ) == nil, "rects fully outside the buffer clamp to empty")
    }
}
