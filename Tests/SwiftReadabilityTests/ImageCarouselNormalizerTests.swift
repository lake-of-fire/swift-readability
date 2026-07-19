import SwiftSoup
import Testing
@testable import SwiftReadability

struct ImageCarouselNormalizerTests {
    @Test func imageDominantCarouselBecomesSemanticFigures() throws {
        let document = try SwiftSoup.parse("""
        <div class="swiper gallery">
          <figure><img data-src="first.jpg" alt="First"><figcaption>First caption</figcaption></figure>
          <figure><img srcset="second.webp 2x"><figcaption>Second caption</figcaption></figure>
        </div>
        """)

        ImageCarouselNormalizer(regEx: RegExUtil()).normalize(document)

        let carousel = try #require(document.select("[data-readability-carousel=true]").first())
        #expect(try carousel.select("figure[data-readability-carousel-slide]").count == 2)
        #expect(try carousel.select("img").map { try $0.attr("src") } == ["first.jpg", "second.webp"])
        #expect(try carousel.select("figcaption").text().contains("First caption"))
    }

    @Test func contentHeavySectionIsNotRewrittenAsACarousel() throws {
        let substantialText = String(repeating: "Substantive article prose. ", count: 90)
        let document = try SwiftSoup.parse("""
        <section class="carousel">
          <img src="first.jpg"><img src="second.jpg">
          <p>\(substantialText)</p>
        </section>
        """)

        ImageCarouselNormalizer(regEx: RegExUtil()).normalize(document)

        #expect(try document.select("[data-readability-carousel]").isEmpty())
        #expect(try document.select("section.carousel").count == 1)
    }

    @Test func duplicateImageSourcesDoNotCreateAFakeGallery() throws {
        let document = try SwiftSoup.parse("""
        <div class="slider">
          <img src="same.jpg"><img data-src="same.jpg">
        </div>
        """)

        ImageCarouselNormalizer(regEx: RegExUtil()).normalize(document)

        #expect(try document.select("[data-readability-carousel]").isEmpty())
    }
}
