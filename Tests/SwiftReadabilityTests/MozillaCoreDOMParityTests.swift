import Foundation
import Testing
@testable import SwiftReadability

/// Small oracle-derived regressions for browser DOM semantics used by the
/// pinned Mozilla Readability implementation. Each fixture isolates one
/// behavior so broad corpus agreement cannot conceal a compensating mismatch.
struct MozillaCoreDOMParityTests {
    private let baseURL = URL(string: "https://example.com/articles/story")!

    @Test func linkDensityDoesNotCountTheCandidateAnchorItself() throws {
        let html = """
        <!doctype html><html><head><title>Root anchor density regression</title></head><body><main>
          <a id="article-content" class="article-content"><p>Primary wrapped article prose has many words, several commas, and enough detail to become the strongest candidate. It continues with a substantial explanation, more observations, and a clear concluding sentence. This marker ROOT_ANCHOR_PRIMARY must survive when the wrapped anchor wins.</p></a>
          <aside><p>Short competing material, with enough words to score, but it is not the primary article. COMPETING_ASIDE.</p></aside>
        </main></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.textContent.contains("ROOT_ANCHOR_PRIMARY"))
        #expect(!result.textContent.contains("COMPETING_ASIDE"))
    }

    @Test func maximumElementCountExcludesTheDocumentNode() throws {
        // Browser document.getElementsByTagName("*") reports exactly six
        // elements here: html, head, title, body, article, and p.
        let html = """
        <!doctype html><html><head><title>Boundary</title></head><body><article><p>Concise article prose is enough to return content at the exact six-element boundary.</p></article></body></html>
        """

        _ = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(maxElemsToParse: 6, charThreshold: 1)
        ).parse()

        do {
            _ = try Readability(
                html: html,
                url: baseURL,
                options: ReadabilityOptions(maxElemsToParse: 5, charThreshold: 1)
            ).parse()
            Issue.record("Mozilla rejects this six-element document when the configured maximum is five.")
        } catch {
            #expect(error.localizedDescription.contains("6 elements found"))
        }
    }

    @Test func mathMLNodesWithoutAStyleInterfaceIgnoreTheRawStyleAttribute() throws {
        let html = """
        <!doctype html><html><head><title>MathML style property regression</title></head><body><article>
          <math><mtext style="display:none">MATHML_STYLE_MARKER remains in Mozilla because generic MathML elements do not expose an element.style CSSOM property in the pinned DOM.</mtext></math>
          <p>An ordinary visible paragraph keeps the surrounding article selected and makes the result deterministic. It should remain in both implementations.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.textContent.contains("MATHML_STYLE_MARKER"))
    }

    @Test func svgClassNameDoesNotBehaveLikeAJavaScriptString() throws {
        let html = """
        <!doctype html><html><head><title>SVG className regression</title></head><body><article>
          <svg aria-hidden="true" class="fallback-image"><foreignObject><p>SVG_FALLBACK_MARKER is hidden because SVG className is not a string and has no includes method in Mozilla's browser DOM check. This paragraph is intentionally substantial.</p></foreignObject></svg>
          <p>An ordinary visible paragraph keeps the surrounding article selected and makes the output deterministic. It should remain regardless of the SVG subtree decision.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(!result.textContent.contains("SVG_FALLBACK_MARKER"))
    }

    @Test func lowercaseObjectInnerHTMLCheckPreservesPinnedHTMLTagNameSemantics() throws {
        let html = """
        <!doctype html><html><head><title>Object inner video regression</title></head><body><article>
          <p>This substantive article contains an object whose own attributes do not name an allowed video host. The fallback child alone names YouTube, which exposes the pinned tagName case comparison.</p>
          <object><param name="movie" value="https://www.youtube.com/embed/abc"></object>
          <p>A second substantial paragraph keeps extraction deterministic and records the marker OBJECT_INNER_VIDEO_REGRESSION.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.textContent.contains("OBJECT_INNER_VIDEO_REGRESSION"))
        #expect(!result.content.contains("<object"))
    }

    @Test func emptyFirstParagraphProducesAnEmptyExcerptInsteadOfNil() throws {
        let html = """
        <!doctype html><html><head><title>Image excerpt regression</title></head><body><article>
          <p><img src="hero.jpg" alt=""></p>
          <p>This substantive article paragraph follows an image-only paragraph. It contains enough editorial prose, punctuation, and explanatory detail to make extraction deterministic while leaving the first retained paragraph without text.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.excerpt == Optional(""))
    }

    @Test func whitespaceOnlyCommentsAreSkippedWhenCleaningTrailingBreaks() throws {
        let html = """
        <!doctype html><html><head><title>Trailing break regression</title></head><body><article>
          <h1>Trailing break regression</h1>
          <p>Alpha prose is deliberately long enough to make this candidate stable and readable. More words follow so extraction consistently retains the selected paragraph and its siblings.</p>
          <br><!--   --><p>Beta prose follows the break and should cause Mozilla cleanup to delete that break even with a whitespace-only comment between them. This paragraph is also intentionally substantial.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(!result.content.contains("<br"))
        #expect(result.content.contains("<!--   -->"))
    }

    @Test func customSerializerObservesMozillasReadabilityContentRootID() throws {
        let html = """
        <!doctype html><html><body><article>
          <p>Substantial article prose gives the custom serializer a stable extracted root to inspect.</p>
        </article></body></html>
        """
        let options = ReadabilityOptions(
            charThreshold: 1,
            serializer: { $0.id() }
        )

        let result = try #require(try Readability(html: html, url: baseURL, options: options).parse())

        #expect(result.content == "readability-content")
    }
}
