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

        let runnerWeight = collectors.dropFirst().first?.weight ?? 0
        let hasClearLead = runnerWeight == 0
            || leader.weight / runnerWeight >= configuration.lockLeadRatio
        let leadName = names.first
        let similarity = leadName.map {
            NameMatcher.similarity(ocrName: $0.name, catalogName: printing.name)
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

        // A live collector line outranks the fallback — unless its lookup
        // already came back as a confirmed catalog miss, in which case that
        // reading can never lock and must not hold the name path hostage.
        let collectorLineStillWinning = collectors.contains { candidate in
            guard let setCode = candidate.info.setCode,
                  candidate.weight >= configuration.strongCollectorWeight
            else { return false }
            let key = CatalogAnswers.PrintingKey(
                setCode: setCode,
                collectorNumber: candidate.info.collectorNumber
            )
            if case .some(.none) = answers.printings[key] { return false }
            return true
        }
        guard collectorLineStillWinning == false else { return nil }

        decision.progress = max(
            decision.progress,
            min(leadName.weight / configuration.nameOnlyLockThreshold, 1)
        )
        guard elapsed >= configuration.nameOnlyFallbackDelay,
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

        return ScanDecision.Lock(
            name: winner.name,
            printing: resolvedPrinting(among: winner.printings, collectors: collectors),
            confidence: .nameOnly,
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

    /// Pins a specific printing for a name-only lock when possible: a bare
    /// collector-number reading (no set code, as printed on older frames)
    /// that matches exactly one candidate printing settles it; otherwise a
    /// name with a single printing is unambiguous by itself.
    private static func resolvedPrinting(
        among printings: [CatalogPrinting],
        collectors: [(info: CollectorInfo, weight: Double)]
    ) -> CatalogPrinting? {
        if let bareNumber = collectors.first(where: { $0.info.setCode == nil })?.info.collectorNumber {
            let numberMatches = printings.filter { $0.collectorNumber == bareNumber }
            if numberMatches.count == 1 { return numberMatches[0] }
        }
        return printings.count == 1 ? printings[0] : nil
    }
}
