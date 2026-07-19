import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

/// URL post-processing is specified by Mozilla Readability's use of the browser
/// `URL` constructor. These expectations are therefore WHATWG URL serialization
/// results, not Foundation URL spellings.
struct PostprocessorURLResolutionTests {
    private let documentURI = "https://Example.COM:443/a/b/index.html?old=1#old"

    @Test func resolvesAndSerializesSpecialSchemeURLsLikeMozilla() throws {
        let article = try postprocessedArticle(
            body: """
            <a id="backslash" href="..\\images\\photo.png">Backslash</a>
            <a id="dots" href="./x/../y/./z">Dots</a>
            <a id="default-port" href="HTTP://EXAMPLE.COM:80/a">Port</a>
            <a id="query-fragment" href="?next=two words#frag ment">Query</a>
            <a id="network-path" href="//CDN.Example.COM:443/assets/a.png">CDN</a>
            <a id="encoded-dots" href="/a/%2e%2e/b/%2E/c">Encoded dots</a>
            <a id="credentials" href="https://user:pass@EXAMPLE.COM:443">Credentials</a>
            """
        )

        #expect(try attribute("href", of: "#backslash", in: article) == "https://example.com/a/images/photo.png")
        #expect(try attribute("href", of: "#dots", in: article) == "https://example.com/a/b/y/z")
        #expect(try attribute("href", of: "#default-port", in: article) == "http://example.com/a")
        #expect(try attribute("href", of: "#query-fragment", in: article) == "https://example.com/a/b/index.html?next=two%20words#frag%20ment")
        #expect(try attribute("href", of: "#network-path", in: article) == "https://cdn.example.com/assets/a.png")
        #expect(try attribute("href", of: "#encoded-dots", in: article) == "https://example.com/b/c")
        #expect(try attribute("href", of: "#credentials", in: article) == "https://user:pass@example.com/")
    }

    @Test func preservesInvalidInputsExactlyAsMozillaDoes() throws {
        let article = try postprocessedArticle(
            body: """
            <a id="bad-path-escape" href="bad%zz path">Bad path escape</a>
            <a id="bad-host-escape" href="https://exa%zzmple.com/">Bad host escape</a>
            <a id="bad-ipv6" href="http://[::1">Bad IPv6</a>
            <img id="bad-src" src="//[::1">
            """
        )

        #expect(try attribute("href", of: "#bad-path-escape", in: article) == "https://example.com/a/b/bad%zz%20path")
        #expect(try attribute("href", of: "#bad-host-escape", in: article) == "https://exa%zzmple.com/")
        #expect(try attribute("href", of: "#bad-ipv6", in: article) == "http://[::1")
        #expect(try attribute("src", of: "#bad-src", in: article) == "//[::1")
    }

    @Test func handlesNonHTTPSchemesLikeMozilla() throws {
        let article = try postprocessedArticle(
            body: """
            <a id="ftp" href="ftp://EXAMPLE.com:21/file">FTP</a>
            <a id="mailto" href="mailto:Name@example.com">Mail</a>
            <a id="custom" href="custom:opaque path">Custom</a>
            <img id="data" src="data:text/plain,hello world">
            <img id="file" src="file:///C|/folder/../photo.png">
            """
        )

        #expect(try attribute("href", of: "#ftp", in: article) == "ftp://example.com/file")
        #expect(try attribute("href", of: "#mailto", in: article) == "mailto:Name@example.com")
        #expect(try attribute("href", of: "#custom", in: article) == "custom:opaque path")
        #expect(try attribute("src", of: "#data", in: article) == "data:text/plain,hello world")
        #expect(try attribute("src", of: "#file", in: article) == "file:///C:/photo.png")
    }

    @Test func usesFirstBaseElementAndWHATWGBaseResolution() throws {
        let article = try postprocessedArticle(
            head: """
            <base href="../assets/">
            <base href="https://ignored.example/">
            """,
            body: """
            <a id="link" href="page.html">Page</a>
            <img id="image" src="//CDN.Example.COM:443/image.png">
            """
        )

        #expect(try attribute("href", of: "#link", in: article) == "https://example.com/a/assets/page.html")
        #expect(try attribute("src", of: "#image", in: article) == "https://cdn.example.com/image.png")
    }

    @Test func invalidFirstBaseDoesNotFallThroughToLaterBase() throws {
        let article = try postprocessedArticle(
            head: """
            <base href="http://[::1">
            <base href="https://second.example/">
            """,
            body: "<a id=\"link\" href=\"page.html\">Page</a>"
        )

        #expect(try attribute("href", of: "#link", in: article) == "https://example.com/a/b/page.html")
    }

    @Test func emptyBaseStillChangesHashOnlyResolution() throws {
        let article = try postprocessedArticle(
            head: "<base href=\"\">",
            body: "<a id=\"hash\" href=\"#target\">Target</a>"
        )

        // An empty <base href> resolves to the document URL with its fragment removed.
        // It therefore differs from documentURI, so Mozilla makes this hash absolute.
        #expect(try attribute("href", of: "#hash", in: article) == "https://example.com/a/b/index.html?old=1#target")
    }

    @Test func noBaseLeavesHashOnlyLinksRelative() throws {
        let article = try postprocessedArticle(
            body: "<a id=\"hash\" href=\"#target\">Target</a>"
        )

        #expect(try attribute("href", of: "#hash", in: article) == "#target")
    }

    @Test func appliesWHATWGResolutionToSrcsetCandidates() throws {
        let article = try postprocessedArticle(
            body: """
            <picture>
              <source id="source" srcset="..\\small.png 1x, //CDN.Example.COM:443/large.png 2x">
            </picture>
            """
        )

        #expect(
            try attribute("srcset", of: "#source", in: article)
                == "https://example.com/a/small.png 1x, https://cdn.example.com/large.png 2x"
        )
    }

    @Test func preservesMozillaAttributeTruthinessAndJavascriptPrefixRules() throws {
        let article = try postprocessedArticle(
            body: """
            <a id="whitespace" href="   ">Whitespace</a>
            <a id="leading-javascript" href=" javascript:alert(1)">Leading</a>
            <a id="uppercase-javascript" href="JavaScript:alert(2)">Uppercase</a>
            <a id="exact-javascript" href="javascript:alert(3)">Removed link text</a>
            """
        )

        // JavaScript considers a whitespace-only attribute truthy; the URL parser
        // then treats it as an empty reference and removes the base fragment.
        #expect(try attribute("href", of: "#whitespace", in: article) == "https://example.com/a/b/index.html?old=1")
        // Readability removes only a raw, case-sensitive `javascript:` prefix.
        #expect(try attribute("href", of: "#leading-javascript", in: article) == "javascript:alert(1)")
        #expect(try attribute("href", of: "#uppercase-javascript", in: article) == "javascript:alert(2)")
        #expect(try article.select("#exact-javascript").isEmpty())
        #expect(try article.text().contains("Removed link text"))
    }

    @Test func srcsetTokenizationUsesECMAScriptWhitespace() throws {
        let article = try postprocessedArticle(
            body: """
            <picture>
              <source id="source" srcset="small.png 1x, large.png﻿2x">
            </picture>
            """
        )

        // ECMAScript `\s` excludes U+0085, so it is part of the first URL and
        // is percent-encoded. U+FEFF is whitespace and remains the descriptor gap.
        #expect(
            try attribute("srcset", of: "#source", in: article)
                == "https://example.com/a/b/small.png%C2%85 1x, https://example.com/a/b/large.png﻿2x"
        )
    }

    @Test func srcsetDescriptorsUseECMAScriptASCIIDigits() throws {
        let article = try postprocessedArticle(
            body: """
            <picture>
              <source id="source" srcset="small.png ٢x, large.png 2x">
            </picture>
            """
        )

        // JavaScript `\d` without a UnicodeSets extension matches only ASCII.
        // The Arabic-Indic digit therefore begins a second URL token rather than
        // becoming a density descriptor for `small.png`.
        #expect(
            try attribute("srcset", of: "#source", in: article)
                == "small.png https://example.com/a/b/%D9%A2x, https://example.com/a/b/large.png 2x"
        )
    }

    @Test func nestedSimplificationUsesECMAScriptTrim() throws {
        let article = try postprocessedArticle(
            body: """
            <section id="outer"><div id="inner"><p>Editorial text.</p></div></section>
            """
        )

        // U+0085 is not removed by JavaScript trim(), so the section has
        // observable text and must not be collapsed into its only child.
        let outer = try #require(article.select("#outer").first())
        #expect(outer.tagName() == "section")
        #expect(try outer.select("#inner").first() != nil)
    }

    // Mozilla's helper is the unusual `/\S$/`, not an ordinary "contains
    // non-whitespace" test. A text node ending in whitespace therefore does
    // not prevent its sole nested DIV/SECTION from replacing the parent.
    @Test func nestedSimplificationUsesMozillasTrailingContentTest() throws {
        let article = try postprocessedArticle(
            body: """
            <section id="outer" data-parent="kept">prefix <div id="inner"><p>Editorial text.</p></div></section>
            """
        )

        let replacement = try #require(article.select("#outer").first())
        #expect(replacement.tagName() == "div")
        #expect(try replacement.attr("data-parent") == "kept")
        #expect(try article.select("#inner").isEmpty())
        #expect(try !article.text().contains("prefix"))
    }

    @Test func classCleaningPreservesDuplicatesAndUsesECMAScriptWhitespace() throws {
        let document = try SwiftSoup.parse(
            "<html><body><article id=\"article\" class=\"keep keep drop﻿keep dropkeep\">Text</article></body></html>",
            documentURI
        )
        let article = try #require(document.select("#article").first())

        Postprocessor().postProcessContent(
            originalDocument: document,
            articleContent: article,
            articleUri: documentURI,
            keepClasses: false,
            classesToPreserve: ["keep", "drop"]
        )

        // Mozilla's filter does not deduplicate tokens. U+FEFF splits a token;
        // U+0085 does not, so `drop\u{0085}keep` is discarded as one token.
        #expect(try article.attr("class") == "keep keep drop keep")
    }

    private func postprocessedArticle(head: String = "", body: String) throws -> Element {
        let document = try SwiftSoup.parse(
            "<html><head>\(head)</head><body><article id=\"article\">\(body)</article></body></html>",
            documentURI
        )
        let article = try #require(document.select("#article").first())
        Postprocessor().postProcessContent(
            originalDocument: document,
            articleContent: article,
            articleUri: documentURI,
            keepClasses: true
        )
        return article
    }

    private func attribute(_ name: String, of selector: String, in article: Element) throws -> String {
        let element = try #require(article.select(selector).first())
        return try element.attr(name)
    }
}
