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

        let collectorLines = orderedLines(from: collectorObservations)
        return FrameReading(
            name: nameReading(from: nameObservations),
            collector: collectorReading(fromOrderedLines: collectorLines),
            collectorLines: collectorLines.map(\.string)
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
