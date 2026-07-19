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

        let lineCandidates = orderedLineCandidates(from: collectorObservations)
        return FrameReading(
            name: nameReading(from: nameObservations),
            collector: collectorReading(fromLineCandidates: lineCandidates),
            collectorLines: lineCandidates.map(\.[0].string),
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

        // Card holders and scanning trays are card-shaped rectangles too, and
        // the card sits INSIDE them — when one plausible rect contains
        // another, the inner one is the card.
        let innermost = candidates.filter { candidate in
            candidates.contains {
                $0.rect != candidate.rect
                    && candidate.rect.insetBy(dx: -0.01, dy: -0.01).contains($0.rect)
            } == false
        }
        return innermost.max { $0.score < $1.score }?.rect
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
    /// the top line has the larger midY. Each line carries Vision's ranked
    /// alternate transcriptions, not just the top one.
    private func orderedLineCandidates(
        from observations: [RecognizedTextObservation]
    ) -> [[(string: String, confidence: Double)]] {
        observations
            .sorted { $0.boundingBox.cgRect.midY > $1.boundingBox.cgRect.midY }
            .compactMap { observation in
                let candidates = observation.topCandidates(3).map {
                    (string: $0.string, confidence: Double($0.confidence))
                }
                return candidates.isEmpty ? nil : candidates
            }
    }

    /// Parses the top transcription of every line; when that fails, retries
    /// with each line's runner-up substituted one at a time — Vision's
    /// second guess is often the correct read of a borderline line.
    private func collectorReading(
        fromLineCandidates lineCandidates: [[(string: String, confidence: Double)]]
    ) -> FrameReading.CollectorReading? {
        guard lineCandidates.isEmpty == false else { return nil }

        var attempts: [[(string: String, confidence: Double)]] = []
        let primary = lineCandidates.map(\.[0])
        attempts.append(primary)
        for index in lineCandidates.indices where lineCandidates[index].count > 1 {
            var variant = primary
            variant[index] = lineCandidates[index][1]
            attempts.append(variant)
        }

        for lines in attempts {
            guard let info = CollectorLineParser.parse(lines: lines.map(\.string)) else { continue }
            // Vision under-reports confidence on very small text, but a
            // reading that survived the parser's structural validity gates
            // is strong evidence regardless — floor its vote so locks
            // accumulate at the paced read rate.
            let visionConfidence = lines.map(\.confidence).reduce(0, +) / Double(lines.count)
            return FrameReading.CollectorReading(info: info, confidence: max(0.6, visionConfidence))
        }
        return nil
    }
}
