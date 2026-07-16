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
