import SwiftSoup
import Testing
@testable import SwiftReadability

@Suite("Explicit non-Mozilla extensions")
struct ReadabilityExtensionsTests {
    @Test("Mozilla mode is the default")
    func defaultOptionsContainNoExtensions() {
        #expect(ReadabilityOptions().extensions.isEmpty)
        #expect(ReadabilityExtensions.publisherAdaptations.contains(.imageCarouselRecovery))
        #expect(ReadabilityExtensions.publisherAdaptations.contains(.publisherChromeCleanup))
        #expect(ReadabilityExtensions.publisherAdaptations.contains(.articleBodyPreservation))
        #expect(ReadabilityExtensions.publisherAdaptations.contains(.significantMediaPreservation))
        #expect(ReadabilityExtensions.publisherAdaptations.contains(.rubyNormalization))
    }

    @Test("Publisher patterns cannot alter Mozilla mode implicitly")
    func publisherPatternsAreOptIn() {
        let mozilla = RegExUtil(options: ReadabilityOptions())
        let enhanced = RegExUtil(
            options: ReadabilityOptions(extensions: [.publisherChromeCleanup])
        )

        #expect(!mozilla.isUnlikelyCandidate("notprint"))
        #expect(!mozilla.isNegative("admod"))
        #expect(enhanced.isUnlikelyCandidate("notprint"))
        #expect(enhanced.isNegative("admod"))
    }

    @Test("Ruby normalization is opt in")
    func rubyNormalizationIsOptIn() throws {
        let source = "<html><body><p><ruby><rb>東京</rb><rp>(</rp><rt>とうきょう</rt><rp>)</rp></ruby></p></body></html>"
        let mozillaDocument = try SwiftSoup.parse(source)
        let enhancedDocument = try SwiftSoup.parse(source)

        Preprocessor().prepareDocument(mozillaDocument)
        Preprocessor(extensions: [.rubyNormalization]).prepareDocument(enhancedDocument)

        #expect(try mozillaDocument.select("rb").count == 1)
        #expect(try mozillaDocument.select("rp").count == 2)
        #expect(try enhancedDocument.select("rb").isEmpty())
        #expect(try enhancedDocument.select("rp").isEmpty())
        #expect(try enhancedDocument.select("rt").text() == "とうきょう")
    }
}
