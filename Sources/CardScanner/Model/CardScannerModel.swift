import CoreGraphics
import Foundation
import Observation
#if os(iOS)
import AudioToolbox
import UIKit
#endif

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

    /// Whether the last frame's text bands tracked a detected card
    /// rectangle (versus the on-screen guide fallback).
    public private(set) var isTrackingCard = false

    /// Torch control for dim lighting. No-op on platforms without capture.
    public var isTorchOn = false {
        didSet {
            #if os(iOS)
            let isOn = isTorchOn
            Task { await capture.setTorch(isOn) }
            #endif
        }
    }

    /// Current zoom factor (1 = no zoom). Set via `setZoom(_:)`.
    public private(set) var zoomFactor: CGFloat = 1

    /// Zooms the camera — for fixed-distance setups (a scanning rig, a
    /// tripod) where the card can't be brought closer to fill the guide.
    /// Clamped to 1…8; camera-less platforms ignore it.
    public func setZoom(_ factor: CGFloat) {
        zoomFactor = min(max(factor, 1), 8)
        #if os(iOS)
        let target = zoomFactor
        Task { await capture.setZoom(target) }
        #endif
    }

    /// Fired once per locked card, before any auto-resume pause begins.
    public var onCardLocked: ((ScannedCard) -> Void)?

    private let catalog: any CardCatalog
    private let configuration: ScannerConfiguration
    #if os(iOS)
    private let capture: CameraCaptureService
    #endif
    private let engine: RecognitionEngine
    private let clock = ContinuousClock()

    private var accumulator: ObservationAccumulator
    private var setHintVotes: [String: Double] = [:]
    private var answers = CatalogAnswers()
    private var pendingLookups: [ScanDecision.Lookup] = []
    private var cardScanStart: ContinuousClock.Instant?
    private var resumeTask: Task<Void, Never>?
    private var consecutiveCatalogFailures = 0
    private var lastLockedIdentity: String?
    private var lastLockTime: ContinuousClock.Instant?
    private var cardLeftFrameSinceLock = true

    public init(catalog: any CardCatalog, configuration: ScannerConfiguration = ScannerConfiguration()) {
        self.catalog = catalog
        self.configuration = configuration
        #if os(iOS)
        capture = CameraCaptureService(configuration: configuration.camera)
        #endif
        engine = RecognitionEngine()
        accumulator = ObservationAccumulator(halfLife: configuration.decayHalfLife)
    }

    // MARK: Lifecycle

    /// Requests camera access, starts the session, and processes frames until
    /// the surrounding task is cancelled or `stop()` is called.
    ///
    /// On platforms without camera capture (visionOS), fails immediately
    /// with `.cameraUnavailable`.
    public func start() async {
        #if os(iOS)
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

        // Hands-free scanning (a rig, a stack) means no touches — keep the
        // screen awake for the session, restored on any exit path.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // Zoom set before the session existed (e.g. a persisted level)
        // applies now that the device is configured.
        if zoomFactor != 1 {
            await capture.setZoom(zoomFactor)
        }

        beginNextCard()
        await processFrames(frames)

        resumeTask?.cancel()
        resumeTask = nil
        await capture.stopStreaming()
        if isFailed == false {
            phase = .idle
        }
        #else
        phase = .failed(.cameraUnavailable)
        #endif
    }

    /// Ends the frame stream, which unwinds `start()`.
    public func stop() {
        #if os(iOS)
        Task { await capture.stopStreaming() }
        #endif
    }

    /// After a lock (with `.manual` auto-resume), starts scanning the next card.
    public func resumeScanning() {
        guard case .locked = phase else { return }
        resumeTask?.cancel()
        resumeTask = nil
        beginNextCard()
    }

    /// Discards memoized catalog answers. Call after mutating the catalog
    /// (adding cards, syncing) so cached misses don't mask new entries.
    public func invalidateCatalogCache() {
        answers = CatalogAnswers()
        pendingLookups.removeAll()
    }

    // MARK: Pipeline

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func beginNextCard() {
        accumulator.reset()
        setHintVotes.removeAll()
        pendingLookups.removeAll()
        liveCandidate = nil
        cardScanStart = clock.now
        phase = .searching
    }

    private func processFrames(_ frames: AsyncStream<VideoFrame>) async {
        var lastReadFinished: ContinuousClock.Instant?
        var lastPassSawCard = true // optimistic: the first card snaps quickly
        for await frame in frames {
            guard Task.isCancelled == false else { break }
            guard phase == .searching else { continue }

            // Adaptive pacing: read quickly while a card is in view (fast
            // locks), slowly while staring at nothing (cool device) —
            // instead of one compromise rate for both.
            let interval = lastPassSawCard
                ? configuration.recognitionInterval
                : configuration.idleRecognitionInterval
            if let lastReadFinished, clock.now - lastReadFinished < interval {
                continue
            }

            let reading: FrameReading
            do {
                reading = try await engine.read(frame)
                lastReadFinished = clock.now
                lastPassSawCard = reading.cardDetected
            } catch {
                continue // Transient recognition failure; the next frame retries.
            }

            debugCollectorLines = reading.collectorLines
            isTrackingCard = reading.cardDetected
            if reading.cardDetected == false {
                cardLeftFrameSinceLock = true
            }
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
        if let setHint = reading.setHint {
            setHintVotes[setHint, default: 0] += 1
        }
    }

    /// The set code read most often when the number couldn't be parsed.
    private var leadingSetHint: String? {
        setHintVotes.max { $0.value < $1.value }?.key
    }

    private func decide() {
        guard phase == .searching, let elapsed = elapsedForCurrentCard() else { return }

        let decision = ScanResolver.decide(
            names: accumulator.rankedNames(at: elapsed),
            collectors: accumulator.rankedCollectors(at: elapsed),
            answers: answers,
            elapsed: elapsed,
            setHint: leadingSetHint,
            configuration: configuration
        )

        liveCandidate = ScanCandidate(
            name: decision.leadingName,
            setCode: decision.leadingCollector?.setCode,
            collectorNumber: decision.leadingCollector?.collectorNumber,
            progress: decision.progress,
            hint: decision.hint
        )
        pendingLookups = decision.neededLookups

        if let lock = decision.lock {
            // Don't double-count a card that just locked and never left the
            // frame — auto-resume would otherwise re-scan it in place. A
            // brief absence (the hand swapping cards) re-arms it, as does a
            // deliberate lingering pause.
            let identity = lock.printing?.id ?? lock.name
            let lingeredLongEnough = lastLockTime.map { clock.now - $0 > .seconds(5) } ?? true
            if identity == lastLockedIdentity,
               cardLeftFrameSinceLock == false,
               lingeredLongEnough == false {
                return
            }
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
                    var printing = try await catalog.printing(setCode: setCode, collectorNumber: collectorNumber)
                    if printing == nil {
                        printing = try await repairedSetCodeLookup(
                            setCode: setCode,
                            collectorNumber: collectorNumber
                        )
                    }
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

    /// After a confirmed miss, probes OCR look-alike variants of the set
    /// code (never repaired at parse time) against the catalog. A hit is
    /// accepted only when all matching variants agree on one printing — the
    /// catalog itself is the safety check.
    private func repairedSetCodeLookup(
        setCode: String,
        collectorNumber: String
    ) async throws -> CatalogPrinting? {
        var hits: [CatalogPrinting] = []
        for variant in SetCodeRepair.variants(of: setCode) {
            let key = CatalogAnswers.PrintingKey(setCode: variant, collectorNumber: collectorNumber)
            let printing: CatalogPrinting?
            if let cached = answers.printings[key] {
                printing = cached
            } else {
                printing = try await catalog.printing(setCode: variant, collectorNumber: collectorNumber)
                answers.printings.updateValue(printing, forKey: key)
            }
            if let printing {
                hits.append(printing)
            }
        }
        let distinctPrintings = Set(hits.map(\.id))
        return distinctPrintings.count == 1 ? hits.first : nil
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
        lastLockedIdentity = lock.printing?.id ?? lock.name
        lastLockTime = clock.now
        cardLeftFrameSinceLock = false
        #if os(iOS)
        if configuration.playsLockSound {
            AudioServicesPlaySystemSound(1057) // short "tink"
        }
        #endif
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

    #if os(iOS)
    /// The preview connector for `CameraPreviewView`.
    var previewSource: PreviewSource { capture.previewSource }
    #endif

    /// True when the host must call `resumeScanning()` after each lock.
    var configurationRequiresManualResume: Bool {
        configuration.autoResume == .manual
    }

    /// Forwards layout-derived recognition regions to the engine.
    func updateScanRegions(_ regions: ScanRegions) {
        Task { await engine.updateRegions(regions) }
    }
}
