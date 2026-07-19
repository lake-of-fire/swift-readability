import SwiftSoup
import Testing
@testable import SwiftReadability

struct MetadataParserTests {
    @Test func unicodeBeforeMatchedMetaPropertyDoesNotCrash() throws {
        let document = try SwiftSoup.parse(
            #"<html><head><meta property="😀 og:title" content="Unicode-safe title"></head></html>"#
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == "Unicode-safe title")
    }

    // Source map: Mozilla Readability._textSimilarity splits on `/\W+/g`.
    // In JavaScript that expression recognizes only ASCII letters, digits, and
    // underscore as word characters; Unicode letters are separators.
    @Test func jsonLDTitleSimilarityUsesMozillaASCIIWordTokens() throws {
        let htmlTitle = "猫 猫 猫 猫 猫 猫 猫 猫 alpha"
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>\(htmlTitle)</title>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org",
                  "@type": "NewsArticle",
                  "name": "猫",
                  "headline": "\(htmlTitle)"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == htmlTitle)
    }

    // Source map: Mozilla Readability._getArticleTitle compares an H1/H2's
    // raw DOM `textContent.trim()`, not a rendered/normalized text projection.
    @Test func colonTitleHeadingMatchUsesRawDOMTextContent() throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Brand: A Thorough Article Title About Native Swift</title>
            </head><body>
              <h1>Brand:\n A Thorough Article Title About Native Swift</h1>
            </body></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == "A Thorough Article Title About Native Swift")
    }

    // Source map: in Mozilla Readability._getJSONLD, the branch where both
    // `name` and `headline` exist deliberately assigns the selected raw value.
    @Test(
        arguments: [
            (
                title: "Canonical Article Title With Enough Words",
                name: "  Publisher Label  ",
                headline: "An Unrelated Headline",
                expected: "  Publisher Label  "
            ),
            (
                title: "Canonical Article Title With Enough Words",
                name: "Publisher Label",
                headline: "  Canonical Article Title With Enough Words  ",
                expected: "  Canonical Article Title With Enough Words  "
            ),
        ]
    )
    func bothPresentJSONLDTitleBranchesPreserveWhitespace(
        example: (title: String, name: String, headline: String, expected: String)
    ) throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>\(example.title)</title>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org",
                  "@type": "NewsArticle",
                  "name": "\(example.name)",
                  "headline": "\(example.headline)"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == example.expected)
    }

    // Source map: Mozilla Readability._getJSONLD only enters its author-array
    // branch when the first entry exists and has a string `name`.
    @Test func jsonLDAuthorArrayWithInvalidFirstEntryIsIgnored() throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Article Title With Several Useful Words</title>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org",
                  "@type": "NewsArticle",
                  "headline": "Article Title With Several Useful Words",
                  "author": [{"@type": "Organization"}, {"name": "Later Author"}]
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.byline == nil)
    }

    // JavaScript Array.find evaluates its callback in order. Accessing @type on
    // `null`, or calling `.match` on a truthy non-string @type, throws and makes
    // Mozilla reject that entire JSON-LD script. Falsey non-string values do not.
    @Test(arguments: [
        (
            json: #"[null,{"@context":"https://schema.org","@type":"NewsArticle","headline":"Wrong"}]"#,
            expected: "Fallback Document Title With Enough Words"
        ),
        (
            json: #"[{"@type":true},{"@context":"https://schema.org","@type":"NewsArticle","headline":"Wrong"}]"#,
            expected: "Fallback Document Title With Enough Words"
        ),
        (
            json: #"{"@context":"https://schema.org","@graph":[null,{"@type":"NewsArticle","headline":"Wrong"}]}"#,
            expected: "Fallback Document Title With Enough Words"
        ),
        (
            json: #"{"@context":"https://schema.org","@graph":[{"@type":{}},{"@type":"NewsArticle","headline":"Wrong"}]}"#,
            expected: "Fallback Document Title With Enough Words"
        ),
        (
            json: #"[{"@type":0},{"@context":"https://schema.org","@type":"NewsArticle","headline":"Accepted"}]"#,
            expected: "Accepted"
        ),
        (
            json: #"{"@context":"https://schema.org","@graph":[{"@type":0},{"@type":"NewsArticle","headline":"Accepted"}]}"#,
            expected: "Accepted"
        ),
    ])
    func malformedJSONLDSearchUsesMozillasOrderedFailureSemantics(
        example: (json: String, expected: String)
    ) throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Fallback Document Title With Enough Words</title>
              <script type="application/ld+json">\(example.json)</script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == example.expected)
    }

    // Source map: Mozilla's schema.org context regex is intentionally
    // case-sensitive. This prevents the native port from accepting JSON-LD
    // that the pinned authority rejects.
    @Test func jsonLDSchemaContextMatchingIsCaseSensitive() throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Fallback Document Title With Enough Words</title>
              <script type="application/ld+json">
                {
                  "@context": "https://SCHEMA.ORG",
                  "@type": "NewsArticle",
                  "headline": "JSON LD Title That Mozilla Rejects"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == "Fallback Document Title With Enough Words")
    }

    // ECMAScript `$` matches only the actual end of the input here. ICU also
    // matches before Unicode line separators such as U+0085, which would make
    // the native parser accept a schema context rejected by pinned Mozilla.
    @Test func jsonLDSchemaContextRequiresTheECMAScriptEndOfInput() throws {
        let nextLine = "\u{0085}"
        let fallback = "Fallback Document Title With Enough Words"
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>\(fallback)</title>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org\(nextLine)",
                  "@type": "NewsArticle",
                  "headline": "JSON LD Title That Mozilla Rejects"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == fallback)
    }

    // `APIReference` is the only final alternative anchored with `$` in
    // Mozilla's intentionally asymmetric JSON-LD type expression.
    @Test func jsonLDAPIReferenceTypeRequiresTheECMAScriptEndOfInput() throws {
        let nextLine = "\u{0085}"
        let fallback = "Fallback Document Title With Enough Words"
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>\(fallback)</title>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org",
                  "@type": "APIReference\(nextLine)",
                  "headline": "JSON LD Title That Mozilla Rejects"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == fallback)
    }

    // Mozilla enumerates every script and then uses exact string equality on
    // its `type` attribute; SwiftSoup's CSS attribute selector is broader.
    @Test(
        arguments: ["APPLICATION/LD+JSON", " application/ld+json "]
    )
    func jsonLDScriptTypeRequiresMozillaExactMatch(type: String) throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Fallback Document Title With Enough Words</title>
              <script type="\(type)">
                {
                  "@context": "https://schema.org",
                  "@type": "NewsArticle",
                  "headline": "JSON LD Title That Mozilla Rejects"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == "Fallback Document Title With Enough Words")
    }

    // Source map: Mozilla Readability._isUrl uses the browser's one-argument
    // WHATWG `new URL(value)`. Foundation.URL accepts incomplete values such as
    // `http://`, which incorrectly suppresses them as article-author URLs.
    @Test func articleAuthorURLDetectionUsesWHATWGParsing() throws {
        let incompleteURLDocument = try SwiftSoup.parse(
            """
            <html><head>
              <title>Article Title With Several Useful Words</title>
              <meta property="article:author" content="http://">
            </head></html>
            """
        )
        let validURLDocument = try SwiftSoup.parse(
            """
            <html><head>
              <title>Article Title With Several Useful Words</title>
              <meta property="article:author" content="https://example.com/author">
            </head></html>
            """
        )

        let parser = MetadataParser()
        let incomplete = parser.getArticleMetadata(incompleteURLDocument, disableJSONLD: true)
        let valid = parser.getArticleMetadata(validURLDocument, disableJSONLD: true)

        #expect(incomplete.byline == "http://")
        #expect(valid.byline == nil)
    }

    // Mozilla's metadata `trim()` sites follow ECMAScript whitespace, which
    // removes U+FEFF but preserves U+0085 and U+200B.
    @Test(arguments: [
        ("\u{FEFF}Metadata Title\u{FEFF}", "Metadata Title"),
        ("\u{0085}Metadata Title\u{0085}", "\u{0085}Metadata Title\u{0085}"),
        ("\u{200B}Metadata Title\u{200B}", "\u{200B}Metadata Title\u{200B}"),
    ])
    func metaContentUsesECMAScriptTrim(example: (input: String, expected: String)) throws {
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Fallback Document Title With Enough Words</title>
              <meta property="og:title" content="\(example.input)">
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == example.expected)
    }

    // Mozilla's metadata key patterns and subsequent `replace(/\s/g, "")`
    // share ECMAScript's whitespace table. U+FEFF is whitespace there, while
    // U+0085 and U+200B are literal characters and must prevent a key match.
    @Test(arguments: [
        (attribute: "property", whitespace: "\u{FEFF}", matches: true),
        (attribute: "property", whitespace: "\u{0085}", matches: false),
        (attribute: "property", whitespace: "\u{200B}", matches: false),
        (attribute: "name", whitespace: "\u{FEFF}", matches: true),
        (attribute: "name", whitespace: "\u{0085}", matches: false),
        (attribute: "name", whitespace: "\u{200B}", matches: false),
    ])
    func metaKeyPatternsUseECMAScriptWhitespace(
        example: (attribute: String, whitespace: String, matches: Bool)
    ) throws {
        let fallback = "Fallback Document Title With Enough Words"
        let key = "og\(example.whitespace):\(example.whitespace)title"
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>\(fallback)</title>
              <meta \(example.attribute)="\(key)" content="Structured Metadata Title">
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == (example.matches ? "Structured Metadata Title" : fallback))
    }

    // The separators in Mozilla `_getArticleTitle` are surrounded by JS `\s`,
    // not Foundation/ICU whitespace. This is observable before the short-title
    // fallback because the retained left side contains more than four words.
    @Test(arguments: [
        (whitespace: "\u{FEFF}", separates: true),
        (whitespace: "\u{0085}", separates: false),
        (whitespace: "\u{200B}", separates: false),
    ])
    func titleSeparatorsUseECMAScriptWhitespace(
        example: (whitespace: String, separates: Bool)
    ) throws {
        let articleTitle = "Long Article Title With Enough Words"
        let fullTitle =
            "\(articleTitle)\(example.whitespace)|\(example.whitespace)Publisher Name"
        let document = try SwiftSoup.parse("<html><head><title>\(fullTitle)</title></head></html>")

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == (example.separates ? articleTitle : fullTitle))
    }

    // Mozilla strips JSON-LD CDATA sentinels using
    // `/^\s*<!\[CDATA\[|\]\]>\s*$/g`; both anchors therefore use the same
    // ECMAScript whitespace table as `trim()`.
    @Test(arguments: [
        (whitespace: "\u{FEFF}", stripsMarkers: true),
        (whitespace: "\u{0085}", stripsMarkers: false),
        (whitespace: "\u{200B}", stripsMarkers: false),
    ])
    func jsonLDCDATABoundariesUseECMAScriptWhitespace(
        example: (whitespace: String, stripsMarkers: Bool)
    ) throws {
        let fallback = "Fallback Document Title With Enough Words"
        let json =
            #"{"@context":"https://schema.org","@type":"NewsArticle","headline":"CDATA Article Title"}"#
        let document = try SwiftSoup.parse(
            """
            <html><head><title>\(fallback)</title><script type="application/ld+json">\(example.whitespace)<![CDATA[\(json)]]>\(example.whitespace)</script></head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == (example.stripsMarkers ? "CDATA Article Title" : fallback))
    }

    @Test func singleJSONLDTitleAndFieldsUseECMAScriptTrim() throws {
        let nextLine = "\u{0085}"
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>Fallback Document Title With Enough Words</title>
              <script type="application/ld+json">
                {
                  "@context": "https://schema.org",
                  "@type": "NewsArticle",
                  "headline": "\(nextLine)Structured Title\(nextLine)",
                  "author": {"name": "\(nextLine)Author Name\(nextLine)"},
                  "description": "\(nextLine)Description\(nextLine)",
                  "publisher": {"name": "\(nextLine)Publisher\(nextLine)"},
                  "datePublished": "\(nextLine)2026-07-20\(nextLine)"
                }
              </script>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: false)

        #expect(metadata.title == "\(nextLine)Structured Title\(nextLine)")
        #expect(metadata.byline == "\(nextLine)Author Name\(nextLine)")
        #expect(metadata.excerpt == "\(nextLine)Description\(nextLine)")
        #expect(metadata.siteName == "\(nextLine)Publisher\(nextLine)")
        #expect(metadata.publishedTime == "\(nextLine)2026-07-20\(nextLine)")
    }

    // The DOM `document.title` getter collapses only HTML ASCII whitespace;
    // Readability then applies ECMAScript trim. SwiftSoup's convenience getter
    // uses a broader whitespace definition, so the port must not delegate here.
    @Test func documentTitlePreservesNonHTMLWhitespaceLikeMozilla() throws {
        let nextLine = "\u{0085}"
        let document = try SwiftSoup.parse(
            """
            <html><head>
              <title>\(nextLine)Alpha   Beta   Gamma   Delta   Epsilon\(nextLine)</title>
            </head></html>
            """
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == "\(nextLine)Alpha Beta Gamma Delta Epsilon\(nextLine)")
    }
}
