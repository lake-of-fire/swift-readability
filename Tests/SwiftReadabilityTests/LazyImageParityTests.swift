import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct LazyImageParityTests {
    private let articleURL = URL(string: "https://example.com/articles/story")!

    @Test func lazyImagePatternsPreserveMozillaCaseAndWhitespaceSemantics() throws {
        let result = try #require(try extract("""
            <img id="lower" data-source="images/lower.jpg">
            <img id="upper" data-source="images/upper.JPG">
            <img id="feff" data-source="images/density.jpg\u{FEFF}2x">
            <img id="nel" data-source="images/density.jpg\u{0085}2x">
            """))
        let document = try SwiftSoup.parseBodyFragment(result.content)

        #expect(try document.select("#lower").attr("src") == "https://example.com/articles/images/lower.jpg")
        #expect(try document.select("#upper").hasAttr("src") == false)
        #expect(try document.select("#upper").attr("data-source") == "images/upper.JPG")
        #expect(try document.select("#feff").hasAttr("srcset"))
        #expect(try document.select("#feff").hasAttr("src") == false)
        #expect(try document.select("#nel").hasAttr("src"))
        #expect(try document.select("#nel").hasAttr("srcset") == false)
    }

    @Test func explicitlyEmptyImageSourceUsesTheDOMPropertyTruthiness() throws {
        let ordinary = try #require(try extract(
            #"<img id="empty" src="" data-source="images/replacement.jpg">"#
        ))
        let ordinaryDocument = try SwiftSoup.parseBodyFragment(ordinary.content)
        let ordinaryImage = try #require(try ordinaryDocument.select("#empty").first())

        #expect(ordinaryImage.hasAttr("src"))
        #expect(try ordinaryImage.attr("src").isEmpty)
        #expect(try ordinaryImage.attr("data-source") == "images/replacement.jpg")

        let blank = try #require(try Readability(
            html: articleHTML(
                #"<img id="empty" src="" data-source="https://cdn.example/replacement.jpg">"#
            ),
            url: URL(string: "about:blank")!,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse())
        let blankDocument = try SwiftSoup.parseBodyFragment(blank.content)
        #expect(try blankDocument.select("#empty").attr("src") == "https://cdn.example/replacement.jpg")
    }

    @Test func base64RecognitionRunsAfterDOMURLSerialization() throws {
        let result = try #require(try extract("""
            <img id="feff" src="data:\u{FEFF}image/png;\u{FEFF}base64,AAAA" data-source="images/real.jpg">
            <img id="nel" src="data:\u{0085}image/png;\u{0085}base64,AAAA" data-source="images/other.jpg">
            """))
        let document = try SwiftSoup.parseBodyFragment(result.content)

        #expect(
            try document.select("#feff").attr("src")
                == "data:%EF%BB%BFimage/png;%EF%BB%BFbase64,AAAA"
        )
        #expect(
            try document.select("#nel").attr("src")
                == "data:%C2%85image/png;%C2%85base64,AAAA"
        )
    }

    @Test func base64DetectionUsesTheResolvedImageSourceProperty() throws {
        let result = try #require(try extract(
            #"<img id="resolved" src="  data:image/png;base64,AAAA" data-source="images/real.jpg">"#
        ))
        let document = try SwiftSoup.parseBodyFragment(result.content)

        #expect(
            try document.select("#resolved").attr("src")
                == "https://example.com/articles/images/real.jpg"
        )
    }

    @Test func pictureSourcePropertiesRemainUndefinedLikeTheBrowserInterface() throws {
        let result = try #require(try extract("""
            <picture id="raw-src" src="images/already.jpg" data-source="images/lazy.jpg"></picture>
            <picture id="raw-srcset" srcset="images/already.jpg 1x" data-source="images/lazy.jpg"></picture>
            """))
        let document = try SwiftSoup.parseBodyFragment(result.content)

        #expect(
            try document.select("#raw-src").attr("src")
                == "https://example.com/articles/images/lazy.jpg"
        )
        #expect(
            try document.select("#raw-srcset").attr("src")
                == "https://example.com/articles/images/lazy.jpg"
        )
        #expect(
            try document.select("#raw-srcset").attr("srcset")
                == "https://example.com/articles/images/already.jpg 1x"
        )
    }

    private func extract(_ images: String) throws -> ReadabilityResult? {
        try Readability(
            html: articleHTML(images),
            url: articleURL,
            options: ReadabilityOptions(charThreshold: 1, keepClasses: true)
        ).parse()
    }

    private func articleHTML(_ images: String) -> String {
        """
        <html><body><article>
          <p>This article paragraph contains enough coherent editorial prose to establish a stable primary content candidate.</p>
          <figure>\(images)</figure>
          <p>A second paragraph keeps the surrounding article and its retained illustrative images unambiguous.</p>
        </article></body></html>
        """
    }
}
