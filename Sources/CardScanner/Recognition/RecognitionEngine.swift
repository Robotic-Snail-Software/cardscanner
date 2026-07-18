import CoreGraphics
import Foundation
import Vision

/// Runs Vision text recognition on camera frames — the only compute loop off
/// the main actor.
///
/// Exactly two requests per frame (a lesson from earlier prototypes that ran
/// seven): one over the title band, one over the collector-info band. Both
/// use the `.accurate` recognizer — accuracy is the stated priority, small
/// regions keep it cheap, and the latest-frame-only stream absorbs latency.
/// Language correction stays off: it "fixes" proper nouns like card names,
/// and the catalog cross-check is a far better corrector.
actor RecognitionEngine {
    private var regions: ScanRegions

    init(regions: ScanRegions = .default) {
        self.regions = regions
    }

    /// Called by the scanner view when layout-derived regions change.
    func updateRegions(_ regions: ScanRegions) {
        self.regions = regions
    }

    /// Recognizes and parses a single frame.
    ///
    /// A fast rectangle-detection pass locates the card first, and the text
    /// bands are derived from the *detected card*, not the on-screen guide —
    /// users rarely fill the guide exactly, and guide-anchored bands end up
    /// reading the table around the card. The guide-derived regions remain
    /// the fallback whenever nothing card-shaped is found.
    func read(_ frame: VideoFrame) async throws -> FrameReading {
        let handler = ImageRequestHandler(frame.pixelBuffer, orientation: frame.orientation)

        let cardRect = await detectCardRect(with: handler, in: frame)
        let nameBand = cardRect.map(CardGuideGeometry.visionNameBand(inCard:)) ?? regions.nameBand
        let collectorBand = cardRect.map(CardGuideGeometry.visionCollectorBand(inCard:)) ?? regions.collectorBand

        let nameRequest = makeRequest(region: nameBand)
        let collectorRequest = makeRequest(region: collectorBand)

        let (nameObservations, collectorObservations): ([RecognizedTextObservation], [RecognizedTextObservation])
        do {
            (nameObservations, collectorObservations) = try await handler.perform(nameRequest, collectorRequest)
        } catch {
            throw ScannerError.recognitionFailed(String(describing: error))
        }

        let collectorLines = orderedLines(from: collectorObservations)
        return FrameReading(
            name: nameReading(from: nameObservations),
            collector: collectorReading(fromOrderedLines: collectorLines),
            collectorLines: collectorLines.map(\.string),
            cardDetected: cardRect != nil
        )
    }

    /// The most card-like rectangle in the frame, or `nil`. Detection
    /// failures are treated as "no card" — the guide fallback still scans.
    private func detectCardRect(with handler: ImageRequestHandler, in frame: VideoFrame) async -> CGRect? {
        var request = DetectRectanglesRequest()
        request.minimumAspectRatio = 0.5
        request.maximumAspectRatio = 1.0
        // Loose size floor so a card in a fixed-distance rig still tracks
        // while the user dials in zoom; the aspect gate below keeps
        // non-card rectangles out.
        request.minimumSize = 0.12
        request.minimumConfidence = 0.5
        request.maximumObservations = 4
        request.quadratureToleranceDegrees = 20

        guard let observations = try? await handler.perform(request) else { return nil }

        let bufferWidth = CGFloat(CVPixelBufferGetWidth(frame.pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(frame.pixelBuffer))
        let cardAspect = CardGuideGeometry.cardAspectRatio

        let candidates = observations.compactMap { observation -> (rect: CGRect, score: CGFloat)? in
            let rect = observation.boundingBox.cgRect
            guard rect.width > 0, rect.height > 0 else { return nil }
            let pixelAspect = (rect.width * bufferWidth) / (rect.height * bufferHeight)
            // An upright Magic card is ~0.716; allow tilt and perspective.
            guard (0.55...0.90).contains(pixelAspect) else { return nil }
            guard rect.width * rect.height >= 0.02 else { return nil }
            let score = CGFloat(observation.confidence) - abs(pixelAspect - cardAspect)
            return (rect, score)
        }
        return candidates.max { $0.score < $1.score }?.rect
    }

    private func makeRequest(region: CGRect) -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.regionOfInterest = NormalizedRect(normalizedRect: region)
        return request
    }

    private func nameReading(from observations: [RecognizedTextObservation]) -> FrameReading.NameReading? {
        let candidates = observations.compactMap { observation -> TextCandidate? in
            guard let top = observation.topCandidates(1).first else { return nil }
            return TextCandidate(
                string: top.string,
                confidence: Double(top.confidence),
                boundingBox: observation.boundingBox.cgRect
            )
        }
        guard let best = NameCandidateScorer.bestName(from: candidates) else { return nil }
        return FrameReading.NameReading(text: best.name, confidence: best.confidence)
    }

    /// Collector-band lines in reading order — lower-left-origin boxes mean
    /// the top line has the larger midY.
    private func orderedLines(
        from observations: [RecognizedTextObservation]
    ) -> [(string: String, confidence: Double)] {
        observations
            .sorted { $0.boundingBox.cgRect.midY > $1.boundingBox.cgRect.midY }
            .compactMap { observation in
                observation.topCandidates(1).first.map {
                    (string: $0.string, confidence: Double($0.confidence))
                }
            }
    }

    private func collectorReading(
        fromOrderedLines lines: [(string: String, confidence: Double)]
    ) -> FrameReading.CollectorReading? {
        guard lines.isEmpty == false,
              let info = CollectorLineParser.parse(lines: lines.map(\.string))
        else { return nil }
        let confidence = lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        return FrameReading.CollectorReading(info: info, confidence: confidence)
    }
}
