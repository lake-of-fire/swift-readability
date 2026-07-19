import Foundation
import SwiftReadabilityJavaScriptReference
import Testing

struct JavaScriptReferenceResourceTests {
    @Test func optionalReferenceProductLoadsBothPinnedSources() throws {
        let readability = try ReadabilityJavaScriptResource.source()
        let readerable = try ReadabilityJavaScriptResource.readerableSource()

        #expect(readability.contains("function Readability"))
        #expect(readability.contains("module.exports = Readability"))
        #expect(readerable.contains("function isProbablyReaderable"))
    }
}
