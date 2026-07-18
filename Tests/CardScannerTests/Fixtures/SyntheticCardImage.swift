import CoreGraphics
import CoreText
import CoreVideo

/// Renders a synthetic "card" into a pixel buffer so the full
/// recognition → parsing pipeline can run deterministically in tests,
/// with no camera involved.
///
/// Layout mimics a modern frame filling the whole image: title line at the
/// top, collector info at the bottom-left, and decoy text (power/toughness,
/// the trademark line) that the bands and parser must exclude.
nonisolated enum SyntheticCardImage {
    static let size = CGSize(width: 1080, height: 1920)

    struct Line {
        var text: String
        /// Baseline position in bottom-left-origin (CoreGraphics) coordinates.
        var position: CGPoint
        var fontSize: CGFloat
    }

    /// A Bladeback Sliver-shaped test card (MH1 119/254).
    static let bladebackSliver: [Line] = [
        Line(text: "Bladeback Sliver", position: CGPoint(x: 70, y: 1790), fontSize: 64),
        Line(text: "Creature — Sliver", position: CGPoint(x: 70, y: 700), fontSize: 48),
        Line(text: "119/254 C", position: CGPoint(x: 40, y: 170), fontSize: 34),
        Line(text: "MH1 • EN Svetlin Velinov", position: CGPoint(x: 40, y: 120), fontSize: 34),
        Line(text: "2/2", position: CGPoint(x: 950, y: 150), fontSize: 44),
        Line(text: "™ & © 2019 Wizards of the Coast", position: CGPoint(x: 560, y: 40), fontSize: 26),
    ]

    /// The realistic failure scene: the card sits on a desk, smaller than
    /// (and below) where the on-screen guide assumes it, with note-paper
    /// text above it. Guide-anchored bands read the notes and the desk;
    /// only card tracking reads the card.
    static let cardOnDeskFrame = CGRect(x: 146, y: 200, width: 787, height: 1100)

    static let bladebackSliverOnDesk: [Line] = [
        Line(text: "HTML Notes", position: CGPoint(x: 300, y: 1450), fontSize: 48),
        Line(text: "Bladeback Sliver", position: CGPoint(x: 190, y: 1180), fontSize: 40),
        Line(text: "Creature — Sliver", position: CGPoint(x: 190, y: 700), fontSize: 32),
        Line(text: "119/254 C", position: CGPoint(x: 170, y: 300), fontSize: 24),
        Line(text: "MH1 • EN Svetlin Velinov", position: CGPoint(x: 170, y: 255), fontSize: 24),
        Line(text: "2/2", position: CGPoint(x: 800, y: 290), fontSize: 26),
        Line(text: "™ & © 2019 Wizards of the Coast", position: CGPoint(x: 480, y: 215), fontSize: 16),
    ]

    /// Draws the lines onto a pixel buffer — a plain white page, or, when
    /// `cardFrame` is given, a bordered white card on a gray desk.
    static func render(_ lines: [Line], cardFrame: CGRect? = nil) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        if let cardFrame {
            context.setFillColor(CGColor(gray: 0.4, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let cardPath = CGPath(
                roundedRect: cardFrame,
                cornerWidth: 30,
                cornerHeight: 30,
                transform: nil
            )
            context.addPath(cardPath)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
            context.addPath(cardPath)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(6)
            context.strokePath()
        } else {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }

        for line in lines {
            let font = CTFontCreateWithName("Helvetica" as CFString, line.fontSize, nil)
            let attributed = NSAttributedString(string: line.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textPosition = line.position
            CTLineDraw(ctLine, context)
        }
        return pixelBuffer
    }
}
