import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct JavaScriptStringLengthSemanticsTests {
    private let baseURL = URL(string: "https://example.com/article")!

    @Test func helperCountsUTF16CodeUnitsRatherThanGraphemeClusters() {
        #expect(javaScriptStringLength("😀") == 2)
        #expect(javaScriptStringLength("e\u{301}") == 2)
        #expect(javaScriptStringLength("👨‍👩‍👧‍👦") == 11)
    }

    @Test func readerabilityCountsSupplementaryScalarsAsTwoCodeUnits() throws {
        let document = try SwiftSoup.parse("<html><body><p>😀😀</p></body></html>")
        let options = Readability.ReaderableOptions(minContentLength: 4, minScore: -1)

        // JavaScript "😀😀".length is 4, even though Swift String.count is 2.
        #expect(Readability.isProbablyReaderable(document: document, options: options))
    }

    @Test func bylineLimitUsesJavaScriptLengthForSupplementaryScalars() throws {
        let byline = String(repeating: "😀", count: 50)
        let body = String(repeating: "Substantive article prose with punctuation. ", count: 20)
        let html = """
        <html><body>
          <article>
            <p class="byline">\(byline)</p>
            <p>\(body)</p>
          </article>
        </body></html>
        """

        let result = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        ).parse()

        // Mozilla requires byline.length < 100. Fifty non-BMP scalars are exactly
        // 100 JavaScript UTF-16 code units and therefore are not a valid byline.
        #expect(result?.byline == nil)
    }

    @Test func titleLimitUsesJavaScriptLengthForCombiningSequences() throws {
        let decomposedEAcute = "e\u{301}"
        let longTitle = String(repeating: decomposedEAcute, count: 76)
        let heading = "Replacement Article Heading With Enough Words"
        let body = String(repeating: "Substantive article prose with punctuation. ", count: 20)
        let html = """
        <html>
          <head><title>\(longTitle)</title></head>
          <body><article><h1>\(heading)</h1><p>\(body)</p></article></body>
        </html>
        """

        let result = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        ).parse()

        // The title has 152 JavaScript UTF-16 code units but only 76 Swift
        // grapheme clusters, so Mozilla's >150 branch selects the lone H1.
        #expect(result?.title == heading)
    }

    @Test func siblingThresholdCountsSupplementaryScalarsAsTwoCodeUnits() throws {
        let main = String(
            repeating: "Main article sentence, with enough detail to dominate scoring. ",
            count: 20
        )
        let supplementaryParagraph = String(repeating: "😀", count: 41)
        let html = """
        <html><body>
          <div class="article-content"><p>\(main)</p></div>
          <p>\(supplementaryParagraph)</p>
        </body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        ).parse())

        // Mozilla appends a sibling paragraph when its normalized text length is
        // greater than 80. Forty-one emoji are 82 JavaScript code units but only
        // 41 Swift grapheme clusters.
        #expect(result.textContent.contains(supplementaryParagraph))
    }
}
