import Foundation

/// Regex helper mirroring Readability.js REGEXPS.
final class RegExUtil {
    static let unlikelyCandidatesDefaultPattern = "-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote"

    static let okMaybeItsACandidateDefaultPattern = "and|article|body|column|content|main|mathjax|shadow"

    static let positiveDefaultPattern = "article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story"

    static let negativeDefaultPattern = "-ad-|hidden|^hid$| hid$| hid |^hid |banner|combx|comment|com-|contact|footer|gdpr|masthead|media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget"

    static let extraneousDefaultPattern = "print|archive|comment|discuss|e[\\-]?mail|share|reply|all|login|sign|single|utility"

    static let bylineDefaultPattern = "byline|author|dateline|writtenby|p-author"

    static let replaceFontsDefaultPattern = "<(/?)font[^>]*>"

    static let normalizeDefaultPattern = "\\s{2,}"

    static let videosDefaultPattern = "//(www\\.)?((dailymotion|youtube|youtube-nocookie|player\\.vimeo|v\\.qq|bilibili|live\\.bilibili)\\.com|(archive|upload\\.wikimedia)\\.org|player\\.twitch\\.tv)"

    static let nextLinkDefaultPattern = "(next|weiter|continue|>([^\\|]|$)|»([^\\|]|$))"

    static let prevLinkDefaultPattern = "(prev|earl|old|new|<|«)"

    static let whitespaceDefaultPattern = "^\\s*$"

    static let hasContentDefaultPattern = "\\S$"

    private let unlikelyCandidates: NSRegularExpression
    private let okMaybeItsACandidate: NSRegularExpression
    private let positive: NSRegularExpression
    private let negative: NSRegularExpression
    private let extraneous: NSRegularExpression
    private let byline: NSRegularExpression
    private let replaceFonts: NSRegularExpression
    private let normalize: NSRegularExpression
    private let videos: NSRegularExpression
    private let nextLink: NSRegularExpression
    private let prevLink: NSRegularExpression
    private let whitespace: NSRegularExpression
    private let hasContent: NSRegularExpression

    init(unlikelyCandidatesPattern: String = unlikelyCandidatesDefaultPattern,
         okMaybeItsACandidatePattern: String = okMaybeItsACandidateDefaultPattern,
         positivePattern: String = positiveDefaultPattern,
         negativePattern: String = negativeDefaultPattern,
         extraneousPattern: String = extraneousDefaultPattern,
         bylinePattern: String = bylineDefaultPattern,
         replaceFontsPattern: String = replaceFontsDefaultPattern,
         normalizePattern: String = normalizeDefaultPattern,
         videosPattern: String = videosDefaultPattern,
         allowedVideoRegex: NSRegularExpression? = nil,
         nextLinkPattern: String = nextLinkDefaultPattern,
         prevLinkPattern: String = prevLinkDefaultPattern,
         whitespacePattern: String = whitespaceDefaultPattern,
         hasContentPattern: String = hasContentDefaultPattern) {
        func re(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
            return try! NSRegularExpression(pattern: pattern, options: options)
        }
        unlikelyCandidates = re(unlikelyCandidatesPattern)
        okMaybeItsACandidate = re(okMaybeItsACandidatePattern)
        positive = re(positivePattern)
        negative = re(negativePattern)
        extraneous = re(extraneousPattern)
        byline = re(bylinePattern)
        replaceFonts = re(replaceFontsPattern)
        normalize = re(normalizePattern, options: [])
        videos = allowedVideoRegex ?? re(videosPattern)
        nextLink = re(nextLinkPattern)
        prevLink = re(prevLinkPattern)
        whitespace = re(whitespacePattern, options: [])
        hasContent = re(hasContentPattern, options: [])
    }

    private func matches(_ regex: NSRegularExpression, in string: String) -> Bool {
        return regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil
    }

    func isPositive(_ s: String) -> Bool { matches(positive, in: s) }
    func isNegative(_ s: String) -> Bool { matches(negative, in: s) }
    func isUnlikelyCandidate(_ s: String) -> Bool { matches(unlikelyCandidates, in: s) }
    func okMaybeItsACandidate(_ s: String) -> Bool { matches(okMaybeItsACandidate, in: s) }
    func isByline(_ s: String) -> Bool { matches(byline, in: s) }
    func hasContent(_ s: String) -> Bool { matches(hasContent, in: s) }
    func isWhitespace(_ s: String) -> Bool { matches(whitespace, in: s) }
    func normalize(_ text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        return normalize.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }
    func isVideo(_ s: String) -> Bool { matches(videos, in: s) }

    var allowedVideoRegex: NSRegularExpression { videos }
}
