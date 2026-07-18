/// Tunable thresholds governing scan stabilization and locking.
///
/// The defaults are tuned for roughly one to two seconds of steady framing
/// per card. Hosts rarely need to change anything except `autoResume`.
public nonisolated struct ScannerConfiguration: Sendable {
    /// Half-life of the exponential decay applied to accumulated votes.
    /// Consistent fresh reads overtake a stale early leader within ~2×.
    /// Tuned together with `recognitionInterval`: at ~6 paced reads/second
    /// the equilibrium weight must comfortably clear the lock thresholds.
    public var decayHalfLife: Duration = .seconds(2.5)

    /// Accumulated weight a set+number reading needs for an
    /// `.exactPrinting` lock (≈ 3 consistent reads at the paced rate).
    public var lockThreshold: Double = 2.0

    /// Higher weight demanded when locking on set+number alone
    /// (`.printingOnly`), because there is no name to cross-check.
    public var printingOnlyLockThreshold: Double = 3.0

    /// Weight the leading name needs before the name-only fallback can lock.
    public var nameOnlyLockThreshold: Double = 2.5

    /// The leading collector reading must outweigh the runner-up by this
    /// factor before any collector-based lock.
    public var lockLeadRatio: Double = 2.0

    /// Minimum OCR-name ↔ catalog-name similarity to count as agreement
    /// in the exact-printing rule. Stylized frames (showcase, borderless)
    /// OCR imperfectly, so this is deliberately forgiving — the set+number
    /// catalog hit is the primary evidence.
    public var nameSimilarityFloor: Double = 0.5

    /// Below this similarity, a strong name reading actively contradicts the
    /// collector reading and vetoes a printing-only lock.
    public var nameContradictionCeiling: Double = 0.3

    /// Name weight required before its contradiction veto applies.
    public var contradictionNameWeight: Double = 2.0

    /// A set-coded collector reading at or above this weight suppresses the
    /// name-only fallback — the collector line is still winning.
    public var strongCollectorWeight: Double = 1.0

    /// Similarity the best catalog name must reach for a name-only lock.
    public var nameOnlySimilarityFloor: Double = 0.85

    /// Margin by which the best catalog name must beat the runner-up name.
    public var nameOnlyLeadMargin: Double = 0.1

    /// How long to wait for a collector-line reading before the name-only
    /// fallback becomes eligible (older frames have no collector info).
    public var nameOnlyFallbackDelay: Duration = .seconds(2)

    /// Maximum candidates requested from `CardCatalog.candidates(forName:limit:)`.
    public var nameCandidateLimit: Int = 24

    /// Minimum time between recognition passes. Without pacing the pipeline
    /// runs back-to-back at 100% duty cycle (4K Vision work), heating the
    /// device until the whole system throttles. ~5 passes/second still gives
    /// voting several consistent reads well inside one decay half-life.
    public var recognitionInterval: Duration = .milliseconds(150)

    /// Behavior after a lock. Defaults to auto-resume for stack scanning.
    public var autoResume: AutoResumeBehavior = .after(.milliseconds(1200))

    /// Camera-session tunables.
    public var camera = CameraConfiguration()

    public init() {}
}
