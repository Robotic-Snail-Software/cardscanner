/// The pure lock-decision engine. Given ranked evidence, memoized catalog
/// answers, and elapsed scan time, it decides whether the scan is confirmed.
///
/// Three lock rules, strictest first:
///
/// - **Exact printing** — the leading set+number reading is heavy enough,
///   clearly ahead of the runner-up, resolves in the catalog, *and* the OCR
///   name agrees with the catalog name.
/// - **Printing only** — the reading resolves but no name confirms it, so a
///   higher weight is demanded; a strong *contradicting* name vetoes it.
/// - **Name only** — no strong collector reading after a grace period
///   (older card frames); the leading name must match a catalog name nearly
///   exactly and beat every other name by a clear margin.
///
/// The resolver never performs lookups itself — missing answers are returned
/// as `neededLookups` and the model re-runs the resolver once they complete.
nonisolated enum ScanResolver {
    static func decide(
        names: [(name: String, weight: Double)],
        collectors: [(info: CollectorInfo, weight: Double)],
        answers: CatalogAnswers,
        elapsed: Duration,
        configuration: ScannerConfiguration
    ) -> ScanDecision {
        var decision = ScanDecision()
        decision.leadingName = names.first?.name
        decision.leadingCollector = collectors.first?.info

        if let lock = collectorLock(
            names: names,
            collectors: collectors,
            answers: answers,
            configuration: configuration,
            decision: &decision
        ) {
            decision.lock = lock
            decision.progress = 1
            return decision
        }

        if let lock = nameOnlyLock(
            names: names,
            collectors: collectors,
            answers: answers,
            elapsed: elapsed,
            configuration: configuration,
            decision: &decision
        ) {
            decision.lock = lock
            decision.progress = 1
            return decision
        }

        // The title reads but the small collector print never has — the
        // classic dim-lighting signature; the torch usually fixes it.
        if decision.hint == nil,
           elapsed >= .seconds(2),
           let leadName = names.first, leadName.weight >= 1,
           collectors.isEmpty {
            decision.hint = .needsMoreLight
        }
        return decision
    }

    // MARK: Set-coded collector path (rules A and B)

    /// Attempts an exact-printing or printing-only lock. When no lock is
    /// possible yet, annotates `decision` with progress, needed lookups, and
    /// hints, then returns `nil` so the name-only rule can still be weighed.
    private static func collectorLock(
        names: [(name: String, weight: Double)],
        collectors: [(info: CollectorInfo, weight: Double)],
        answers: CatalogAnswers,
        configuration: ScannerConfiguration,
        decision: inout ScanDecision
    ) -> ScanDecision.Lock? {
        guard let leader = collectors.first, let setCode = leader.info.setCode else { return nil }

        decision.progress = min(leader.weight / configuration.lockThreshold, 1)

        let key = CatalogAnswers.PrintingKey(setCode: setCode, collectorNumber: leader.info.collectorNumber)
        guard let answer = answers.printings[key] else {
            decision.neededLookups.append(
                .printing(setCode: setCode, collectorNumber: leader.info.collectorNumber)
            )
            return nil
        }

        guard let printing = answer else {
            // Confirmed catalog miss: strong evidence for a nonexistent
            // printing means the read (or framing) is wrong.
            if leader.weight >= configuration.printingOnlyLockThreshold {
                decision.hint = .checkAlignment
            }
            return nil
        }

        // The lead-ratio veto exists for genuine ambiguity between different
        // cards. A runner-up that is just an OCR misread of the leader —
        // same number with a confusable set code, or a bare-number echo —
        // is the same card and must not block the lock.
        let runnerWeight = collectors.dropFirst().first { candidate in
            isConfusionSibling(candidate.info, of: leader.info) == false
        }?.weight ?? 0
        let hasClearLead = runnerWeight == 0
            || leader.weight / runnerWeight >= configuration.lockLeadRatio
        let leadName = names.first
        let similarity = leadName.map {
            NameMatcher.similarity(ocrName: $0.name, catalogName: printing.name)
        }

        // Non-English cards print a language token on the collector line but
        // a title the English recognizer can't read — the catalog stores
        // English names, so the name cross-check can never agree. The
        // catalog-verified set+number (which is language-independent) locks
        // on its own at the standard threshold.
        let isForeignLanguage = leader.info.languageCode.map { $0 != "EN" } ?? false
        if isForeignLanguage {
            if leader.weight >= configuration.lockThreshold, hasClearLead {
                return ScanDecision.Lock(name: printing.name, printing: printing, confidence: .exactPrinting)
            }
            return nil
        }

        if let similarity, similarity >= configuration.nameSimilarityFloor {
            // Rule A: the name agrees with the resolved printing.
            if leader.weight >= configuration.lockThreshold, hasClearLead {
                return ScanDecision.Lock(name: printing.name, printing: printing, confidence: .exactPrinting)
            }
        } else {
            // Rule B: no usable name — demand more collector evidence, and
            // let a strongly contradicting name veto the lock entirely.
            decision.progress = min(leader.weight / configuration.printingOnlyLockThreshold, 1)
            let contradicted = (leadName?.weight ?? 0) >= configuration.contradictionNameWeight
                && (similarity ?? 0) < configuration.nameContradictionCeiling
            if contradicted == false,
               leader.weight >= configuration.printingOnlyLockThreshold,
               hasClearLead {
                return ScanDecision.Lock(name: printing.name, printing: printing, confidence: .printingOnly)
            }
        }
        return nil
    }

    /// Whether `candidate` is plausibly the same physical reading as
    /// `leader`: an identical collector number with a confusable (or absent)
    /// set code.
    private static func isConfusionSibling(_ candidate: CollectorInfo, of leader: CollectorInfo) -> Bool {
        guard candidate.collectorNumber == leader.collectorNumber else { return false }
        guard let candidateSet = candidate.setCode else { return true }
        guard let leaderSet = leader.setCode else { return false }
        return SetCodeRepair.areConfusable(candidateSet, leaderSet)
    }

    // MARK: Name-only fallback (rule C)

    private static func nameOnlyLock(
        names: [(name: String, weight: Double)],
        collectors: [(info: CollectorInfo, weight: Double)],
        answers: CatalogAnswers,
        elapsed: Duration,
        configuration: ScannerConfiguration,
        decision: inout ScanDecision
    ) -> ScanDecision.Lock? {
        guard let leadName = names.first else { return nil }

        // A live set-coded reading usually resolves into an exact lock, so
        // the fallback holds off longer while one is in play. Readings whose
        // lookups came back as confirmed catalog misses can never lock and
        // don't count.
        let hasLiveSetCodedReading = collectors.contains { candidate in
            guard let setCode = candidate.info.setCode,
                  candidate.weight >= 0.3 // at least one recent parse
            else { return false }
            let key = CatalogAnswers.PrintingKey(
                setCode: setCode,
                collectorNumber: candidate.info.collectorNumber
            )
            if case .some(.none) = answers.printings[key] { return false }
            return true
        }
        let fallbackDelay = hasLiveSetCodedReading
            ? configuration.nameOnlyContestedDelay
            : configuration.nameOnlyFallbackDelay

        decision.progress = max(
            decision.progress,
            min(leadName.weight / configuration.nameOnlyLockThreshold, 1)
        )
        guard elapsed >= fallbackDelay,
              leadName.weight >= configuration.nameOnlyLockThreshold
        else { return nil }

        let foldedKey = TextNormalizer.foldedForMatching(leadName.name)
        guard let candidates = answers.nameCandidates[foldedKey] else {
            decision.neededLookups.append(.nameCandidates(leadName.name))
            return nil
        }

        guard let winner = bestUniqueName(
            reading: leadName.name,
            candidates: candidates,
            configuration: configuration
        ) else { return nil }

        let resolution = resolvedPrinting(
            among: winner.printings,
            collectors: collectors,
            configuration: configuration
        )
        // A confidently-read bare collector number agreeing with the matched
        // name is two independent confirmations — exact-grade, same as a
        // set-code path lock.
        return ScanDecision.Lock(
            name: winner.name,
            printing: resolution?.printing,
            confidence: resolution?.confirmedByNumber == true ? .exactPrinting : .nameOnly,
            alternates: winner.printings
        )
    }

    /// The catalog name that best matches the reading, provided it clears the
    /// similarity floor and beats every other candidate name by the margin.
    private static func bestUniqueName(
        reading: String,
        candidates: [CatalogPrinting],
        configuration: ScannerConfiguration
    ) -> (name: String, printings: [CatalogPrinting])? {
        let byName = Dictionary(grouping: candidates, by: \.name)
        let ranked = byName.keys
            .map { (name: $0, similarity: NameMatcher.similarity(ocrName: reading, catalogName: $0)) }
            .sorted { $0.similarity > $1.similarity }
        guard let best = ranked.first,
              best.similarity >= configuration.nameOnlySimilarityFloor,
              best.similarity - (ranked.dropFirst().first?.similarity ?? 0) >= configuration.nameOnlyLeadMargin,
              let printings = byName[best.name]
        else { return nil }
        return (best.name, printings.sorted { ($0.setCode, $0.collectorNumber) < ($1.setCode, $1.collectorNumber) })
    }

    /// Pins a specific printing for a name-matched lock when possible: a
    /// bare collector-number reading (no set code, as printed on older
    /// frames) that matches exactly one candidate printing settles it;
    /// otherwise a name with a single printing is unambiguous by itself.
    /// `confirmedByNumber` is true only when the agreeing number was itself
    /// confidently read (enough accumulated weight), making the lock
    /// exact-grade rather than name-grade.
    private static func resolvedPrinting(
        among printings: [CatalogPrinting],
        collectors: [(info: CollectorInfo, weight: Double)],
        configuration: ScannerConfiguration
    ) -> (printing: CatalogPrinting, confirmedByNumber: Bool)? {
        if let bare = collectors.first(where: { $0.info.setCode == nil }) {
            let numberMatches = printings.filter { $0.collectorNumber == bare.info.collectorNumber }
            if numberMatches.count == 1 {
                let confident = bare.weight >= configuration.strongCollectorWeight
                return (numberMatches[0], confident)
            }
        }
        return printings.count == 1 ? (printings[0], false) : nil
    }
}
