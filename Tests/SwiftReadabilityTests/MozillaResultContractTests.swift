import Foundation
import Testing
@testable import SwiftReadability

struct MozillaResultContractTests {
    @Test func textContentAndLengthUseDOMAndJavaScriptSemantics() throws {
        let html = """
        <html><head><title>Text contract</title></head><body><article><p>Hello <em>world</em>.</p><p>Second 😀 paragraph.</p></article></body></html>
        """
        let reader = Readability(
            html: html,
            url: URL(string: "https://example.com/article")!,
            options: ReadabilityOptions(charThreshold: 0)
        )

        let result = try #require(try reader.parse())

        // Mozilla returns Element.textContent and JavaScript String.length.
        // Text nodes concatenate without SwiftSoup's inserted word separators,
        // while a non-BMP scalar occupies two UTF-16 code units.
        #expect(result.textContent == "Hello world.Second 😀 paragraph.")
        #expect(result.length == 32)
        #expect(result.length == result.textContent.utf16.count)
    }
}
