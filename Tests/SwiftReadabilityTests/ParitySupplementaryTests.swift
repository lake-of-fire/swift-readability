import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import SwiftSoup
import Testing
@testable import SwiftReadability

struct ParitySupplementaryTests {
    private let baseURL = URL(string: "http://example.com")!

    @Test(arguments: ["custom:flag ", "😀 ", "e\u{301} ", "🧑‍💻 "])
    func metadataPropertiesUseUTF16MatchRanges(prefix: String) throws {
        let html = """
        <html><head><title>Fallback</title>
        <meta property="\(prefix)og:title twitter:title" content="Selected title">
        <meta property="\(prefix)dc:creator article:author" content="Selected author">
        <meta property="\(prefix)og:description twitter:description" content="Selected description">
        <meta property="\(prefix)og:site_name" content="Selected site">
        <meta property="\(prefix)article:published_time" content="2026-11-06T12:00:00Z">
        </head><body><p>Article body.</p></body></html>
        """
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)
        #expect(metadata.title == "Selected title")
        #expect(metadata.byline == "Selected author")
        #expect(metadata.excerpt == "Selected description")
        #expect(metadata.siteName == "Selected site")
        #expect(metadata.publishedTime == "2026-11-06T12:00:00Z")
    }

    @Test func documentPipelineMutatesOriginalDOM() throws {
        let html = "<html><head><script>console.log('x')</script></head><body><p>Hello world</p></body></html>"
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let reader = Readability(document: doc)
        _ = try reader.parse()
        let scripts = try doc.select("script")
        #expect(scripts.count == 0)
    }

    @Test func documentPipelineReflectsMutations() throws {
        let html = "<html><body><article><p id='target'>old.</p></article></body></html>"
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        try doc.select("#target").first()?.text("new.")
        let reader = Readability(document: doc, options: ReadabilityOptions(charThreshold: 0))
        let result = try reader.parse()
        #expect(result?.content.contains("new.") == true)
    }

    @Test func xmlSerializerOptionProducesXMLSyntax() throws {
        let html = "<html><body><p>hello there hello there hello there hello there hello there hello there hello there hello there hello there hello there.</p><p><img src=\"\"></p></body></html>"
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0, useXMLSerializer: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("<img"))
        #expect(result.content.contains("/>"))
    }

    @Test func xmlDocumentSerializerReturnsWellFormedXML() throws {
        let source = """
        <?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Article</title></head><body>
        <article itemscope=""><p>Hello&#xa0;there. \(String(repeating: "A readable paragraph. ", count: 25))</p>
        <p><img src="picture.jpg" /></p></article></body></html>
        """
        let inputParser = XMLParser(data: Data(source.utf8))
        #expect(inputParser.parse())
        let document = try SwiftSoup.parse(source, baseURL.absoluteString, Parser.xmlParser())
        let parsedResult = try Readability(
            document: document,
            options: ReadabilityOptions(charThreshold: 0, useXMLSerializer: true)
        ).parse()
        let result = try #require(parsedResult)
        let parser = XMLParser(data: Data(("<root>" + result.content + "</root>").utf8))
        #expect(parser.parse(), "XML serializer returned invalid XML: \(String(describing: parser.parserError))")
        let parsed = try SwiftSoup.parse(result.content, baseURL.absoluteString, Parser.xmlParser())
        let articles = try parsed.select("article")
        let article = try #require(articles.first())
        #expect(article.hasAttr("itemscope"))
        #expect(try article.attr("itemscope") == "")
        #expect(try article.text().hasPrefix("Hello there."))
    }

    @Test func htmlSerializerDefaultUsesHtmlBooleanSyntax() throws {
        let html = """
        <html>
          <body>
            <article id="target" itemscope="itemscope" itemtype="https://schema.org/Article">
              <p>hello there hello there hello there hello there hello there.</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("itemscope"))
        #expect(result.content.contains("itemscope=\"itemscope\"") == false)
    }

    @Test func xmlSerializerDoesNotForceXMLForHTMLInput() throws {
        let html = """
        <html>
          <body>
            <article id="target" itemscope="itemscope" itemtype="https://schema.org/Article">
              <p>hello there hello there hello there hello there hello there.</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0, useXMLSerializer: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("itemscope"))
        #expect(result.content.contains("itemscope=\"itemscope\"") == false)
    }

    @Test func disableJSONLDSkipsStructuredData() throws {
        let html = """
        <html>
          <head>
            <meta property="og:title" content="OG Title" />
            <script type="application/ld+json">
              {"@context":"https://schema.org","@type":"NewsArticle","headline":"JSONLD Title"}
            </script>
          </head>
          <body>
            <p>hello there hello there hello there hello there hello there.</p>
          </body>
        </html>
        """

        let readerDefault = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        )
        let resultDefault = try readerDefault.parse()
        #expect(resultDefault?.title == "JSONLD Title")

        let readerDisabled = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0, disableJSONLD: true)
        )
        let resultDisabled = try readerDisabled.parse()
        #expect(resultDisabled?.title == "OG Title")
    }

    @Test func classesToPreserveAreKeptWhenStripping() throws {
        let html = """
        <html>
          <body>
            <article>
              <p class="keepme dropme">hello there hello there hello there hello there hello there.</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0, classesToPreserve: ["keepme"])
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("keepme"))
        #expect(result.content.contains("dropme") == false)
    }

    @Test func keepClassesKeepsAllClasses() throws {
        let html = """
        <html>
          <body>
            <article>
              <p class="keepme dropme">hello there hello there hello there hello there hello there.</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0, classesToPreserve: ["keepme"], keepClasses: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("keepme"))
        #expect(result.content.contains("dropme"))
    }

    @Test func xmlSerializerDoesNotPromoteHTMLBooleanAttributeValues() throws {
        let html = """
        <html>
          <body>
            <article id="target" itemscope="itemscope" itemtype="https://schema.org/Article">
              <p>hello there hello there hello there hello there hello there.</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0, useXMLSerializer: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("itemscope"))
        #expect(result.content.contains("itemscope=\"itemscope\"") == false)
    }

    @Test func maxElemsToParseAppliesToDocumentPipeline() throws {
        let html = "<html><head><title>Yo</title></head><body><div>yo</div><span>hi</span></body></html>"
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let reader = Readability(document: doc, options: ReadabilityOptions(maxElemsToParse: 1))
        do {
            _ = try reader.parse()
            #expect(false, "Expected parse() to throw when exceeding maxElemsToParse")
        } catch {
            #expect(error.localizedDescription.contains("Aborting parsing document;"))
        }
    }

    @Test func baseUriResolvesRelativeLinks() throws {
        let html = """
        <html>
          <head>
            <base href="https://example.com/base/" />
          </head>
          <body>
            <article>
              <p>hello there hello there hello there hello there hello there.</p>
              <a href="page.html">Link</a>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: URL(string: "https://example.com/root/index.html")!,
            options: ReadabilityOptions(charThreshold: 0)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("https://example.com/base/page.html"))
    }

    @Test func baseUriResolvesRelativeImages() throws {
        let html = """
        <html>
          <head>
            <base href="https://example.com/base/" />
          </head>
          <body>
            <article>
              <p>hello there hello there hello there hello there hello there.</p>
              <img src="img.png" />
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: URL(string: "https://example.com/root/index.html")!,
            options: ReadabilityOptions(charThreshold: 0)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("https://example.com/base/img.png"))
    }

}
