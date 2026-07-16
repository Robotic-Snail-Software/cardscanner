/// Repairs common OCR letter-for-digit confusions inside text that is
/// confidently numeric, e.g. `"O123"` → `"0123"`, `"O27I"` → `"0271"`.
///
/// Deconfusion is deliberately narrow: it only runs on slots that a structural
/// regex has already identified as numeric, and only when the slot is at least
/// half real digits. Set-code slots are never deconfused (`"SLD"` must not
/// become `"510"`), and lowercase `a`–`e` are excluded from the confusable
/// alphabet because they are legitimate collector-number suffixes.
nonisolated enum DigitDeconfuser {
    /// Letters Vision commonly returns in place of digits on the small
    /// collector line. Lowercase `b`/`d` are intentionally absent — they are
    /// far more likely to be genuine collector-number suffixes.
    private static let confusions: [Character: Character] = [
        "O": "0", "o": "0", "Q": "0", "q": "0", "D": "0",
        "I": "1", "i": "1", "L": "1", "l": "1", "|": "1",
        "S": "5", "s": "5",
        "B": "8",
    ]

    /// Returns the slot as a pure digit string, repairing confusable letters,
    /// or `nil` when the slot is not confidently numeric.
    ///
    /// A slot qualifies when it contains at least one real digit and digits
    /// make up at least half of its characters — so `"O123"` qualifies but
    /// `"SLD"` (zero digits) is rejected outright.
    static func canonicalDigits(_ slot: some StringProtocol) -> String? {
        guard !slot.isEmpty else { return nil }
        let digitCount = slot.count(where: \.isNumber)
        guard digitCount >= 1, digitCount * 2 >= slot.count else { return nil }
        let repaired = String(slot.map { confusions[$0] ?? $0 })
        guard repaired.allSatisfy(\.isNumber) else { return nil }
        return repaired
    }
}
