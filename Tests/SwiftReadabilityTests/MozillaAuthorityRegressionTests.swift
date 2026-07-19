import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

/// Focused boundaries where the inherited Swift implementation once diverged
/// from the pinned Mozilla Readability source. These tests intentionally use
/// small documents so a corpus pass cannot hide a semantic mismatch.
struct MozillaAuthorityRegressionTests {
    private let baseURL = URL(string: "https://example.com/articles/story")!

    @Test func directionComesFromTheSelectedCandidatesOriginalAncestors() throws {
        let html = """
        <html><body>
          <section dir="rtl">
            <div class="article-content">
              <p>هذه فقرة عربية طويلة بما يكفي لاختيار الحاوية الداخلية بوصفها محتوى المقالة الأساسي مع الاحتفاظ باتجاه السلف الأصلي.</p>
              <p>ويجب أن يبقى اتجاه النص من اليمين إلى اليسار بعد نقل المرشح إلى حاوية القراءة الجديدة.</p>
            </div>
          </section>
        </body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.dir == "rtl")
    }

    @Test func directionIsStillResolvedWhenTheLongestFallbackAttemptWins() throws {
        let html = """
        <html><body>
          <section dir="rtl"><article>
            <p>مقالة قصيرة ذات اتجاه صريح يجب ألا تفقد اتجاهها عندما تعيد الخوارزمية أطول محاولة بعد استنفاد أعلام التنظيف.</p>
          </article></section>
        </body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 10_000)
        ).parse())

        #expect(result.dir == "rtl")
    }

    @Test func commentsInsideSelectedContentRemainObservable() throws {
        let html = """
        <html><body><article>
          <p>The first paragraph supplies enough coherent prose for the article candidate to be selected by the native implementation.</p>
          <!--marker-kept-->
          <p>The second paragraph keeps the comment between two retained pieces of editorial content.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.content.contains("<!--marker-kept-->"))
    }

    @Test func normalizedTextLengthDoesNotInventWhitespaceAtBlockBoundaries() throws {
        let document = try SwiftSoup.parse("<div id='story'><p>alpha</p><p>beta</p></div>")
        let story = try #require(try document.getElementById("story"))
        let sourceTextContent = textContentPreservingWhitespace(of: story)

        #expect(sourceTextContent == "alphabeta")
        #expect(javaScriptNormalizedTextLength(sourceTextContent) == 9)
    }

    @Test(arguments: [
        ("\u{0085}", false), // NEXT LINE is not ECMAScript whitespace.
        ("\u{200B}", false), // ZERO WIDTH SPACE is not ECMAScript whitespace.
        ("\u{FEFF}", true),  // BOM is ECMAScript whitespace.
    ])
    func whitespaceClassificationMatchesECMAScript(character: String, isWhitespace: Bool) {
        #expect(javaScriptIsWhitespaceOnly(character) == isWhitespace)
        #expect(javaScriptTrim(character).isEmpty == isWhitespace)
    }

    @Test func getInnerTextUsesECMAScriptTrimAndWhitespaceNormalization() throws {
        let document = try SwiftSoup.parseBodyFragment(
            "<div id='story'>\u{FEFF}\u{FEFF}alpha\u{0085}\u{0085}beta\u{200B}\u{200B}gamma\u{FEFF}</div>"
        )
        let story = try #require(try document.getElementById("story"))

        #expect(
            ProcessorBase().getInnerText(story, regEx: RegExUtil()) ==
                "alpha\u{0085}\u{0085}beta\u{200B}\u{200B}gamma"
        )
    }

    @Test(arguments: [
        ("\u{0085}\u{0085}", true),
        ("\u{200B}\u{200B}", true),
        ("\u{FEFF}\u{FEFF}", false),
    ])
    func readerabilityUsesECMAScriptTrim(characterRun: String, expected: Bool) {
        let html = "<html><body><article>\(characterRun)</article></body></html>"
        let options = Readability.ReaderableOptions(minContentLength: 1, minScore: 0)

        #expect(Readability.isProbablyReaderable(html: html, options: options) == expected)
    }

    @Test(arguments: [
        "background-image: url('display:none')",
        "display: nonefoo",
        "visibility: hiddenish",
    ])
    func styleTextThatMerelyContainsHiddenWordsDoesNotHideContent(style: String) throws {
        let marker = "Visible editorial prose survives a CSS substring that is not the display or visibility property value."
        let html = """
        <html><body><article>
          <div style="\(style)">
            <p>\(marker)</p>
            <p>A second connected paragraph makes this content an unambiguous article candidate.</p>
          </div>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.textContent.contains(marker))
    }

    @Test(arguments: [
        ("display: none; display: block", true),
        ("display: block; display: none", false),
        ("display: none !important; display: block", false),
        ("display: block !important; display: none", true),
        ("display: none; display: nonefoo", false),
        ("visibility: visible; visibility: hidden", false),
        ("visibility: hidden !important; visibility: visible", false),
        ("background-image: url('display:none'); display: block", true),
    ])
    func parsedInlineStyleControlsExtractionVisibility(style: String, expectedVisible: Bool) throws {
        let marker = "Editorial marker whose visibility follows the parsed declaration block."
        let html = """
        <html><body><article>
          <div style="\(style)">
            <p>\(marker)</p>
            <p>A second substantial paragraph makes this content an unambiguous article candidate.</p>
          </div>
          <p>Visible fallback prose keeps extraction successful regardless of the styled node.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.textContent.contains(marker) == expectedVisible)
    }

    @Test(arguments: [
        ("display: none; display: block", true),
        ("display: block; display: none", false),
        ("display: none !important; display: block", false),
        ("display: none; display: nonefoo", false),
        // Mozilla's lightweight heuristic checks display but not visibility.
        ("visibility: hidden; visibility: visible", true),
        ("visibility: visible; visibility: hidden", true),
    ])
    func parsedInlineStyleControlsReaderabilityVisibility(style: String, expectedVisible: Bool) {
        let prose = String(repeating: "Readerable editorial prose with detail. ", count: 8)
        let html = "<html><body><article style=\"\(style)\">\(prose)</article></body></html>"
        let options = Readability.ReaderableOptions(minContentLength: 1, minScore: 0)

        #expect(Readability.isProbablyReaderable(html: html, options: options) == expectedVisible)
    }

    @Test(arguments: [
        ("display:none;display:block", "block"),
        ("display:none!important;display:block", "none"),
        ("display:block!important;display:none", "block"),
        ("display:block!important;display:none!important", "block"),
        ("display:none;display:nonefoo", "none"),
        ("background-image:url('display:none');display:block", "block"),
        ("display:none;/* semicolon ; */display:block", "block"),
    ])
    func inlineStyleParserMatchesCSSDeclarationPrecedence(style: String, expectedDisplay: String) {
        #expect(InlineStyleDeclarations(style).value(for: "display") == expectedDisplay)
    }

    @Test func zeroTopCandidateCountUsesMozillasDefault() {
        let reader = Readability(
            html: "<html><body><p>Article prose.</p></body></html>",
            url: baseURL,
            options: ReadabilityOptions(nbTopCandidates: 0)
        )

        #expect(reader.nbTopCandidates == ReadabilityOptions.defaultNTopCandidates)
    }

    @Test func zeroCharacterThresholdBehavesLikeMozillasDefault() throws {
        let primary = String(repeating: "Primary editorial sentence, with punctuation and context. ", count: 5)
        let unlikely = String(repeating: "Supplemental unlikely prose becomes available only on a relaxed retry. ", count: 8)
        let html = """
        <html><body>
          <div class="article content"><p>\(primary)</p></div>
          <div class="comment"><p>\(unlikely)</p></div>
        </body></html>
        """

        let zero = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        ).parse()
        let defaulted = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions()
        ).parse()

        #expect(zero?.content == defaulted?.content)
        #expect(zero?.textContent == defaulted?.textContent)
    }

    @Test func maximumElementCountUsesTheDOMElementBoundary() throws {
        let html = """
        <html><head><title>Boundary</title></head><body>
          <main><article><p>Enough concise article prose to produce a nonempty result at the exact element-count boundary.</p></article></main>
        </body></html>
        """
        // html, head, title, body, main, article, and p. The browser API used
        // by Mozilla does not include the Document receiver in this count.
        let browserElementCount = 7

        _ = try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(maxElemsToParse: browserElementCount, charThreshold: 1)
        ).parse()

        do {
            _ = try Readability(
                html: html,
                url: baseURL,
                options: ReadabilityOptions(maxElemsToParse: browserElementCount - 1, charThreshold: 1)
            ).parse()
            Issue.record("Mozilla rejects a document only when its element count exceeds the configured maximum.")
        } catch {
            #expect(error.localizedDescription.contains("Aborting parsing document"))
        }
    }

    @Test func customVideoRegexIsAppliedToEachAttributeIndividually() throws {
        let regex = try NSRegularExpression(pattern: "left\\|right")
        let html = """
        <html><body><article>
          <p>This ordinary article includes an unrelated iframe whose separate attributes must not be concatenated before regex matching.</p>
          <p>A second substantial paragraph ensures the surrounding article remains readable after the iframe is removed.</p>
          <iframe data-first="left" data-second="right"></iframe>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(
                charThreshold: 1,
                allowedVideoRegex: regex
            )
        ).parse())

        #expect(!result.content.contains("<iframe"))
    }

    @Test func traversalStartsAtTheDocumentElementAndCanRemoveAnUnlikelyBase() throws {
        let html = """
        <html><head>
          <base class="sidebar" href="https://wrong.example/assets/">
        </head><body><article>
          <p>This article contains enough ordinary editorial prose to keep its relative link in the selected content.</p>
          <p><a id="relative" href="related.html">The relative link must resolve from the source document after the unlikely base is removed.</a></p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse())
        let resultDocument = try SwiftSoup.parseBodyFragment(result.content)

        #expect(
            try resultDocument.select("#relative").attr("href")
                == "https://example.com/articles/related.html"
        )
    }

    @Test(arguments: [
        ("<html lang=\"\">", Optional("")),
        ("<html>", nil),
    ])
    func languagePreservesTheDifferenceBetweenEmptyAndMissingHTMLAttributes(
        openingHTML: String,
        expected: String?
    ) throws {
        let html = """
        \(openingHTML)<body><article>
          <p>A concise article provides enough text for language-contract extraction.</p>
          <p>The result must preserve browser getAttribute semantics exactly.</p>
        </article></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())
        #expect(result.lang == expected)
    }

    @Test func documentElementIsNotAContentScoringCandidate() throws {
        let prose = String(
            repeating: "Shallow editorial prose, with enough punctuation and detail to become a scoring candidate. ",
            count: 4
        )
        let html = """
        <html class="article"><body class="sidebar"><p id="story">\(prose)</p></body></html>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse())
        let resultDocument = try SwiftSoup.parseBodyFragment(result.content)

        #expect(try resultDocument.select("html").count == 1)
        #expect(try resultDocument.select("body").count == 1)
        #expect(try resultDocument.select("#story").count == 1)
        #expect(!result.content.contains("class=\"article\""))
    }

    @Test func classNameUsesTheRawDOMAttributeValue() throws {
        let document = try SwiftSoup.parseBodyFragment(
            "<div id=\"candidate\" class=\"  article   content  \"></div>"
        )
        let candidate = try #require(try document.select("#candidate").first())

        #expect(candidate.classNameSafe() == "  article   content  ")
    }
}
