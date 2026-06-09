import Testing
import Foundation
import SwiftSoup
@testable import SwiftReadability

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}

@Test func rubyInsideInlineFormattingSurvivesExtraction() async throws {
    let html = #"""
    <html>
    <body>
    <article>
    <p><ruby><rb>東京</rb><rp>(</rp><rt>とうきょう</rt><rp>)</rp></ruby>を　<ruby><rb>旅行</rb><rp>(</rp><rt>りょこう</rt><rp>)</rp></ruby>するときに　よく　<ruby><rb>使</rb><rp>(</rp><rt>つか</rt><rp>)</rp></ruby>う「<b>JR<ruby><rb>渋谷</rb><rp>(</rp><rt>しぶや</rt><rp>)</rp></ruby><ruby><rb>駅</rb><rp>(</rp><rt>えき</rt><rp>)</rp></ruby></b>」から、よく　<ruby><rb>使</rb><rp>(</rp><rt>つか</rt><rp>)</rp></ruby>われる　<ruby><rb>改札</rb><rp>(</rp><rt>かいさつ</rt><rp>)</rp></ruby>までの　<ruby><rb>行</rb><rp>(</rp><rt>い</rt><rp>)</rp></ruby>き<ruby><rb>方</rb><rp>(</rp><rt>かた</rt><rp>)</rp></ruby>を　<ruby><rb>紹介</rb><rp>(</rp><rt>しょうかい</rt><rp>)</rp></ruby>します。</p>
    </article>
    </body>
    </html>
    """#
    let expectedText = "東京を　旅行するときに　よく　使う「JR渋谷駅」から、よく　使われる　改札までの　行き方を　紹介します。"

    let reader = Readability(
        html: html,
        url: URL(string: "https://matcha-jp.com/easy/1166")!,
        options: ReadabilityOptions(charThreshold: 1)
    )
    let result = try #require(try reader.parse())

    let document = try SwiftSoup.parseBodyFragment(result.content)
    try document.select("rt, rp").remove()
    let actualText = try document.text(trimAndNormaliseWhitespace: false)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(actualText == expectedText)

    let ruby = try SwiftSoup.parseBodyFragment(result.content).select("ruby").array()
    #expect(try ruby.contains { try $0.text(trimAndNormaliseWhitespace: false).contains("渋谷") && $0.select("rt").text() == "しぶや" })
    #expect(try ruby.contains { try $0.text(trimAndNormaliseWhitespace: false).contains("駅") && $0.select("rt").text() == "えき" })
}
