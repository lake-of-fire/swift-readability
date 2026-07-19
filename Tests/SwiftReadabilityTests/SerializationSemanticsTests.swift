import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct SerializationSemanticsTests {
    private let baseURL = URL(string: "https://example.com/article")!

    @Test(arguments: ["itemscope", "ITEMSCOPE"])
    func htmlSerializationPreservesCanonicalBooleanValues(_ value: String) throws {
        let prose = String(repeating: "Browser serialization preserves source attribute values. ", count: 30)
        let html = """
        <!doctype html>
        <html><body>
          <article itemscope="\(value)" itemtype="https://schema.org/Article">
            <p>\(prose)</p>
          </article>
        </body></html>
        """

        let result = try Readability(html: html, url: baseURL).parse()

        #expect(result?.content.contains("itemscope=\"\(value)\"") == true)
    }

    @Test func htmlSerializationUsesBrowserVoidElementSyntax() throws {
        let prose = String(repeating: "Browser HTML serialization remains directly observable. ", count: 20)
        let html = "<article><p>\(prose)<br>Tail.</p></article>"

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1)
        ).parse())

        #expect(result.content.contains("<br>Tail."))
        #expect(!result.content.contains("<br />"))
    }

    @Test func htmlSerializationUsesBrowserEmptyAttributeAndEntitySpelling() throws {
        let prose = String(repeating: "Browser HTML serialization preserves the public string contract. ", count: 20)
        let html = "<article itemscope><p>\(prose)non\u{00A0}breaking.</p></article>"

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse())

        #expect(result.content.contains("itemscope=\"\""))
        #expect(result.content.contains("non&nbsp;breaking"))
    }

    @Test func htmlSerializationUsesBrowserSVGNameAdjustments() throws {
        let prose = String(repeating: "SVG name adjustment is part of browser HTML serialization. ", count: 20)
        let html = """
        <article><p>\(prose)</p><svg viewBox="0 0 10 10"><clipPath id="cut"><path d="M0 0"></path></clipPath></svg></article>
        """

        let result = try #require(try Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse())

        #expect(result.content.contains("viewBox=\"0 0 10 10\""))
        #expect(result.content.contains("<clipPath id=\"cut\">"))
    }

    @Test(arguments: ["\u{0085}", "\u{FEFF}", "\u{200B}"])
    func htmlSerializationPreservesUnicodeInsideBooleanValues(_ scalar: String) throws {
        let prose = String(repeating: "Attribute values remain observable DOM data. ", count: 35)
        let value = scalar + "itemscope" + scalar
        let html = """
        <article itemscope="\(value)" itemtype="https://schema.org/Article">
          <p>\(prose)</p>
        </article>
        """

        let result = try Readability(html: html, url: baseURL).parse()

        #expect(result?.content.contains("itemscope=\"\(value)\"") == true)
    }

    @Test func malformedHTMLIsRepairedWithoutRewritingBooleanValues() throws {
        let prose = String(repeating: "The HTML parser repairs this unclosed paragraph. ", count: 35)
        let html = "<article itemscope=\"itemscope\" itemtype=\"https://schema.org/Article\"><p>\(prose)"

        let result = try Readability(html: html, url: baseURL).parse()

        #expect(result?.content.contains("itemscope=\"itemscope\"") == true)
        #expect(result?.textContent.contains("The HTML parser repairs") == true)
    }

    @Test(arguments: ["\u{0085}", "\u{FEFF}", "\u{200B}"])
    func xmlRecoveryDoesNotTreatUnicodeCharactersAsXMLWhitespace(_ scalar: String) throws {
        let target = try xmlElement("<root><article id=\"target\" itemscope=\"\" /></root>")
        let reader = Readability(html: "", url: baseURL)
        let source = "<root><article id=\"target\" itemscope=\"\(scalar)itemscope\(scalar)\" /></root>"

        reader.normalizeBooleanAttributes(in: target, sourceXML: source)

        #expect(try target.attr("itemscope") == "")
    }

    @Test(arguments: ["\u{0085}", "\u{FEFF}", "\u{200B}"])
    func xmlRecoveryDoesNotTreatUnicodeCharactersAsAttributeSeparators(_ scalar: String) throws {
        let target = try xmlElement("<root><article id=\"target\" itemscope=\"\" /></root>")
        let reader = Readability(html: "", url: baseURL)
        let source = "<root><article id=\"target\" itemscope\(scalar)=\"itemscope\" /></root>"

        reader.normalizeBooleanAttributes(in: target, sourceXML: source)

        #expect(try target.attr("itemscope") == "")
    }

    @Test func xmlRecoveryAcceptsXMLWhitespaceAroundEquals() throws {
        let target = try xmlElement("<root><article id=\"target\" itemscope=\"\" /></root>")
        let reader = Readability(html: "", url: baseURL)
        let source = "<root><article id=\"target\" itemscope \n=\t \"ITEMSCOPE\" /></root>"

        reader.normalizeBooleanAttributes(in: target, sourceXML: source)

        #expect(try target.attr("itemscope") == "itemscope")
    }

    @Test func xmlRecoveryIgnoresElementMarkupInsideComments() throws {
        let target = try xmlElement("<root><article id=\"target\" itemscope=\"\" /></root>")
        let reader = Readability(html: "", url: baseURL)
        let source = "<root><!-- <article id=\"target\" itemscope=\"itemscope\" /> --></root>"

        reader.normalizeBooleanAttributes(in: target, sourceXML: source)

        #expect(try target.attr("itemscope") == "")
    }

    @Test func xmlSerializationPreservesCanonicalBooleanValues() throws {
        let document = try SwiftSoup.parse(
            "<root><article><figure id=\"target\" itemscope=\"itemscope\" /></article></root>",
            baseURL.absoluteString,
            Parser.xmlParser()
        )
        let article = try #require(document.select("article").first())
        let reader = Readability(document: document)

        let serialized = reader.serializeArticleContent(
            document: document,
            articleContent: article,
            useXMLSerializer: true,
            isLiveDocument: true
        )

        #expect(serialized.contains("itemscope=\"itemscope\""))
    }

    private func xmlElement(_ source: String) throws -> Element {
        let document = try SwiftSoup.parse(source, baseURL.absoluteString, Parser.xmlParser())
        return try #require(document.select("article").first())
    }
}
