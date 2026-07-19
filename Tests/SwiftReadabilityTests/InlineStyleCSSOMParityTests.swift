import Foundation
import Testing
@testable import SwiftReadability

struct InlineStyleCSSOMParityTests {
    private let baseURL = URL(string: "https://example.com/article")!

    private struct Fixture: Decodable {
        let name: String
        let style: String
        let display: String?
        let visibility: String?
    }

    private static func fixtures() throws -> [Fixture] {
        let root = try #require(Bundle.module.resourceURL)
        let url = root.appendingPathComponent("Fixtures/inline-style-cssom-cases.json")
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }

    @Test func inlineStyleParsingMatchesPinnedJSDOMCSSOMCorpus() throws {
        for fixture in try Self.fixtures() {
            let declarations = InlineStyleDeclarations(fixture.style)
            #expect(
                declarations.value(for: "display") == fixture.display,
                "display mismatch for \(fixture.name): \(fixture.style)"
            )
            #expect(
                declarations.value(for: "visibility") == fixture.visibility,
                "visibility mismatch for \(fixture.name): \(fixture.style)"
            )
        }
    }

    @Test func malformedCSSCannotCreatePhantomHiddenDeclarations() {
        let styles = [
            "color:red\\;display:none;",
            "unknown:[x;display:none;]",
            "unknown:{x;visibility:hidden;}",
        ]

        for style in styles {
            let declarations = InlineStyleDeclarations(style)
            #expect(declarations.value(for: "display") != "none", "phantom display for \(style)")
            #expect(declarations.value(for: "visibility") != "hidden", "phantom visibility for \(style)")
        }
    }

    @Test func extractionUsesThePinnedCSSOMValuesForDefaultVisibility() throws {
        let cases: [(style: String, visible: Bool)] = [
            ("display:none", false),
            ("display:none!foo;display:block", false),
            ("visibility:visible;visibility:hidden", false),
            ("color:red\\;display:none;", true),
            ("unknown:[x;display:none;]", true),
            ("display:none;display:block var(--layout)", true),
            ("visibility:hidden;visibility:force-hidden", true),
            ("display:block math!important;display:none", true),
        ]

        for testCase in cases {
            let marker = "CSSOM visibility marker for \(testCase.style)"
            let escapedStyle = testCase.style
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            let html = """
            <html><body><article>
              <div style="\(escapedStyle)">
                <p>\(marker)</p>
                <p>A second substantial paragraph keeps the visible target inside the article candidate.</p>
              </div>
              <p>Visible fallback prose keeps extraction successful when the target is hidden.</p>
            </article></body></html>
            """
            let result = try #require(try Readability(
                html: html,
                url: baseURL,
                options: ReadabilityOptions(charThreshold: 1)
            ).parse())

            #expect(
                result.textContent.contains(marker) == testCase.visible,
                "default extraction visibility mismatch for \(testCase.style)"
            )
        }
    }

    @Test func readerabilityUsesDisplayButNotVisibilityLikeMozilla() {
        let cases: [(style: String, visible: Bool)] = [
            ("display:none!foo;display:block", false),
            ("color:red\\;display:none;", true),
            ("display:none;display:block var(--layout)", true),
            ("visibility:hidden", true),
        ]
        let prose = String(repeating: "Substantive readerability prose with context. ", count: 8)
        let options = Readability.ReaderableOptions(minContentLength: 1, minScore: 0)

        for testCase in cases {
            let html = "<html><body><article style=\"\(testCase.style)\">\(prose)</article></body></html>"
            #expect(
                Readability.isProbablyReaderable(html: html, options: options) == testCase.visible,
                "default readerability visibility mismatch for \(testCase.style)"
            )
        }
    }
}
