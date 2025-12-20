import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct ReadabilityAPITests {
    private let baseURL = URL(string: "http://example.com")!

    @Test func constructorOptions() throws {
        let html = "<html><body><div>yo</div></body></html>"

        let defaultReader = Readability(html: html, url: baseURL)
        #expect(defaultReader.debugEnabled == false)
        #expect(defaultReader.nbTopCandidates == ReadabilityOptions.defaultNTopCandidates)
        #expect(defaultReader.maxElemsToParse == ReadabilityOptions.defaultMaxElemsToParse)
        #expect(defaultReader.keepClasses == false)
        #expect(defaultReader.allowedVideoRegex.pattern == RegExUtil.videosDefaultPattern)

        let customRegex = try NSRegularExpression(pattern: "//mydomain.com/.*'", options: [])
        let configuredReader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(
                debug: true,
                maxElemsToParse: 42,
                nbTopCandidates: 42,
                keepClasses: true,
                allowedVideoRegex: customRegex
            )
        )

        #expect(configuredReader.debugEnabled == true)
        #expect(configuredReader.nbTopCandidates == 42)
        #expect(configuredReader.maxElemsToParse == 42)
        #expect(configuredReader.keepClasses == true)
        #expect(configuredReader.allowedVideoRegex.pattern == customRegex.pattern)
    }

    @Test func parseRejectsOversizedDocuments() throws {
        let html = "<html><head><title>Yo</title></head><body><div>yo</div><span>hi</span></body></html>"
        let doc = try SwiftSoup.parse(html, baseURL.absoluteString)
        let numTags = (try? doc.getAllElements().count) ?? 0
        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(maxElemsToParse: 1)
        )

        do {
            _ = try reader.parse()
            #expect(false, "Expected parse() to throw when exceeding maxElemsToParse")
        } catch {
            #expect(error.localizedDescription == "Aborting parsing document; \(numTags) elements found")
        }
    }

    @Test func keepClassesOptionControlsClassStripping() throws {
        let html = "<html><body><div><p class='keep'>Hello</p></div></body></html>"

        let defaultReader = Readability(html: html, url: baseURL)
        guard let defaultResult = try defaultReader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        let defaultDoc = try SwiftSoup.parseBodyFragment(defaultResult.content)
        let defaultClass = try defaultDoc.select("p").first()?.className() ?? ""
        #expect(defaultClass.isEmpty)

        let keepReader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(keepClasses: true)
        )
        guard let keepResult = try keepReader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        let keepDoc = try SwiftSoup.parseBodyFragment(keepResult.content)
        let keepClass = try keepDoc.select("p").first()?.className() ?? ""
        #expect(keepClass == "keep")
    }

    @Test func customSerializerIsUsed() throws {
        let html = "My cat: <img src=''>"
        let expectedXHTML =
        "<div xmlns=\"http://www.w3.org/1999/xhtml\" id=\"readability-page-1\" class=\"page\">My cat: <img src=\"\" /></div>"

        let serializer: ReadabilityOptions.Serializer = { element in
            guard let page = try? element.child(0) else { return "" }
            let inner = (try? page.html()) ?? ""
            let normalizedInner = inner
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .replacingOccurrences(of: "<img src=\"\"></img>", with: "<img src=\"\" />")
                .replacingOccurrences(of: "<img src=\"\">", with: "<img src=\"\" />")
            let idValue = page.idSafe()
            let classValue = page.classNameSafe()
            return "<div xmlns=\"http://www.w3.org/1999/xhtml\" id=\"\(idValue)\" class=\"\(classValue)\">\(normalizedInner)</div>"
        }

        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(serializer: serializer)
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content == expectedXHTML)
    }

    @Test func customAllowedVideoRegexIsRespected() throws {
        let html =
        "<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nunc mollis leo lacus, vitae semper nisl ullamcorper ut.</p>" +
        "<iframe src=\"https://mycustomdomain.com/some-embeds\"></iframe>"

        let reader = Readability(
            html: html,
            url: baseURL,
            options: ReadabilityOptions(
                charThreshold: 20,
                allowedVideoRegex: try NSRegularExpression(pattern: ".*mycustomdomain.com.*", options: [])
            )
        )
        guard let result = try reader.parse() else {
            #expect(false, "Expected parse() to return a result")
            return
        }
        #expect(result.content.contains("iframe"))
        #expect(result.content.contains("mycustomdomain.com"))
    }

    @Test func initWithDocumentUsesDocumentHTML() throws {
        let doc = try SwiftSoup.parse("<html><body><div>yo</div></body></html>", baseURL.absoluteString)
        let reader = Readability(document: doc)
        let result = try reader.parse()
        #expect(result != nil)
    }

    @Test func parseWithSerializerReturnsCustomContent() throws {
        let reader = Readability(
            html: "<html><body><div id='x'>yo</div></body></html>",
            url: baseURL
        )
        let result = try reader.parse { element in
            (try? element.select("#readability-page-1").first()?.tagNameSafe()) ?? ""
        }
        #expect(result?.content == "div")
    }
}
