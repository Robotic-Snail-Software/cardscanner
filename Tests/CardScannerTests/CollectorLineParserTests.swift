@testable import CardScanner
import Testing

struct CollectorLineParserTests {
    @Test(arguments: CollectorLineCorpus.accepted)
    func parsesRealisticReads(_ testCase: CollectorLineCase) {
        let parsed = CollectorLineParser.parse(lines: testCase.lines)
        #expect(parsed == testCase.expected)
    }

    @Test(arguments: CollectorLineCorpus.rejected)
    func rejectsImplausibleReads(_ testCase: CollectorLineRejection) {
        let parsed = CollectorLineParser.parse(lines: testCase.lines)
        #expect(parsed == nil, "should reject: \(testCase.reason)")
    }

    @Test func setCodeHintReadsSetWithoutANumber() {
        // The pairing guard rejects a set with no number for locking, but the
        // set is still recoverable as a soft hint.
        #expect(CollectorLineParser.setCodeHint(lines: ["UST • EN Michael Phillippi"]) == "UST")
        #expect(CollectorLineParser.parse(lines: ["UST • EN Michael Phillippi"]) == nil)
    }

    @Test func setCodeHintRejectsNonSetLines() {
        #expect(CollectorLineParser.setCodeHint(lines: ["™ & © 2017 Wizards"]) == nil)
        #expect(CollectorLineParser.setCodeHint(lines: ["068/216 C"]) == nil)
    }

    @Test func setCodeIsNeverEmittedWithoutCollectorNumber() {
        // The pairing guard from prior prototypes, now enforced structurally:
        // a set/language line alone must produce nothing at all.
        let parsed = CollectorLineParser.parse(lines: ["NEO • EN", "Artist Name"])
        #expect(parsed == nil)
    }

    @Test func firstLadderRungWins() {
        // A merged line and a weaker standalone number coexist; the merged
        // interpretation (most specific) must win.
        let parsed = CollectorLineParser.parse(lines: ["0117/0277 M MID • EN", "42"])
        #expect(parsed?.collectorNumber == "117")
        #expect(parsed?.setCode == "MID")
    }
}
