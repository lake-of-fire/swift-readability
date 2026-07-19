import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct MozillaOptionAndCleanupParityTests {
    private let baseURL = URL(string: "https://example.com/story")!

    @Test func negativeTopCandidateCountDoesNotTrap() throws {
        let result = try Readability(
            html: articleHTML("Negative candidate counts are truthy in JavaScript, but the candidate loop simply executes zero times."),
            url: baseURL,
            options: ReadabilityOptions(nbTopCandidates: -1, charThreshold: 1)
        ).parse()

        #expect(result != nil)
    }

    @Test func nanLinkDensityModifierUsesMozillasFalsyZero() throws {
        let html = articleHTML("A NaN link-density modifier must behave exactly like zero throughout conditional cleanup.")
        let nan = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, linkDensityModifier: .nan)
        ).parse()
        let zero = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, linkDensityModifier: 0)
        ).parse()

        #expect(nan?.content == zero?.content)
        #expect(nan?.textContent == zero?.textContent)
    }

    @Test func ariaModalAndUnlikelyRolesAreCaseSensitive() throws {
        let marker = "Uppercase role values are not equal to Mozilla's lowercase role tokens and must remain available to extraction."
        let html = """
        <html><body><article>
          <section aria-modal="true" role="DIALOG"><p>\(marker)</p></section>
          <section role="NAVIGATION"><p>Uppercase navigation is likewise not an exact unlikely-role match.</p></section>
          <p>A final ordinary paragraph makes the complete article a stable selection candidate.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.textContent.contains(marker))
        #expect(result.textContent.contains("Uppercase navigation"))
    }

    @Test func iframeInnerHTMLDoesNotSatisfyTheVideoAllowlist() throws {
        let html = """
        <html><body><article>
          <p>This article includes an ordinary iframe whose fallback markup mentions a video host without an allowed iframe attribute.</p>
          <iframe><a href="https://www.youtube.com/watch?v=fallback">Fallback video link</a></iframe>
          <p>The iframe itself must still be removed just as Mozilla removes it.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(!result.content.contains("<iframe"))
    }

    @Test func bylineNameSearchStartsAtDescendantsNotTheRoot() throws {
        let html = """
        <html><head><title>A Focused Byline Test</title></head><body><article>
          <div class="byline" itemprop="name author">
            Root prefix <span itemprop="name">Correct Author</span>
          </div>
          <p>This substantial editorial paragraph makes the byline and content extraction behavior deterministic.</p>
          <p>A second paragraph ensures the article remains selected after the byline node is removed.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.byline == "Correct Author")
    }

    private func articleHTML(_ marker: String) -> String {
        """
        <html><body><article>
          <p>\(marker)</p>
          <p>A second coherent paragraph supplies additional editorial context and punctuation, making the article selection deterministic.</p>
        </article></body></html>
        """
    }
}
