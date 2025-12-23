import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct ParitySupplementaryTests {
    private let baseURL = URL(string: "http://example.com")!

    @Test func documentPipelineMutatesOriginalDOM() throws {
        let html = "<html><head><script>console.log('x')</script></head><body><p>Hello world</p></body></html>"
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let reader = Readability(document: doc)
        _ = try reader.parse()
        let scripts = try doc.select("script")
        #expect(scripts.count == 0)
    }

    @Test func documentPipelineReflectsMutations() throws {
        let html = "<html><body><article><p id='target'>old</p></article></body></html>"
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        try doc.select("#target").first()?.text("new")
        let reader = Readability(document: doc, options: ReadabilityOptions(charThreshold: 1))
        let result = try reader.parse()
        #expect(result?.content.contains("new") == true)
    }

    @Test func xmlSerializerOptionProducesXMLSyntax() throws {
        let html = "<html><body><p>hello there hello there hello there hello there hello there hello there hello there hello there hello there hello there</p><p><img src=\"\"></p></body></html>"
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20, useXMLSerializer: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("<img"))
        #expect(result.content.contains("/>"))
    }

    @Test func htmlSerializerDefaultUsesHtmlBooleanSyntax() throws {
        let html = """
        <html>
          <body>
            <article id="target" itemscope="itemscope" itemtype="https://schema.org/Article">
              <p>hello there hello there hello there hello there hello there</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("itemscope"))
        #expect(result.content.contains("itemscope=\"itemscope\""))
    }

    @Test func xmlSerializerDefaultPreservesExplicitBooleanValues() throws {
        let html = """
        <html>
          <body>
            <article id="target" itemscope="itemscope" itemtype="https://schema.org/Article">
              <p>hello there hello there hello there hello there hello there</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20, useXMLSerializer: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("itemscope=\"itemscope\""))
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
            <p>hello there hello there hello there hello there hello there</p>
          </body>
        </html>
        """

        let readerDefault = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20)
        )
        let resultDefault = try readerDefault.parse()
        #expect(resultDefault?.title == "JSONLD Title")

        let readerDisabled = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20, disableJSONLD: true)
        )
        let resultDisabled = try readerDisabled.parse()
        #expect(resultDisabled?.title == "OG Title")
    }

    @Test func classesToPreserveAreKeptWhenStripping() throws {
        let html = """
        <html>
          <body>
            <article>
              <p class="keepme dropme">hello there hello there hello there hello there hello there</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20, classesToPreserve: ["keepme"])
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
              <p class="keepme dropme">hello there hello there hello there hello there hello there</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20, classesToPreserve: ["keepme"], keepClasses: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("keepme"))
        #expect(result.content.contains("dropme"))
    }

    @Test func xmlSerializerPromotesExplicitBooleanAttributeValues() throws {
        let html = """
        <html>
          <body>
            <article id="target" itemscope="itemscope" itemtype="https://schema.org/Article">
              <p>hello there hello there hello there hello there hello there</p>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 20, useXMLSerializer: true)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("itemscope=\"itemscope\""))
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
              <p>hello there hello there hello there hello there hello there</p>
              <a href="page.html">Link</a>
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: URL(string: "https://example.com/root/index.html")!,
            options: ReadabilityOptions(charThreshold: 20)
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
              <p>hello there hello there hello there hello there hello there</p>
              <img src="img.png" />
            </article>
          </body>
        </html>
        """
        let reader = Readability(
            html: html,
            url: URL(string: "https://example.com/root/index.html")!,
            options: ReadabilityOptions(charThreshold: 20)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("https://example.com/base/img.png"))
    }

}
