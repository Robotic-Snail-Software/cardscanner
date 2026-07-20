@testable import CardScanner
import Testing

struct ScanResolverTests {
    private let configuration = ScannerConfiguration()

    private let midBolt = CatalogPrinting(
        id: "uuid-mid-117",
        name: "Lightning Bolt",
        setCode: "MID",
        collectorNumber: "117"
    )

    private let midReading = CollectorInfo(collectorNumber: "117", setCode: "MID")

    private func answersWithHit() -> CatalogAnswers {
        var answers = CatalogAnswers()
        answers.printings[CatalogAnswers.PrintingKey(setCode: "MID", collectorNumber: "117")] = midBolt
        return answers
    }

    private func decide(
        names: [(name: String, weight: Double)] = [],
        collectors: [(info: CollectorInfo, weight: Double)] = [],
        answers: CatalogAnswers = CatalogAnswers(),
        elapsed: Duration = .seconds(1),
        setHint: String? = nil
    ) -> ScanDecision {
        ScanResolver.decide(
            names: names,
            collectors: collectors,
            answers: answers,
            elapsed: elapsed,
            setHint: setHint,
            configuration: configuration
        )
    }

    // MARK: Rule A — exact printing

    @Test func ruleALocksWithAgreeingName() {
        let decision = decide(
            names: [("Lightning Bolt", 2.0)],
            collectors: [(midReading, 2.6)],
            answers: answersWithHit()
        )
        #expect(decision.lock?.confidence == .exactPrinting)
        #expect(decision.lock?.printing == midBolt)
        #expect(decision.progress == 1)
    }

    @Test func ruleAToleratesOCRDamageInTheName() {
        let decision = decide(
            names: [("Lightnimg Bolt", 2.0)],
            collectors: [(midReading, 2.6)],
            answers: answersWithHit()
        )
        #expect(decision.lock?.confidence == .exactPrinting)
        #expect(decision.lock?.name == "Lightning Bolt", "locked name is the catalog's, not the OCR reading")
    }

    @Test func ruleANeedsEnoughWeight() {
        let decision = decide(
            names: [("Lightning Bolt", 2.0)],
            collectors: [(midReading, 1.0)],
            answers: answersWithHit()
        )
        #expect(decision.lock == nil)
        #expect(decision.progress < 1)
    }

    @Test func ruleANeedsAClearLeadOverTheRunnerUp() {
        let runnerUp = CollectorInfo(collectorNumber: "111", setCode: "MID")
        let decision = decide(
            names: [("Lightning Bolt", 2.0)],
            collectors: [(midReading, 2.6), (runnerUp, 2.0)],
            answers: answersWithHit()
        )
        #expect(decision.lock == nil, "2.6 vs 2.0 is below the 2.0× lead ratio")
    }

    @Test func ocrSiblingRunnerUpDoesNotBlockTheLock() {
        // "M1D" is an OCR misread of "MID" with the same number — the same
        // physical reading, not a competing card, so no ratio veto.
        let sibling = CollectorInfo(collectorNumber: "117", setCode: "M1D")
        let decision = decide(
            names: [("Lightning Bolt", 2.0)],
            collectors: [(midReading, 2.6), (sibling, 2.0)],
            answers: answersWithHit()
        )
        #expect(decision.lock?.confidence == .exactPrinting)
    }

    @Test func bareNumberEchoDoesNotBlockTheLock() {
        let echo = CollectorInfo(collectorNumber: "117", setCode: nil)
        let decision = decide(
            names: [("Lightning Bolt", 2.0)],
            collectors: [(midReading, 2.6), (echo, 2.0)],
            answers: answersWithHit()
        )
        #expect(decision.lock?.confidence == .exactPrinting)
    }

    @Test func foreignLanguageCardLocksExactWithoutNameAgreement() {
        // A Japanese card's title is unreadable to the English recognizer,
        // but its set+number+language line is language-independent.
        let foreignReading = CollectorInfo(
            collectorNumber: "117",
            setCode: "MID",
            languageCode: "JA"
        )
        var answers = CatalogAnswers()
        answers.printings[CatalogAnswers.PrintingKey(setCode: "MID", collectorNumber: "117")] = midBolt
        let decision = decide(
            names: [("稲妻", 1.0)],
            collectors: [(foreignReading, 2.2)],
            answers: answers
        )
        #expect(decision.lock?.confidence == .exactPrinting)
        #expect(decision.lock?.name == "Lightning Bolt")
    }

    @Test func foreignLanguageStillNeedsTheWeightThreshold() {
        let foreignReading = CollectorInfo(
            collectorNumber: "117",
            setCode: "MID",
            languageCode: "DE"
        )
        var answers = CatalogAnswers()
        answers.printings[CatalogAnswers.PrintingKey(setCode: "MID", collectorNumber: "117")] = midBolt
        let decision = decide(
            collectors: [(foreignReading, 1.2)],
            answers: answers
        )
        #expect(decision.lock == nil)
    }

    // MARK: Rule B — printing only

    @Test func ruleBLocksWithoutANameAtHigherWeight() {
        let decision = decide(
            names: [],
            collectors: [(midReading, 4.2)],
            answers: answersWithHit()
        )
        #expect(decision.lock?.confidence == .printingOnly)
        #expect(decision.lock?.printing == midBolt)
    }

    @Test func ruleBNeedsMoreWeightThanRuleA() {
        let decision = decide(
            names: [],
            collectors: [(midReading, 2.6)],
            answers: answersWithHit()
        )
        #expect(decision.lock == nil)
    }

    @Test func ruleBIsVetoedByAContradictingName() {
        let decision = decide(
            names: [("Craterhoof Behemoth", 2.5)],
            collectors: [(midReading, 5.0)],
            answers: answersWithHit()
        )
        #expect(decision.lock == nil, "a strong unrelated name means the collector read is suspect")
    }

    // MARK: Catalog misses and lookups

    @Test func missingAnswerRequestsALookup() {
        let decision = decide(
            names: [("Lightning Bolt", 2.0)],
            collectors: [(midReading, 2.6)]
        )
        #expect(decision.lock == nil)
        #expect(decision.neededLookups == [.printing(setCode: "MID", collectorNumber: "117")])
    }

    @Test func confirmedMissWithStrongEvidenceHintsAlignment() {
        var answers = CatalogAnswers()
        answers.printings.updateValue(
            nil,
            forKey: CatalogAnswers.PrintingKey(setCode: "MID", collectorNumber: "117")
        )
        let decision = decide(
            collectors: [(midReading, 4.5)],
            answers: answers
        )
        #expect(decision.lock == nil)
        #expect(decision.hint == .checkAlignment)
    }

    // MARK: Rule C — name-only fallback

    @Test func ruleCLocksAfterTheGracePeriod() {
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt]
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            answers: answers,
            elapsed: .seconds(3)
        )
        #expect(decision.lock?.confidence == .nameOnly)
        #expect(decision.lock?.printing == midBolt, "single printing is unambiguous")
        #expect(decision.lock?.alternates == [midBolt])
    }

    @Test func ruleCWaitsOutTheGracePeriod() {
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt]
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            answers: answers,
            elapsed: .seconds(1)
        )
        #expect(decision.lock == nil)
    }

    @Test func ruleCWaitsWhileASetCodedReadingResolves() {
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt]
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            collectors: [(midReading, 1.5)],
            answers: answers,
            elapsed: .seconds(2.5)
        )
        #expect(decision.lock == nil, "the collector path may still deliver an exact lock")
        #expect(decision.neededLookups == [.printing(setCode: "MID", collectorNumber: "117")])
    }

    @Test func ruleCEventuallyOverridesAStalledSetCodedReading() {
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt]
        answers.printings.updateValue(
            midBolt,
            forKey: CatalogAnswers.PrintingKey(setCode: "MID", collectorNumber: "117")
        )
        // A set-coded reading that never accumulates enough weight to lock
        // must not block identification forever.
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            collectors: [(midReading, 0.6)],
            answers: answers,
            elapsed: .seconds(4)
        )
        #expect(decision.lock != nil)
    }

    @Test func confirmedMissDoesNotBlockTheNameFallback() {
        // A strong collector reading that the catalog has confirmed it does
        // NOT contain (e.g. the host's catalog is incomplete) can never lock,
        // so a strong matching name must still be able to identify the card.
        var answers = CatalogAnswers()
        answers.printings.updateValue(
            nil,
            forKey: CatalogAnswers.PrintingKey(setCode: "MID", collectorNumber: "117")
        )
        answers.nameCandidates["lightning bolt"] = [midBolt]
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            collectors: [(midReading, 4.5)],
            answers: answers,
            elapsed: .seconds(3)
        )
        #expect(decision.lock?.confidence == .nameOnly)
        #expect(decision.lock?.printing == midBolt)
    }

    @Test func ruleCRequestsCandidatesWhenNotFetched() {
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            elapsed: .seconds(3)
        )
        #expect(decision.lock == nil)
        #expect(decision.neededLookups == [.nameCandidates("Lightning Bolt")])
    }

    @Test func setHintPinsThePrintingWhenNumberUnread() {
        // "UST" was read but the number wasn't — the hint should pick the
        // one UST printing of the name instead of leaving it arbitrary.
        let ust = CatalogPrinting(id: "uuid-ust-68", name: "Snickering Squirrel", setCode: "UST", collectorNumber: "68")
        let und = CatalogPrinting(id: "uuid-und-45", name: "Snickering Squirrel", setCode: "UND", collectorNumber: "45")
        var answers = CatalogAnswers()
        answers.nameCandidates["snickering squirrel"] = [ust, und]
        let decision = decide(
            names: [("Snickering Squirrel", 3.2)],
            answers: answers,
            elapsed: .seconds(3),
            setHint: "UST"
        )
        #expect(decision.lock?.printing == ust)
        #expect(decision.lock?.alternates.count == 2)
    }

    @Test func setHintIgnoredWhenItMatchesNoPrinting() {
        let und = CatalogPrinting(id: "uuid-und-45", name: "Snickering Squirrel", setCode: "UND", collectorNumber: "45")
        let uma = CatalogPrinting(id: "uuid-uma-9", name: "Snickering Squirrel", setCode: "UMA", collectorNumber: "9")
        var answers = CatalogAnswers()
        answers.nameCandidates["snickering squirrel"] = [und, uma]
        let decision = decide(
            names: [("Snickering Squirrel", 3.2)],
            answers: answers,
            elapsed: .seconds(3),
            setHint: "ZZZ"
        )
        // No UST-equivalent printing; leaves the printing unpinned (ambiguous).
        #expect(decision.lock?.confidence == .nameOnly)
        #expect(decision.lock?.printing == nil)
    }

    @Test func ruleCLeavesPrintingOpenWhenAmbiguous() {
        let reprint = CatalogPrinting(
            id: "uuid-clb-187",
            name: "Lightning Bolt",
            setCode: "CLB",
            collectorNumber: "187"
        )
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt, reprint]
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            answers: answers,
            elapsed: .seconds(3)
        )
        #expect(decision.lock?.confidence == .nameOnly)
        #expect(decision.lock?.printing == nil)
        #expect(decision.lock?.alternates.count == 2)
    }

    @Test func ruleCPinsPrintingViaBareCollectorNumber() {
        let reprint = CatalogPrinting(
            id: "uuid-clb-187",
            name: "Lightning Bolt",
            setCode: "CLB",
            collectorNumber: "187"
        )
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt, reprint]
        let bareNumber = CollectorInfo(collectorNumber: "187", setCode: nil)
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            collectors: [(bareNumber, 0.8)],
            answers: answers,
            elapsed: .seconds(3)
        )
        // A weakly-read number pins the printing but isn't independent
        // confirmation — the lock stays name-grade.
        #expect(decision.lock?.confidence == .nameOnly)
        #expect(decision.lock?.printing == reprint, "the bare number singles out the printing")
    }

    @Test func confidentBareNumberPromotesNameMatchToExact() {
        let reprint = CatalogPrinting(
            id: "uuid-clb-187",
            name: "Lightning Bolt",
            setCode: "CLB",
            collectorNumber: "187"
        )
        var answers = CatalogAnswers()
        answers.nameCandidates["lightning bolt"] = [midBolt, reprint]
        let bareNumber = CollectorInfo(collectorNumber: "187", setCode: nil)
        let decision = decide(
            names: [("Lightning Bolt", 3.2)],
            collectors: [(bareNumber, 1.4)],
            answers: answers,
            elapsed: .seconds(3)
        )
        // Name match + confidently-read agreeing number = two independent
        // confirmations, same strength as the set-code path.
        #expect(decision.lock?.confidence == .exactPrinting)
        #expect(decision.lock?.printing == reprint)
    }

    @Test func persistentlyUnreadCollectorLineHintsMoreLight() {
        let decision = decide(
            names: [("Lightning Bolt", 1.5)],
            collectors: [],
            elapsed: .seconds(3)
        )
        #expect(decision.lock == nil)
        #expect(decision.hint == .needsMoreLight)
    }

    @Test func noLightHintWhileCollectorReadsArrive() {
        let decision = decide(
            names: [("Lightning Bolt", 1.5)],
            collectors: [(midReading, 0.5)],
            answers: answersWithHit(),
            elapsed: .seconds(3)
        )
        #expect(decision.hint == nil)
    }

    @Test func ruleCRejectsANarrowWinOverASiblingName() {
        let sibling = CatalogPrinting(
            id: "uuid-ths-101",
            name: "Fanatics of Mogis",
            setCode: "THS",
            collectorNumber: "101"
        )
        let target = CatalogPrinting(
            id: "uuid-ths-100",
            name: "Fanatic of Mogis",
            setCode: "THS",
            collectorNumber: "100"
        )
        var answers = CatalogAnswers()
        answers.nameCandidates["fanatic of mogis"] = [target, sibling]
        let decision = decide(
            names: [("Fanatic of Mogis", 3.2)],
            answers: answers,
            elapsed: .seconds(3)
        )
        // One edit separates the sibling names (~0.94 similarity), so the
        // exact match's lead is under the 0.1 margin — too risky to lock.
        #expect(decision.lock == nil)
    }

    @Test func noEvidenceMeansNoDecision() {
        let decision = decide()
        #expect(decision.lock == nil)
        #expect(decision.progress == 0)
        #expect(decision.neededLookups.isEmpty)
    }
}
