import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct ECMAScriptRegularExpressionSemanticsTests {
    private let baseURL = URL(string: "https://example.com/story")!

    @Test func legacyIgnoreCaseDoesNotFoldLongSToASCII() throws {
        let marker = "This paragraph uses a Unicode lookalike in its class while remaining ordinary editorial content."
        let html = """
        <html><body>
          <p class="ſidebar">\(marker) \(String(repeating: "More substantive prose follows. ", count: 12))</p>
        </body></html>
        """
        let readerableOptions = Readability.ReaderableOptions(minContentLength: 20, minScore: 0)

        #expect(Readability.isProbablyReaderable(html: html, options: readerableOptions))
        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())
        #expect(result.textContent.contains(marker))
    }

    @Test func legacyIgnoreCaseDoesNotAuthorizeKelvinSignVideoHost() throws {
        let html = """
        <html><body><article>
          <p>This ordinary article includes an iframe whose hostname only resembles an allowlisted video provider.</p>
          <iframe src="//www.youtube-nocooKie.com/embed/not-allowed"></iframe>
          <p>The lookalike host must not survive Mozilla's embedded-media cleanup.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())
        #expect(!result.content.contains("<iframe"))
    }

    @Test func legacyIgnoreCaseDoesNotTreatLongSAsBase64Marker() throws {
        let html = """
        <html><body><article>
          <p>This article keeps an image source whose malformed encoding marker is not JavaScript-case-equivalent to base64.</p>
          <figure><img id="lookalike" src="data:image/png;baſe64,AAAA" data-source="images/replacement.jpg"></figure>
          <p>A second paragraph makes the article selection deterministic and keeps the illustrative figure nearby.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse())
        let document = try SwiftSoup.parseBodyFragment(result.content)
        let image = try #require(try document.select("#lookalike").first())
        #expect(try image.attr("src") == "data:image/png;ba%C5%BFe64,AAAA")
        #expect(try image.attr("data-source") == "images/replacement.jpg")
    }
}
