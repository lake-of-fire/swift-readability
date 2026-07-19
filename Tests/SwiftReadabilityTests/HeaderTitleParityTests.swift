import Foundation
import Testing
@testable import SwiftReadability

struct HeaderTitleParityTests {
    @Test func nonASCIIOnlyTitleIsRetainedLikeMozilla() throws {
        let fixture = try FixtureRepository.packageResources.load(named: "asahi-article-title-byline")
        let result = try Readability(html: fixture.source, url: fixture.url).parse()

        #expect(result?.textContent.hasPrefix("ランクルをバラバラに　コンテナ密輸、手口が巧妙化　迫る税関と警察") == true)
    }

    @Test func titleWithMatchingASCIIAnchorIsRemovedLikeMozilla() throws {
        let fixture = try FixtureRepository.packageResources.load(named: "qq")
        let result = try Readability(html: fixture.source, url: fixture.url).parse()

        #expect(result?.textContent.hasPrefix("DeepMind新电脑已可利用记忆自学 人工智能迈上新台阶") == false)
        #expect(result?.textContent.hasPrefix("TNW中文站") == true)
    }
}
