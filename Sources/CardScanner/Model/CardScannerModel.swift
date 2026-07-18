import CoreGraphics
import Foundation
import Observation

/// The scanner's public face: an observable model that owns the whole
/// pipeline — camera, recognition, vote accumulation, catalog verification,
/// and the lock state machine.
///
/// Typical hosting:
///
/// ```swift
/// let model = CardScannerModel(catalog: myCatalog)
/// model.onCardLocked = { scanned in addToCollection(scanned) }
/// // …
/// CardScannerView(model: model)   // runs model.start() in its .task
/// ```
///
/// `start()` runs the pipeline until the surrounding task is cancelled or
/// `stop()` is called, so hosting it in a SwiftUI `.task` gives automatic
/// teardown on disappear.
@Observable
public final class CardScannerModel {
    /// Lifecycle state; see `ScanPhase`.
    public private(set) var phase: ScanPhase = .idle

    /// Live best guess and lock progress while searching.
    public private(set) var liveCandidate: ScanCandidate?

    /// Camera permission state, for settings-redirect UIs.
    public private(set) var authorization: CameraAuthorization = .notDetermined

    /// Total cards locked this session — also a convenient haptic trigger.
    public private(set) var lockCount = 0

    /// Pixel size of delivered camera buffers, for view→buffer region
    /// mapping. `nil` until the session starts (or when rotation is
    /// unavailable, in which case default regions stay in effect).
    private(set) var captureBufferSize: CGSize?

    /// Raw OCR lines from the collector band on the most recent frame,
    /// before parsing — for tuning and debug overlays.
    public private(set) var debugCollectorLines: [String] = []

    /// Torch control for dim lighting.
    public var isTorchOn = false {
        didSet {
            let isOn = isTorchOn
            Task { await capture.setTorch(isOn) }
        }
    }

    /// Fired once per locked card, before any auto-resume pause begins.
    public var onCardLocked: ((ScannedCard) -> Void)?

    private let catalog: any CardCatalog
    private let configuration: ScannerConfiguration
    private let capture: CameraCaptureService
    private let engine: RecognitionEngine
    private let clock = ContinuousClock()

    private var accumulator: ObservationAccumulator
    private var answers = CatalogAnswers()
    private var pendingLookups: [ScanDecision.Lookup] = []
    private var cardScanStart: ContinuousClock.Instant?
    private var resumeTask: Task<Void, Never>?
    private var consecutiveCatalogFailures = 0

    public init(catalog: any CardCatalog, configuration: ScannerConfiguration = ScannerConfiguration()) {
        self.catalog = catalog
        self.configuration = configuration
        capture = CameraCaptureService(configuration: configuration.camera)
        engine = RecognitionEngine()
        accumulator = ObservationAccumulator(halfLife: configuration.decayHalfLife)
    }

    // MARK: Lifecycle

    /// Requests camera access, starts the session, and processes frames until
    /// the surrounding task is cancelled or `stop()` is called.
    public func start() async {
        guard phase == .idle || isFailed else { return }

        authorization = await CameraAuthorization.request()
        guard authorization == .authorized else {
            phase = .failed(.cameraPermissionDenied)
            return
        }

        let frames: AsyncStream<VideoFrame>
        do {
            let started = try await capture.startStreaming()
            frames = started.frames
            captureBufferSize = started.bufferSize
        } catch {
            phase = .failed((error as? ScannerError) ?? .cameraConfigurationFailed)
            return
        }

        beginNextCard()
        await processFrames(frames)

        resumeTask?.cancel()
        resumeTask = nil
        await capture.stopStreaming()
        if isFailed == false {
            phase = .idle
        }
    }

    /// Ends the frame stream, which unwinds `start()`.
    public func stop() {
        Task { await capture.stopStreaming() }
    }

    /// After a lock (with `.manual` auto-resume), starts scanning the next card.
    public func resumeScanning() {
        guard case .locked = phase else { return }
        resumeTask?.cancel()
        resumeTask = nil
        beginNextCard()
    }

    // MARK: Pipeline

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func beginNextCard() {
        accumulator.reset()
        pendingLookups.removeAll()
        liveCandidate = nil
        cardScanStart = clock.now
        phase = .searching
    }

    private func processFrames(_ frames: AsyncStream<VideoFrame>) async {
        for await frame in frames {
            guard Task.isCancelled == false else { break }
            guard phase == .searching else { continue }

            let reading: FrameReading
            do {
                reading = try await engine.read(frame)
            } catch {
                continue // Transient recognition failure; the next frame retries.
            }

            debugCollectorLines = reading.collectorLines
            record(reading)
            decide()
            if pendingLookups.isEmpty == false {
                await performPendingLookups()
                decide()
            }
        }
    }

    private func record(_ reading: FrameReading) {
        guard let elapsed = elapsedForCurrentCard() else { return }
        if let name = reading.name {
            accumulator.recordName(name.text, confidence: name.confidence, at: elapsed)
        }
        if let collector = reading.collector {
            accumulator.recordCollector(collector.info, confidence: collector.confidence, at: elapsed)
        }
    }

    private func decide() {
        guard phase == .searching, let elapsed = elapsedForCurrentCard() else { return }

        let decision = ScanResolver.decide(
            names: accumulator.rankedNames(at: elapsed),
            collectors: accumulator.rankedCollectors(at: elapsed),
            answers: answers,
            elapsed: elapsed,
            configuration: configuration
        )

        liveCandidate = ScanCandidate(
            name: decision.leadingName,
            setCode: decision.leadingCollector?.setCode,
            collectorNumber: decision.leadingCollector?.collectorNumber,
            progress: decision.progress,
            needsAlignmentHint: decision.hint == .checkAlignment
        )
        pendingLookups = decision.neededLookups

        if let lock = decision.lock {
            finalize(lock)
        }
    }

    private func elapsedForCurrentCard() -> Duration? {
        cardScanStart.map { clock.now - $0 }
    }

    private func performPendingLookups() async {
        let lookups = pendingLookups
        pendingLookups.removeAll()

        for lookup in lookups {
            do {
                switch lookup {
                case .printing(let setCode, let collectorNumber):
                    let key = CatalogAnswers.PrintingKey(setCode: setCode, collectorNumber: collectorNumber)
                    guard answers.printings.index(forKey: key) == nil else { continue }
                    let printing = try await catalog.printing(setCode: setCode, collectorNumber: collectorNumber)
                    answers.printings.updateValue(printing, forKey: key)

                case .nameCandidates(let name):
                    let key = TextNormalizer.foldedForMatching(name)
                    guard answers.nameCandidates.index(forKey: key) == nil else { continue }
                    answers.nameCandidates[key] = try await catalog.candidates(
                        forName: name,
                        limit: configuration.nameCandidateLimit
                    )
                }
                consecutiveCatalogFailures = 0
            } catch {
                // Transient failures retry on later frames; a persistently
                // broken catalog fails the session rather than spinning.
                consecutiveCatalogFailures += 1
                if consecutiveCatalogFailures >= 5 {
                    phase = .failed(.catalogFailed(String(describing: error)))
                }
            }
        }
    }

    private func finalize(_ lock: ScanDecision.Lock) {
        let card = ScannedCard(
            id: UUID(),
            catalogID: lock.printing?.id,
            name: lock.name,
            setCode: lock.printing?.setCode,
            collectorNumber: lock.printing?.collectorNumber,
            confidence: lock.confidence,
            alternates: lock.alternates
        )
        phase = .locked(card)
        liveCandidate = nil
        lockCount += 1
        onCardLocked?(card)

        if case .after(let delay) = configuration.autoResume {
            resumeTask = Task { [weak self] in
                try? await self?.clock.sleep(for: delay)
                guard Task.isCancelled == false else { return }
                self?.resumeFromAutoResume()
            }
        }
    }

    private func resumeFromAutoResume() {
        guard case .locked = phase else { return }
        beginNextCard()
    }

    // MARK: Scanner view support

    /// The preview connector for `CameraPreviewView`.
    var previewSource: PreviewSource { capture.previewSource }

    /// True when the host must call `resumeScanning()` after each lock.
    var configurationRequiresManualResume: Bool {
        configuration.autoResume == .manual
    }

    /// Forwards layout-derived recognition regions to the engine.
    func updateScanRegions(_ regions: ScanRegions) {
        Task { await engine.updateRegions(regions) }
    }
}
