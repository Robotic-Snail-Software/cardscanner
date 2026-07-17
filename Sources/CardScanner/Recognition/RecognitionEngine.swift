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
    func read(_ frame: VideoFrame) async throws -> FrameReading {
        let nameRequest = makeRequest(region: regions.nameBand)
        let collectorRequest = makeRequest(region: regions.collectorBand)

        let handler = ImageRequestHandler(frame.pixelBuffer, orientation: frame.orientation)
        let (nameObservations, collectorObservations): ([RecognizedTextObservation], [RecognizedTextObservation])
        do {
            (nameObservations, collectorObservations) = try await handler.perform(nameRequest, collectorRequest)
        } catch {
            throw ScannerError.recognitionFailed(String(describing: error))
        }

        return FrameReading(
            name: nameReading(from: nameObservations),
            collector: collectorReading(from: collectorObservations)
        )
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

    private func collectorReading(from observations: [RecognizedTextObservation]) -> FrameReading.CollectorReading? {
        guard observations.isEmpty == false else { return nil }
        // Deliver lines to the parser in reading order — lower-left-origin
        // boxes mean the top line has the larger midY.
        let orderedLines = observations
            .sorted { $0.boundingBox.cgRect.midY > $1.boundingBox.cgRect.midY }
            .compactMap { $0.topCandidates(1).first }
        guard let info = CollectorLineParser.parse(lines: orderedLines.map(\.string)) else { return nil }

        let confidence = orderedLines.map { Double($0.confidence) }.reduce(0, +) / Double(orderedLines.count)
        return FrameReading.CollectorReading(info: info, confidence: confidence)
    }
}
