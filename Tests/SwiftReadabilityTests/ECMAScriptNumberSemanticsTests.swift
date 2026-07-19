import SwiftSoup
import Testing
@testable import SwiftReadability

struct ECMAScriptNumberSemanticsTests {
    @Test(arguments: [
        ("2suffix", 2.0),
        ("  +12px", 12.0),
        ("\u{FEFF}-3rest", -3.0),
        ("0", 0.0),
        ("-0", -0.0),
    ])
    func decimalParseIntConsumesTheJavaScriptPrefix(source: String, expected: Double) {
        #expect(javaScriptParseIntBase10(source) == expected)
    }

    @Test(arguments: ["", "words", "\u{0085}2", "\u{200B}2"])
    func decimalParseIntRejectsMissingOrNonECMAScriptPrefixes(source: String) {
        #expect(javaScriptParseIntBase10(source) == nil)
    }

    @Test func tableSpansUseJavaScriptFalsyFallbackAndPrefixParsing() throws {
        let document = try SwiftSoup.parseBodyFragment("""
            <table id="table">
              <tr rowspan="0"><td colspan="2suffix">A</td><td>B</td></tr>
              <tr rowspan="\u{FEFF}+3rows"><td colspan="0">C</td></tr>
            </table>
            """)
        let table = try #require(try document.getElementById("table"))

        let dimensions = readabilityTableDimensions(table)
        #expect(dimensions.rows == 4)
        #expect(dimensions.columns == 3)
    }
}
