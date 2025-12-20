import SwiftSoup
import Testing
@testable import SwiftReadability

struct ReaderableTests {
    private func makeDoc(_ html: String) throws -> Document {
        try SwiftSoup.parse(html)
    }

    @Test func readerableFixtures() throws {
        for fixture in loadFixtures() {
            guard let expected = fixture.expectedMetadata?.readerable else { continue }
            let doc = try SwiftSoup.parse(fixture.source, fixture.url.absoluteString)
            let actual = Readability.isProbablyReaderable(html: fixture.source)
            #expect(actual == expected, "Fixture \(fixture.name) readerable mismatch")
        }
    }

    @Test func readerableThresholds() throws {
        let verySmall = try makeDoc("<html><p id='main'>hello there</p></html>")
        let small = try makeDoc("<html><p id='main'>\(String(repeating: "hello there ", count: 11))</p></html>")
        let large = try makeDoc("<html><p id='main'>\(String(repeating: "hello there ", count: 12))</p></html>")
        let veryLarge = try makeDoc("<html><p id='main'>\(String(repeating: "hello there ", count: 50))</p></html>")

        #expect(Readability.isProbablyReaderable(doc: verySmall) == false)
        #expect(Readability.isProbablyReaderable(doc: small) == false)
        #expect(Readability.isProbablyReaderable(doc: large) == false)
        #expect(Readability.isProbablyReaderable(doc: veryLarge) == true)

        let lowerMinContent = Readability.ReaderableOptions(minContentLength: 120, minScore: 0)
        #expect(Readability.isProbablyReaderable(doc: verySmall, options: lowerMinContent) == false)
        #expect(Readability.isProbablyReaderable(doc: small, options: lowerMinContent) == true)
        #expect(Readability.isProbablyReaderable(doc: large, options: lowerMinContent) == true)
        #expect(Readability.isProbablyReaderable(doc: veryLarge, options: lowerMinContent) == true)

        let higherMinContent = Readability.ReaderableOptions(minContentLength: 200, minScore: 0)
        #expect(Readability.isProbablyReaderable(doc: verySmall, options: higherMinContent) == false)
        #expect(Readability.isProbablyReaderable(doc: small, options: higherMinContent) == false)
        #expect(Readability.isProbablyReaderable(doc: large, options: higherMinContent) == false)
        #expect(Readability.isProbablyReaderable(doc: veryLarge, options: higherMinContent) == true)

        let lowerMinScore = Readability.ReaderableOptions(minContentLength: 0, minScore: 4)
        #expect(Readability.isProbablyReaderable(doc: verySmall, options: lowerMinScore) == false)
        #expect(Readability.isProbablyReaderable(doc: small, options: lowerMinScore) == true)
        #expect(Readability.isProbablyReaderable(doc: large, options: lowerMinScore) == true)
        #expect(Readability.isProbablyReaderable(doc: veryLarge, options: lowerMinScore) == true)

        let higherMinScore = Readability.ReaderableOptions(minContentLength: 0, minScore: 11.5)
        #expect(Readability.isProbablyReaderable(doc: verySmall, options: higherMinScore) == false)
        #expect(Readability.isProbablyReaderable(doc: small, options: higherMinScore) == false)
        #expect(Readability.isProbablyReaderable(doc: large, options: higherMinScore) == true)
        #expect(Readability.isProbablyReaderable(doc: veryLarge, options: higherMinScore) == true)
    }

    @Test func readerableVisibilityCheckerOptions() throws {
        let doc = try makeDoc("<html><p id='main'>\(String(repeating: "hello there ", count: 50))</p></html>")
        var called = false
        let options = Readability.ReaderableOptions(visibilityChecker: { _ in
            called = true
            return false
        })
        #expect(Readability.isProbablyReaderable(doc: doc, options: options) == false)
        #expect(called == true)

        called = false
        let optionsVisible = Readability.ReaderableOptions(visibilityChecker: { _ in
            called = true
            return true
        })
        #expect(Readability.isProbablyReaderable(doc: doc, options: optionsVisible) == true)
        #expect(called == true)
    }

    @Test func readerableVisibilityCheckerParameter() throws {
        let doc = try makeDoc("<html><p id='main'>\(String(repeating: "hello there ", count: 50))</p></html>")
        var called = false
        #expect(Readability.isProbablyReaderable(doc: doc, visibilityChecker: { _ in
            called = true
            return false
        }) == false)
        #expect(called == true)

        called = false
        #expect(Readability.isProbablyReaderable(doc: doc, visibilityChecker: { _ in
            called = true
            return true
        }) == true)
        #expect(called == true)
    }

    @Test func readerableDocumentOverloads() throws {
        let doc = try makeDoc("<html><p id='main'>\(String(repeating: "hello there ", count: 50))</p></html>")
        #expect(Readability.isProbablyReaderable(document: doc) == true)
        let options = Readability.ReaderableOptions(minContentLength: 1000, minScore: 0)
        #expect(Readability.isProbablyReaderable(document: doc, options: options) == false)
    }
}

private extension Readability {
    static func isProbablyReaderable(doc: Document) -> Bool {
        isProbablyReaderable(doc: doc, options: ReaderableOptions())
    }

    static func isProbablyReaderable(doc: Document, options: ReaderableOptions) -> Bool {
        isProbablyReaderable(doc: doc, options: options, visibilityChecker: options.visibilityChecker)
    }

    static func isProbablyReaderable(doc: Document, visibilityChecker: @escaping (Element) -> Bool) -> Bool {
        isProbablyReaderable(doc: doc, options: ReaderableOptions(), visibilityChecker: visibilityChecker)
    }
}
