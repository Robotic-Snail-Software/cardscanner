@testable import CardScanner
import Testing

struct DigitDeconfuserTests {
    @Test(arguments: zip(
        ["O123", "O27I", "123", "0007", "1B", "l23", "5I2", "12|"],
        ["0123", "0271", "123", "0007", "18", "123", "512", "121"]
    ))
    func repairsConfidentlyNumericSlots(input: String, expected: String) {
        #expect(DigitDeconfuser.canonicalDigits(input) == expected)
    }

    @Test(arguments: [
        "SLD",   // zero digits — letters-only slots must never be repaired
        "MB1",   // only 1 of 3 characters is a digit
        "S2I",   // likewise digit-minority — S/I stay letters
        "12E",   // E is not a known confusion, result isn't numeric
        "",      // empty
        "M21",   // M is not a known confusion — set codes survive intact
    ])
    func rejectsNonNumericSlots(input: String) {
        #expect(DigitDeconfuser.canonicalDigits(input) == nil)
    }
}
