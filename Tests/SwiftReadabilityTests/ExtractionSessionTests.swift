import Foundation
import SwiftSoup
import Testing
@_spi(Bench) @testable import SwiftReadability

struct ExtractionSessionTests {
    private let baseURL = URL(string: "https://example.com/article")!

    @Test func htmlBackedReaderProducesStableResultsAcrossRepeatedParses() throws {
        let reader = Readability(
            html: articleHTML(byline: "Stable Author", direction: "rtl"),
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        )

        let first = try #require(try reader.parse())
        let second = try #require(try reader.parse())

        #expect(first.title == second.title)
        #expect(first.byline == second.byline)
        #expect(first.dir == second.dir)
        #expect(first.content == second.content)
        #expect(first.textContent == second.textContent)
        #expect(first.length == second.length)
    }

    @Test func articleGrabberDoesNotLeakBylineOrDirectionBetweenDocuments() throws {
        let grabber = ArticleGrabber(options: ReadabilityOptions(charThreshold: 0))
        let firstDocument = try SwiftSoup.parse(articleHTML(byline: "First Author", direction: "rtl"), baseURL.absoluteString)
        let secondDocument = try SwiftSoup.parse(articleHTML(byline: nil, direction: nil), baseURL.absoluteString)

        _ = try #require(grabber.grabArticle(doc: firstDocument, metadata: ArticleMetadata()))
        #expect(grabber.articleByline == "First Author")
        #expect(grabber.articleDir == "rtl")

        _ = try #require(grabber.grabArticle(doc: secondDocument, metadata: ArticleMetadata()))
        #expect(grabber.articleByline == nil)
        #expect(grabber.articleDir == nil)
    }

    @Test func timedAndUntimedPipelinesReturnTheSameArticle() throws {
        let reader = Readability(
            html: articleHTML(byline: "Timing Author", direction: "ltr"),
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 0)
        )

        let untimed = try #require(try reader.parse())
        let timedPair = try reader.parseWithTimings()
        let timed = try #require(timedPair.0)

        #expect(timed.title == untimed.title)
        #expect(timed.byline == untimed.byline)
        #expect(timed.dir == untimed.dir)
        #expect(timed.lang == untimed.lang)
        #expect(timed.excerpt == untimed.excerpt)
        #expect(timed.siteName == untimed.siteName)
        #expect(timed.publishedTime == untimed.publishedTime)
        #expect(timed.content == untimed.content)
        #expect(timed.textContent == untimed.textContent)
        #expect(timed.length == untimed.length)
        #expect(timed.readerable == untimed.readerable)

        let requiredTimingLabels: Set<String> = [
            "parseDocument", "readerable", "metadata", "preprocess",
            "grabArticle", "postprocess", "lang", "textContent", "serialize",
        ]
        #expect(requiredTimingLabels.isSubset(of: Set(timedPair.1.milliseconds.keys)))
    }

    private func articleHTML(byline: String?, direction: String?) -> String {
        let bylineHTML = byline.map { #"<p class="byline">\#($0)</p>"# } ?? ""
        let directionAttribute = direction.map { #" dir="\#($0)""# } ?? ""
        return """
        <html><head><title>Session isolation</title></head><body>
          <article\(directionAttribute)>
            \(bylineHTML)
            <p>This deliberately substantial paragraph gives the extractor enough readable prose to select the article consistently across every invocation.</p>
          </article>
        </body></html>
        """
    }
}
