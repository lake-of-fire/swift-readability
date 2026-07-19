// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import Foundation

/// Regex helper mirroring Readability.js REGEXPS.
final class RegExUtil {
    static let unlikelyCandidatesDefaultPattern = "-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote"

    static let unlikelyCandidatesPublisherCleanupPattern = "-ad-|ai2html|admod|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|notprint|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote"

    static let okMaybeItsACandidateDefaultPattern = "and|article|body|column|content|main|mathjax|shadow"

    static let positiveDefaultPattern = "article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story"

    static let negativeDefaultPattern = "-ad-|hidden|^hid$| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget"

    static let negativePublisherCleanupPattern = "-ad-|admod|hidden|^hid$| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|notprint|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget"

    static let bylineDefaultPattern = "byline|author|dateline|writtenby|p-author"

    static let normalizeDefaultPattern = "\\s{2,}"

    static let videosDefaultPattern = "//(www\\.)?((dailymotion|youtube|youtube-nocookie|player\\.vimeo|v\\.qq|bilibili|live\\.bilibili)\\.com|(archive|upload\\.wikimedia)\\.org|player\\.twitch\\.tv)"

    static let whitespaceDefaultPattern = "^\\s*$"

    static let hasContentDefaultPattern = "\\S$"

    private let unlikelyCandidates: NSRegularExpression
    private let okMaybeItsACandidate: NSRegularExpression
    private let positive: NSRegularExpression
    private let negative: NSRegularExpression
    private let byline: NSRegularExpression
    private let normalize: NSRegularExpression
    private let videos: NSRegularExpression
    private let whitespace: NSRegularExpression
    private let hasContent: NSRegularExpression
    private let videoUsesMozillaIgnoreCaseSemantics: Bool
    private let usesMozillaNormalizeSemantics: Bool
    private let usesMozillaWhitespaceSemantics: Bool
    private let usesMozillaHasContentSemantics: Bool

    convenience init(options: ReadabilityOptions) {
        let publisherCleanup = options.extensions.contains(.publisherChromeCleanup)
        self.init(
            unlikelyCandidatesPattern: publisherCleanup
                ? Self.unlikelyCandidatesPublisherCleanupPattern
                : Self.unlikelyCandidatesDefaultPattern,
            negativePattern: publisherCleanup
                ? Self.negativePublisherCleanupPattern
                : Self.negativeDefaultPattern,
            allowedVideoRegex: options.allowedVideoRegex
        )
    }

    init(unlikelyCandidatesPattern: String = unlikelyCandidatesDefaultPattern,
         okMaybeItsACandidatePattern: String = okMaybeItsACandidateDefaultPattern,
         positivePattern: String = positiveDefaultPattern,
         negativePattern: String = negativeDefaultPattern,
         bylinePattern: String = bylineDefaultPattern,
         normalizePattern: String = normalizeDefaultPattern,
         videosPattern: String = videosDefaultPattern,
         allowedVideoRegex: NSRegularExpression? = nil,
         whitespacePattern: String = whitespaceDefaultPattern,
         hasContentPattern: String = hasContentDefaultPattern) {
        func re(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
            return try! NSRegularExpression(pattern: pattern, options: options)
        }
        unlikelyCandidates = re(unlikelyCandidatesPattern)
        okMaybeItsACandidate = re(okMaybeItsACandidatePattern)
        positive = re(positivePattern)
        negative = re(negativePattern)
        byline = re(bylinePattern)
        normalize = re(normalizePattern, options: [])
        videos = allowedVideoRegex ?? re(videosPattern)
        videoUsesMozillaIgnoreCaseSemantics = allowedVideoRegex == nil
        whitespace = re(whitespacePattern, options: [])
        hasContent = re(hasContentPattern, options: [])
        usesMozillaNormalizeSemantics = normalizePattern == Self.normalizeDefaultPattern
        usesMozillaWhitespaceSemantics = whitespacePattern == Self.whitespaceDefaultPattern
        usesMozillaHasContentSemantics = hasContentPattern == Self.hasContentDefaultPattern
    }

    private func matches(
        _ regex: NSRegularExpression,
        in string: String,
        legacyIgnoreCase: Bool = true
    ) -> Bool {
        let regexInput = legacyIgnoreCase
            ? javaScriptLegacyIgnoreCaseRegexInput(string)
            : string
        return regex.firstMatch(
            in: regexInput,
            options: [],
            range: NSRange(location: 0, length: regexInput.utf16.count)
        ) != nil
    }

    func isPositive(_ s: String) -> Bool { matches(positive, in: s) }
    func isNegative(_ s: String) -> Bool { matches(negative, in: s) }
    func isUnlikelyCandidate(_ s: String) -> Bool { matches(unlikelyCandidates, in: s) }
    func okMaybeItsACandidate(_ s: String) -> Bool { matches(okMaybeItsACandidate, in: s) }
    func isByline(_ s: String) -> Bool { matches(byline, in: s) }
    func hasContent(_ s: String) -> Bool {
        usesMozillaHasContentSemantics
            ? javaScriptHasTrailingNonWhitespace(s)
            : matches(hasContent, in: s, legacyIgnoreCase: false)
    }
    func isWhitespace(_ s: String) -> Bool {
        usesMozillaWhitespaceSemantics
            ? javaScriptIsWhitespaceOnly(s)
            : matches(whitespace, in: s, legacyIgnoreCase: false)
    }
    func normalize(_ text: String) -> String {
        if usesMozillaNormalizeSemantics {
            return javaScriptNormalizeWhitespaceRuns(text)
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return normalize.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }
    func isVideo(_ s: String) -> Bool {
        matches(videos, in: s, legacyIgnoreCase: videoUsesMozillaIgnoreCaseSemantics)
    }

    var allowedVideoRegex: NSRegularExpression { videos }
}
