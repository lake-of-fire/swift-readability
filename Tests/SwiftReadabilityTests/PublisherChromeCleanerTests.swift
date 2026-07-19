import Foundation
import SwiftSoup
import Testing

@testable import SwiftReadability

@Suite("Publisher chrome cleaner")
struct PublisherChromeCleanerTests {
  private let baseURL = URL(string: "https://example.com/article")!

  @Test("Removes compact publisher controls without removing editorial content")
  func removesOnlyQualifiedChrome() throws {
    let document = try SwiftSoup.parse(
      """
      <html><body><div id="article">
        <ul id="actions" data-content-type="Article">
          <li x-component-name="share-dialog">Share on Twitter</li>
        </ul>
        <ul id="editorial-list">
          <li>First editorial point</li><li>Second editorial point</li>
        </ul>
        <p id="promotion">[PR]</p>
        <p id="body">This is the substantive article body and it must remain available to the reader.</p>
      </div></body></html>
      """,
      baseURL.absoluteString
    )
    let article = try #require(document.select("#article").first())

    makeCleaner().clean(
      articleContent: article,
      articleTitle: nil,
      creatorNames: [],
      titleMatcher: { _, _ in false },
      linkDensity: { _, _ in 0 }
    )

    #expect(try article.select("#actions").isEmpty())
    #expect(try article.select("#promotion").isEmpty())
    #expect(try article.select("#editorial-list").count == 1)
    #expect(try article.select("#body").count == 1)
  }

  @Test("Creator cleanup requires compact semantic metadata")
  func creatorCleanupUsesSemanticSignals() throws {
    let bodyText = String(repeating: "Substantive article sentence. ", count: 20)
    let document = try SwiftSoup.parse(
      """
      <html><body><div id="article">
        <div id="metadata"><time datetime="2026-07-19">July 19</time> Alice Example</div>
        <div id="biography">Alice Example writes about science and technology.</div>
        <p id="body">\(bodyText)</p>
      </div></body></html>
      """,
      baseURL.absoluteString
    )
    let article = try #require(document.select("#article").first())

    makeCleaner().clean(
      articleContent: article,
      articleTitle: nil,
      creatorNames: ["Alice Example"],
      titleMatcher: { _, _ in false },
      linkDensity: { _, _ in 0 }
    )

    #expect(try article.select("#metadata").isEmpty())
    #expect(try article.select("#biography").count == 1)
    #expect(try article.select("#body").count == 1)
  }

  @Test("Publisher cleanup remains explicitly opt in")
  func integrationGateLeavesMozillaModeUntouched() throws {
    let bodyText = String(
      repeating: "A complete article sentence with enough detail for extraction. ", count: 20)
    let html = """
      <html><head><title>Example article</title></head><body>
        <article><p>[PR]</p><p>\(bodyText)</p></article>
      </body></html>
      """

    let mozillaResult = try Readability(
      html: html,
      url: baseURL,
      options: ReadabilityOptions(charThreshold: 0)
    ).parse()
    let extendedResult = try Readability(
      html: html,
      url: baseURL,
      options: ReadabilityOptions(charThreshold: 0, extensions: [.publisherChromeCleanup])
    ).parse()

    #expect(mozillaResult?.textContent.contains("[PR]") == true)
    #expect(extendedResult?.textContent.contains("[PR]") == false)
    #expect(extendedResult?.textContent.contains("A complete article sentence") == true)
  }

  private func makeCleaner() -> PublisherChromeCleaner {
    PublisherChromeCleaner(
      regEx: RegExUtil(
        options: ReadabilityOptions(extensions: [.publisherChromeCleanup])
      )
    )
  }
}
