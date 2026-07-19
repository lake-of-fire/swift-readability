import SwiftSoup
import Testing
@testable import SwiftReadability

struct MetadataParserTests {
    @Test func unicodeBeforeMatchedMetaPropertyDoesNotCrash() throws {
        let document = try SwiftSoup.parse(
            #"<html><head><meta property="😀 og:title" content="Unicode-safe title"></head></html>"#
        )

        let metadata = MetadataParser().getArticleMetadata(document, disableJSONLD: true)

        #expect(metadata.title == "Unicode-safe title")
    }
}
