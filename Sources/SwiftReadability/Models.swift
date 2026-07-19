// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import Foundation
import SwiftSoup

/// Optional behavior layered on top of Mozilla Readability's observable contract.
///
/// The empty set is the default and is the mode used for direct differential
/// testing against the pinned Mozilla implementation. These extensions exist for
/// rendered publisher DOMs where a client deliberately prefers additional cleanup
/// or media recovery. They are kept explicit so they can never silently redefine
/// what "Mozilla compatible" means.
public struct ReadabilityExtensions: OptionSet, Sendable {
    /// The bit mask backing the selected extensions.
    public let rawValue: UInt8

    /// Creates an extension set from its bit-mask representation.
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Normalizes JavaScript-driven image galleries into semantic figures before scoring.
    public static let imageCarouselRecovery = Self(rawValue: 1 << 0)
    /// Removes compact publisher controls, paywall prompts, repeated titles, and related links.
    public static let publisherChromeCleanup = Self(rawValue: 1 << 1)
    /// Retains a low-link-density multi-paragraph body that conditional cleanup would discard.
    public static let articleBodyPreservation = Self(rawValue: 1 << 2)
    /// Retains a compact figure or picture that conditional cleanup would discard.
    public static let significantMediaPreservation = Self(rawValue: 1 << 3)
    /// Normalizes ruby fallback markup for clients that narrate visible base text separately.
    public static let rubyNormalization = Self(rawValue: 1 << 4)
}

/// Configuration for the Mozilla-compatible extraction pipeline.
public struct ReadabilityOptions {
    /// A zero value disables the document element-count limit.
    public static let defaultMaxElemsToParse = 0
    /// Mozilla's default number of high-scoring candidate elements to retain.
    public static let defaultNTopCandidates = 5
    /// Mozilla's default minimum extracted UTF-16 code-unit count before fallback retries.
    public static let defaultCharThreshold = 500

    /// Converts the detached extracted article element into HTML.
    public typealias Serializer = (Element) -> String

    /// Enables diagnostic logging from the extraction façade.
    public var debug: Bool
    /// Maximum number of source elements to parse; zero disables the limit.
    public var maxElemsToParse: Int
    /// Number of top-scoring candidates considered during article selection.
    public var nbTopCandidates: Int
    /// Minimum extracted UTF-16 code-unit length before progressively less aggressive retries run.
    public var charThreshold: Int
    /// CSS classes retained when ordinary source classes are stripped.
    public var classesToPreserve: [String]
    /// Preserves all source CSS classes when `true`.
    public var keepClasses: Bool
    /// Optional HTML serializer used by the non-generic ``Readability/parse()`` API.
    public var serializer: Serializer?
    /// Swift-specific convenience that requests XML syntax when the supplied
    /// SwiftSoup document is itself XML; Mozilla's JavaScript API has no such option.
    public var useXMLSerializer: Bool
    /// Ignores JSON-LD metadata and uses other document signals when `true`.
    public var disableJSONLD: Bool
    /// Replaces Mozilla's default allowlist for embedded-video URLs.
    public var allowedVideoRegex: NSRegularExpression?
    /// Adjusts the link-density threshold used by conditional cleanup.
    public var linkDensityModifier: Double
    /// Explicit non-Mozilla behavior to apply after establishing the compatible baseline.
    public var extensions: ReadabilityExtensions

    /// Creates extraction options using Mozilla-compatible defaults.
    ///
    /// Pass a nonempty `extensions` set only when the caller intentionally wants
    /// behavior beyond the pinned Mozilla contract.
    public init(debug: Bool = false,
                maxElemsToParse: Int = ReadabilityOptions.defaultMaxElemsToParse,
                nbTopCandidates: Int = ReadabilityOptions.defaultNTopCandidates,
                charThreshold: Int = ReadabilityOptions.defaultCharThreshold,
                classesToPreserve: [String] = [],
                keepClasses: Bool = false,
                serializer: Serializer? = nil,
                useXMLSerializer: Bool = false,
                disableJSONLD: Bool = false,
                allowedVideoRegex: NSRegularExpression? = nil,
                linkDensityModifier: Double = 0.0,
                extensions: ReadabilityExtensions = []) {
        self.debug = debug
        self.maxElemsToParse = maxElemsToParse
        self.nbTopCandidates = nbTopCandidates
        self.charThreshold = charThreshold
        self.classesToPreserve = classesToPreserve
        self.keepClasses = keepClasses
        self.serializer = serializer
        self.useXMLSerializer = useXMLSerializer
        self.disableJSONLD = disableJSONLD
        self.allowedVideoRegex = allowedVideoRegex
        self.linkDensityModifier = linkDensityModifier
        self.extensions = extensions
    }

    /// JavaScript's constructor uses `value || default` for these numeric
    /// options. Preserve that observable falsy-value behavior at one boundary
    /// rather than teaching each extraction phase its own version of it.
    var effectiveTopCandidateCount: Int {
        nbTopCandidates == 0 ? Self.defaultNTopCandidates : nbTopCandidates
    }

    var effectiveCharacterThreshold: Int {
        charThreshold == 0 ? Self.defaultCharThreshold : charThreshold
    }

    var effectiveLinkDensityModifier: Double {
        linkDensityModifier.isNaN || linkDensityModifier == 0 ? 0 : linkDensityModifier
    }
}

struct ArticleGrabberOptions {
    var stripUnlikelyCandidates: Bool = true
    var weightClasses: Bool = true
    var cleanConditionally: Bool = true
}

final class ArticleMetadata {
    var title: String?
    var byline: String?
    var creatorNames: [String] = []
    var excerpt: String?
    var siteName: String?
    var publishedTime: String?
}

final class ReadabilityObject {
    var contentScore: Double = 0.0
}

/// A mutable legacy article container retained for source compatibility.
///
/// New extraction code should prefer ``ReadabilityResult``. This type is useful
/// when a client needs to assemble or replace a SwiftSoup article element manually.
public final class Article {
    /// The source article URI as supplied by the caller; it is not normalized or resolved.
    public let uri: String
    /// The article title.
    public var title: String?
    /// The mutable article DOM; replacing it invalidates the cached plain text.
    public var articleContent: Element? {
        didSet { cachedTextContent = nil }
    }
    /// The article excerpt.
    public var excerpt: String?
    /// The article byline.
    public var byline: String?
    /// The inherited text direction.
    public var dir: String?
    /// The source document's character encoding, when known.
    public var charset: String?
    private var cachedTextContent: String?

    /// Creates an empty article container for a source URI.
    public init(uri: String) {
        self.uri = uri
    }

    /// The article element's serialized inner HTML.
    public var content: String? { try? articleContent?.html() }
    /// A complete HTML document declaring UTF-8.
    public var contentWithUtf8Encoding: String? { getContent(withEncoding: "utf-8") }
    /// A complete HTML document declaring ``charset`` or UTF-8 as a fallback.
    public var contentWithDocumentsCharsetOrUtf8: String? { getContent(withEncoding: charset ?? "utf-8") }
    /// SwiftSoup's normalized element text, cached until ``articleContent`` changes.
    public var textContent: String? {
        if let cachedTextContent { return cachedTextContent }
        let value = (try? articleContent?.text()) ?? articleContent?.ownText()
        cachedTextContent = value
        return value
    }
    /// The Swift grapheme-cluster count of ``textContent``, or `-1` when no content exists.
    ///
    /// This legacy count intentionally differs from ``ReadabilityResult/length``, which
    /// follows JavaScript and reports UTF-16 code units.
    public var length: Int { textContent?.count ?? -1 }

    private func getContent(withEncoding encoding: String) -> String? {
        guard let content else { return nil }
        return """
        <html>
          <head>
            <meta charset=\"\(encoding)\"/>
          </head>
          <body>
            \(content)
          </body>
        </html>
        """
    }
}
