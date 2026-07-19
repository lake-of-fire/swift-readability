import Foundation
import SwiftSoup

/// The observable article fields returned by Mozilla-compatible extraction.
public struct ReadabilityResult: Sendable {
    /// The resolved article title, or `nil` when no title signal is available.
    public let title: String?
    /// The resolved author/byline.
    public let byline: String?
    /// The inherited text direction, such as `ltr` or `rtl`.
    public let dir: String?
    /// The document language declared by the source HTML element.
    public let lang: String?
    /// The metadata excerpt, falling back to the first retained paragraph.
    public let excerpt: String?
    /// The publisher or site name supplied by structured metadata.
    public let siteName: String?
    /// The publication time supplied by structured metadata.
    public let publishedTime: String?
    /// Serialized HTML for the extracted article subtree.
    public let content: String
    /// DOM `textContent` semantics: descendant text nodes concatenated in document order.
    public let textContent: String
    /// `textContent` length in UTF-16 code units, matching JavaScript `String.length`.
    public let length: Int
    /// Whether Mozilla's lightweight preflight heuristic considered the source readerable.
    public let readerable: Bool

    /// A descriptive alias for ``content``.
    public var contentHTML: String { content }
}

/// A readability result whose content was projected by a caller-supplied serializer.
public struct ReadabilitySerializedResult<Content> {
    /// The resolved article title, or `nil` when no title signal is available.
    public let title: String?
    /// The resolved author/byline.
    public let byline: String?
    /// The inherited text direction, such as `ltr` or `rtl`.
    public let dir: String?
    /// The language declared by the source document.
    public let lang: String?
    /// The metadata excerpt, falling back to the first retained paragraph.
    public let excerpt: String?
    /// The publisher or site name supplied by structured metadata.
    public let siteName: String?
    /// The publication time supplied by structured metadata.
    public let publishedTime: String?
    /// The caller-defined projection of the detached extracted article element.
    public let content: Content
    /// DOM `textContent` semantics: descendant text nodes concatenated in document order.
    public let textContent: String
    /// ``textContent`` length in UTF-16 code units, matching JavaScript `String.length`.
    public let length: Int
    /// Whether Mozilla's lightweight preflight heuristic considered the source readerable.
    public let readerable: Bool
}

extension ReadabilitySerializedResult: Sendable where Content: Sendable {}

/// A native Swift implementation of Mozilla Readability using SwiftSoup for DOM processing.
///
/// HTML-backed instances parse a fresh document for each call. Document-backed instances
/// operate directly on—and destructively normalize—the supplied DOM, matching Mozilla's
/// mutation contract. A `Readability` instance is not `Sendable`; create and use it within
/// one task or actor.
public final class Readability {
    private static let unlikelyCandidatesRegex = try! NSRegularExpression(
        pattern: "-ad-|ai2html|banner|breadcrumbs|combx|comment|community|cover-wrap|disqus|extra|footer|gdpr|header|legends|menu|related|remark|replies|rss|shoutbox|sidebar|skyscraper|social|sponsor|supplemental|ad-break|agegate|pagination|pager|popup|yom-remote",
        options: [.caseInsensitive]
    )
    private static let okMaybeItsACandidateRegex = try! NSRegularExpression(
        pattern: "and|article|body|column|content|main|mathjax|shadow",
        options: [.caseInsensitive]
    )
    private static let displayNoneRegex = try! NSRegularExpression(
        pattern: "display\\s*:\\s*none",
        options: [.caseInsensitive]
    )
    private let html: String
    private let url: URL
    private let options: ReadabilityOptions
    private let document: Document?

    private let regEx: RegExUtil
    private lazy var preprocessor = Preprocessor(regEx: regEx, extensions: options.extensions)
    private lazy var metadataParser = MetadataParser(regEx: regEx)
    private lazy var postprocessor = Postprocessor()

    var debugEnabled: Bool { options.debug }
    var nbTopCandidates: Int { options.nbTopCandidates }
    var maxElemsToParse: Int { options.maxElemsToParse }
    var keepClasses: Bool { options.keepClasses }
    var allowedVideoRegex: NSRegularExpression { options.allowedVideoRegex ?? regEx.allowedVideoRegex }

    /// Creates an extractor from an HTML snapshot and the URL used to resolve relative links.
    public init(html: String, url: URL, options: ReadabilityOptions = ReadabilityOptions()) {
        self.html = html
        self.url = url
        self.options = options
        self.regEx = RegExUtil(options: options)
        self.document = nil
    }

    private init(html: String, url: URL, document: Document?, options: ReadabilityOptions) {
        self.html = html
        self.url = url
        self.options = options
        self.regEx = RegExUtil(options: options)
        self.document = document
    }

    /// Creates an extractor that mutates the supplied SwiftSoup document in place.
    public convenience init(document: Document, options: ReadabilityOptions = ReadabilityOptions()) {
        let baseUri = document.location()
        let resolvedURL = URL(string: baseUri) ?? URL(string: "about:blank")!
        self.init(html: "", url: resolvedURL, document: document, options: options)
    }

    /// Runs the full extraction pipeline, returning `nil` when no article can be selected.
    public func parse() throws -> ReadabilityResult? {
        guard let parsed = try parseArticle() else { return nil }
        let textContent = textContentPreservingWhitespace(of: parsed.articleContent)
        let contentHTML: String
        if let serializer = options.serializer {
            contentHTML = serializer(parsed.articleContent)
        } else {
            contentHTML = serializeArticleContent(
                document: parsed.document,
                articleContent: parsed.articleContent,
                useXMLSerializer: options.useXMLSerializer,
                isLiveDocument: parsed.isLiveDocument
            )
        }

        return ReadabilityResult(
            title: parsed.metadata.title,
            byline: parsed.metadata.byline ?? parsed.articleByline,
            dir: parsed.articleDirection,
            lang: parsed.lang,
            excerpt: parsed.metadata.excerpt,
            siteName: parsed.metadata.siteName,
            publishedTime: parsed.metadata.publishedTime,
            content: contentHTML,
            textContent: textContent,
            length: textContent.utf16.count,
            readerable: parsed.readerable
        )
    }

    /// Per-stage wall-clock measurements collected by ``parseWithTimings()``.
    ///
    /// Keys are diagnostic implementation labels and are not a stable public protocol.
    @_spi(Bench)
    public struct ReadabilityTimings: Sendable {
        /// Cumulative elapsed milliseconds keyed by extraction-stage label.
        public let milliseconds: [String: Double]

        /// Creates a timing snapshot from cumulative stage measurements.
        @_spi(Bench)
        public init(milliseconds: [String: Double]) {
            self.milliseconds = milliseconds
        }
    }

    private final class TimingCollector: TimingSink {
        var milliseconds: [String: Double] = [:]

        func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = try block()
            let end = DispatchTime.now().uptimeNanoseconds
            let elapsedMs = Double(end - start) / 1_000_000.0
            milliseconds[label, default: 0.0] += elapsedMs
            return result
        }
    }

    /// Runs the same extraction path as ``parse()`` while collecting diagnostic timings.
    ///
    /// - Returns: The extraction result, if any, and cumulative per-stage wall-clock timings.
    @_spi(Bench)
    public func parseWithTimings() throws -> (ReadabilityResult?, ReadabilityTimings) {
        let timing = TimingCollector()
        guard let parsed = try parseArticle(timing: timing) else {
            return (nil, ReadabilityTimings(milliseconds: timing.milliseconds))
        }

        let textContent = timing.measure("textContent") {
            textContentPreservingWhitespace(of: parsed.articleContent)
        }
        let contentHTML: String = timing.measure("serialize") {
            if let serializer = options.serializer {
                return serializer(parsed.articleContent)
            }
            return serializeArticleContent(
                document: parsed.document,
                articleContent: parsed.articleContent,
                useXMLSerializer: options.useXMLSerializer,
                isLiveDocument: parsed.isLiveDocument
            )
        }

        let result = ReadabilityResult(
            title: parsed.metadata.title,
            byline: parsed.metadata.byline ?? parsed.articleByline,
            dir: parsed.articleDirection,
            lang: parsed.lang,
            excerpt: parsed.metadata.excerpt,
            siteName: parsed.metadata.siteName,
            publishedTime: parsed.metadata.publishedTime,
            content: contentHTML,
            textContent: textContent,
            length: textContent.utf16.count,
            readerable: parsed.readerable
        )
        return (result, ReadabilityTimings(milliseconds: timing.milliseconds))
    }

    /// Runs extraction and projects the detached article element into an arbitrary content type.
    public func parse<Content>(serializer: (Element) -> Content) throws -> ReadabilitySerializedResult<Content>? {
        guard let parsed = try parseArticle() else { return nil }
        let content = serializer(parsed.articleContent)
        let textContent = textContentPreservingWhitespace(of: parsed.articleContent)
        return ReadabilitySerializedResult(
            title: parsed.metadata.title,
            byline: parsed.metadata.byline ?? parsed.articleByline,
            dir: parsed.articleDirection,
            lang: parsed.lang,
            excerpt: parsed.metadata.excerpt,
            siteName: parsed.metadata.siteName,
            publishedTime: parsed.metadata.publishedTime,
            content: content,
            textContent: textContent,
            length: textContent.utf16.count,
            readerable: parsed.readerable
        )
    }

    // MARK: Readerable heuristic
    /// Applies Mozilla's inexpensive readerability heuristic to an HTML string.
    public static func isProbablyReaderable(html: String) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        return isProbablyReaderable(doc: doc)
    }

    /// Applies the readerability heuristic to an existing document without extracting it.
    public static func isProbablyReaderable(document: Document, options: ReaderableOptions = ReaderableOptions()) -> Bool {
        return isProbablyReaderable(doc: document, options: options, visibilityChecker: options.visibilityChecker)
    }

    /// Applies the heuristic using a caller-defined visibility predicate.
    public static func isProbablyReaderable(document: Document, visibilityChecker: @escaping (Element) -> Bool) -> Bool {
        return isProbablyReaderable(doc: document, options: ReaderableOptions(), visibilityChecker: visibilityChecker)
    }

    /// Thresholds and visibility policy for the lightweight readerability heuristic.
    public struct ReaderableOptions {
        /// Minimum candidate text length considered by the heuristic.
        public var minContentLength: Int
        /// Accumulated score required before a document is considered readerable.
        public var minScore: Double
        /// Optional visibility predicate; returning `false` excludes an element.
        public var visibilityChecker: ((Element) -> Bool)?

        /// Creates heuristic options using Mozilla's default thresholds.
        ///
        /// - Parameters:
        ///   - minContentLength: Minimum candidate text length considered for scoring.
        ///   - minScore: Accumulated score required to classify the document as readerable.
        ///   - visibilityChecker: Optional predicate that excludes elements by returning `false`.
        public init(minContentLength: Int = 140,
                    minScore: Double = 20.0,
                    visibilityChecker: ((Element) -> Bool)? = nil) {
            self.minContentLength = minContentLength
            self.minScore = minScore
            self.visibilityChecker = visibilityChecker
        }
    }

    /// Applies the readerability heuristic to HTML with custom thresholds.
    public static func isProbablyReaderable(html: String, options: ReaderableOptions) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        return isProbablyReaderable(doc: doc, options: options, visibilityChecker: options.visibilityChecker)
    }

    /// Applies the readerability heuristic to HTML using a custom visibility predicate.
    public static func isProbablyReaderable(html: String, visibilityChecker: @escaping (Element) -> Bool) -> Bool {
        guard let doc = try? SwiftSoup.parse(html) else { return false }
        return isProbablyReaderable(doc: doc, options: ReaderableOptions(), visibilityChecker: visibilityChecker)
    }

    static func isProbablyReaderable(doc: Document,
                                     options: ReaderableOptions = ReaderableOptions(),
                                     visibilityChecker: ((Element) -> Bool)? = nil) -> Bool {
        // Port of Readability-readerable.js
        let minScore = options.minScore
        let minContentLength = options.minContentLength

        var nodes: [Element] = (try? doc.select("p, pre, article").array()) ?? []

        if let brNodes = try? doc.select("div > br"), brNodes.count > 0 {
            var set: [ObjectIdentifier: Element] = [:]
            for node in nodes { set[ObjectIdentifier(node)] = node }
            for br in brNodes {
                if let parent = br.parent() {
                    set[ObjectIdentifier(parent)] = parent
                }
            }
            nodes = Array(set.values)
        }

        let unlikelyCandidates = Readability.unlikelyCandidatesRegex
        let okMaybeItsACandidate = Readability.okMaybeItsACandidateRegex
        let displayNone = Readability.displayNoneRegex

        func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
            regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil
        }

        func defaultVisibilityChecker(_ node: Element) -> Bool {
            let styleBytes = node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.style)
            let style = String(decoding: styleBytes, as: UTF8.self)
            if matches(displayNone, style) { return false }
            if node.hasAttr(ReadabilityUTF8Arrays.hidden) { return false }
            if node.hasAttr(ReadabilityUTF8Arrays.ariaHidden),
               node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.ariaHidden) == ReadabilityUTF8Arrays.true_ {
                let className = node.classNameSafe()
                if !className.contains("fallback-image") { return false }
            }
            return true
        }

        func isDescendantOfListItem(_ node: Element) -> Bool {
            var parent = node.parent()
            while let p = parent {
                if p.tagNameUTF8() == ReadabilityUTF8Arrays.li { return true }
                parent = p.parent()
            }
            return false
        }

        var score = 0.0
        let isVisible: (Element) -> Bool = visibilityChecker ?? options.visibilityChecker ?? defaultVisibilityChecker

        for node in nodes {
            if !isVisible(node) { continue }

            let matchString = node.classNameSafe() + " " + node.idSafe()
            if matches(unlikelyCandidates, matchString), !matches(okMaybeItsACandidate, matchString) {
                continue
            }

            if node.tagNameUTF8() == ReadabilityUTF8Arrays.p, isDescendantOfListItem(node) {
                continue
            }

            let trimmedText = textContentPreservingWhitespace(of: node)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.utf8.count < minContentLength { continue }
            let textLength = trimmedText.count
            if textLength < minContentLength { continue }
            score += sqrt(Double(textLength - minContentLength))
            if score > minScore { return true }
        }
        return false
    }

}

private extension Readability {
    struct ParsedArticle {
        let document: Document
        let articleContent: Element
        let metadata: ArticleMetadata
        let readerable: Bool
        let lang: String?
        let articleByline: String?
        let articleDirection: String?
        let isLiveDocument: Bool
    }

    private func parseArticle(timing: TimingSink? = nil) throws -> ParsedArticle? {
        // ArticleGrabber owns per-extraction scores and DOM identity caches. Keep
        // its lifetime inside one invocation so public Readability instances are
        // deterministic when HTML-backed clients call parse more than once.
        let articleGrabber = ArticleGrabber(options: options, regEx: regEx)
        let document: Document
        let isLiveDocument: Bool
        if let provided = self.document {
            document = provided
            isLiveDocument = true
        } else {
            document = try measured("parseDocument", by: timing) {
                try SwiftSoup.parse(html, url.absoluteString)
            }
            isLiveDocument = false
        }
        let readerable = measured("readerable", by: timing) {
            Readability.isProbablyReaderable(doc: document)
        }

        if options.maxElemsToParse > 0 {
            let numTags = (try? document.getAllElements().count) ?? 0
            if numTags > options.maxElemsToParse {
                let message = "Aborting parsing document; " + String(numTags) + " elements found"
                throw NSError(domain: "Readability", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }

        let metadata = measured("metadata", by: timing) {
            metadataParser.getArticleMetadata(document, disableJSONLD: options.disableJSONLD)
        }
        measured("preprocess", by: timing) {
            preprocessor.prepareDocument(document)
        }

        let content = measured("grabArticle", by: timing) {
            articleGrabber.grabArticle(doc: document, metadata: metadata, timing: timing)
        }
        guard let articleContent = content else { return nil }

        measured("postprocess", by: timing) {
            postprocessor.postProcessContent(
                originalDocument: document,
                articleContent: articleContent,
                articleUri: url.absoluteString,
                keepClasses: options.keepClasses,
                classesToPreserve: options.classesToPreserve
            )
        }

        if (metadata.excerpt ?? "").isEmpty {
            // SwiftSoup's getElementsByTag caches tag indexes and can become stale after DOM mutations.
            // Prefer select("p") here to mirror Readability.js's document-order selection reliably.
            measured("excerpt", by: timing) {
                if let paragraphs = try? articleContent.select("p"),
                   let firstPara = paragraphs.first() {
                    let excerpt = textContentPreservingWhitespace(of: firstPara)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !excerpt.isEmpty {
                        metadata.excerpt = excerpt
                    }
                }
            }
        }

        let lang: String? = measured("lang", by: timing) {
            guard let html = try? document.select("html").first() else { return nil }
            let value = String(decoding: html.attrOrEmptyUTF8(ReadabilityUTF8Arrays.lang), as: UTF8.self)
            return value.isEmpty ? nil : value
        }

        debugLog(["Grabbed:", articleContent])

        return ParsedArticle(
            document: document,
            articleContent: articleContent,
            metadata: metadata,
            readerable: readerable,
            lang: lang,
            articleByline: articleGrabber.articleByline,
            articleDirection: articleGrabber.articleDir,
            isLiveDocument: isLiveDocument
        )
    }

    func serializeArticleContent(document: Document,
                                 articleContent: Element,
                                 useXMLSerializer: Bool,
                                 isLiveDocument: Bool) -> String {
        let isXmlInput = document.outputSettings().syntax() == .xml
        let effectiveUseXMLSerializer = useXMLSerializer && isXmlInput
        let sourceHTML: String
        if effectiveUseXMLSerializer {
            if !html.isEmpty {
                sourceHTML = html
            } else {
                sourceHTML = (try? document.outerHtml()) ?? ""
            }
        } else {
            sourceHTML = ""
        }
        let explicitBooleanAttrs = effectiveUseXMLSerializer ? explicitBooleanAttributes(in: sourceHTML) : []
        let needsSerializationDoc = articleContent.ownerDocument() == nil
        if effectiveUseXMLSerializer, !isLiveDocument || needsSerializationDoc {
            normalizeBooleanAttributes(in: articleContent, sourceHTML: sourceHTML, explicitBooleanAttrs: explicitBooleanAttrs)
            let serializationDoc = try! SwiftSoup.parse("", url.absoluteString, Parser.xmlParser())
            let outputSettings = serializationDoc.outputSettings()
            outputSettings.prettyPrint(pretty: false)
            outputSettings.syntax(syntax: .xml)
            _ = try? serializationDoc.body()?.appendChild(articleContent)
            return (try? articleContent.html()) ?? ""
        }
        if needsSerializationDoc {
            let serializationDoc = try! SwiftSoup.parse("", url.absoluteString)
            let outputSettings = serializationDoc.outputSettings()
            outputSettings.prettyPrint(pretty: false)
            outputSettings.syntax(syntax: .html)
            _ = try? serializationDoc.body()?.appendChild(articleContent)
            collapseBooleanAttributesForHTML(in: articleContent)
            return (try? articleContent.html()) ?? ""
        }

        let outputSettings = document.outputSettings()
        let originalPrettyPrint = outputSettings.prettyPrint()
        let originalSyntax = outputSettings.syntax()
        outputSettings.prettyPrint(pretty: false)
        outputSettings.syntax(syntax: effectiveUseXMLSerializer ? .xml : .html)
        if effectiveUseXMLSerializer {
            normalizeBooleanAttributes(in: articleContent, sourceHTML: sourceHTML, explicitBooleanAttrs: explicitBooleanAttrs)
        } else {
            collapseBooleanAttributesForHTML(in: articleContent)
        }
        let html = (try? articleContent.html()) ?? ""
        outputSettings.prettyPrint(pretty: originalPrettyPrint)
        outputSettings.syntax(syntax: originalSyntax)
        return html
    }

    func collapseBooleanAttributesForHTML(in root: Element) {
        let booleanAttrs: Set<String> = [
            "allowfullscreen",
            "async",
            "autofocus",
            "autoplay",
            "checked",
            "controls",
            "default",
            "defer",
            "disabled",
            "formnovalidate",
            "hidden",
            "ismap",
            "itemscope",
            "loop",
            "multiple",
            "muted",
            "novalidate",
            "open",
            "playsinline",
            "readonly",
            "required",
            "reversed",
            "selected",
            "typemustmatch"
        ]

        guard let elements = try? root.getAllElements() else { return }
        for element in elements {
            guard let attributes = element.getAttributes()?.asList() else { continue }
            for attr in attributes {
                let attrNameLower = String(decoding: attr.getKeyUTF8(), as: UTF8.self).lowercased()
                guard booleanAttrs.contains(attrNameLower) else { continue }
                let value = String(decoding: attr.getValueUTF8(), as: UTF8.self)
                guard value.caseInsensitiveCompare(attrNameLower) == .orderedSame else { continue }
                _ = try? element.attr(attr.getKey(), "")
            }
        }
    }

    func normalizeBooleanAttributes(in root: Element, sourceHTML: String, explicitBooleanAttrs: [String]) {
        guard !sourceHTML.isEmpty else { return }
        guard !explicitBooleanAttrs.isEmpty else { return }
        let explicitSet = Set(explicitBooleanAttrs)
        let booleanAttrs: Set<String> = [
            "allowfullscreen",
            "async",
            "autofocus",
            "autoplay",
            "checked",
            "controls",
            "default",
            "defer",
            "disabled",
            "formnovalidate",
            "hidden",
            "ismap",
            "itemscope",
            "loop",
            "multiple",
            "muted",
            "novalidate",
            "open",
            "playsinline",
            "readonly",
            "required",
            "reversed",
            "selected",
            "typemustmatch"
        ]

        guard let elements = try? root.getAllElements() else { return }
        var matchCache: [String: Bool] = [:]
        for element in elements {
            guard let attributes = element.getAttributes()?.asList() else { continue }
            for attr in attributes where attr.getValueUTF8().isEmpty {
                let keyBytes = attr.getKeyUTF8()
                let attrNameLower = String(decoding: keyBytes, as: UTF8.self).lowercased()
                if !booleanAttrs.contains(attrNameLower) { continue }
                if !explicitSet.contains(attrNameLower) { continue }
                if shouldPromoteBooleanAttributeValue(
                    tagName: String(decoding: element.tagNameUTF8(), as: UTF8.self),
                    attributes: element.getAttributes(),
                    attrName: attrNameLower,
                    sourceHTML: sourceHTML,
                    matchCache: &matchCache
                ) {
                    _ = try? element.attr(attr.getKey(), attr.getKey())
                }
            }
        }
    }

    private func shouldPromoteBooleanAttributeValue(tagName: String,
                                                    attributes: Attributes?,
                                                    attrName: String,
                                                    sourceHTML: String,
                                                    matchCache: inout [String: Bool]) -> Bool {
        let identifiers = [
            ReadabilityUTF8Arrays.id,
            "itemid".utf8Array,
            ReadabilityUTF8Arrays.src,
            "data-media-id".utf8Array,
            "data-uuid".utf8Array,
            "data-type".utf8Array,
            "data-aop".utf8Array
        ]
        for key in identifiers {
            guard let valueBytes = try? attributes?.getIgnoreCase(key: key), !valueBytes.isEmpty else { continue }
            let value = String(decoding: valueBytes, as: UTF8.self)
            if tagHasAttributeValue(tagName: tagName,
                                    matchAttr: String(decoding: key, as: UTF8.self),
                                    matchValue: value,
                                    targetAttr: attrName,
                                    sourceHTML: sourceHTML,
                                    matchCache: &matchCache) {
                return true
            }
        }

        // Fallback: if the source contains an element with matching tag + itemtype + itemprop and the explicit value.
        if let itemtypeBytes = try? attributes?.getIgnoreCase(key: "itemtype".utf8Array),
           let itempropBytes = try? attributes?.getIgnoreCase(key: ReadabilityUTF8Arrays.itemprop),
           !itemtypeBytes.isEmpty, !itempropBytes.isEmpty {
            let itemtype = String(decoding: itemtypeBytes, as: UTF8.self)
            let itemprop = String(decoding: itempropBytes, as: UTF8.self)
            let escapedItemtype = NSRegularExpression.escapedPattern(for: itemtype)
            let escapedItemprop = NSRegularExpression.escapedPattern(for: itemprop)
            let escapedAttr = NSRegularExpression.escapedPattern(for: attrName)
            let escapedTag = NSRegularExpression.escapedPattern(for: tagName)
            let cacheKey = "itemtype|" + escapedTag + "|" + escapedItemtype + "|" + escapedItemprop + "|" + escapedAttr
            if let cached = matchCache[cacheKey] { return cached }
            let pattern = "<\\s*" + escapedTag +
                "\\b[^>]*\\bitemtype\\s*=\\s*\"" + escapedItemtype +
                "\"[^>]*\\bitemprop\\s*=\\s*\"" + escapedItemprop +
                "\"[^>]*\\b" + attrName +
                "\\s*=\\s*\"" + escapedAttr + "\""
            let found = sourceHTML.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            matchCache[cacheKey] = found
            return found
        }
        return false
    }

    private func tagHasAttributeValue(tagName: String,
                                      matchAttr: String,
                                      matchValue: String,
                                      targetAttr: String,
                                      sourceHTML: String,
                                      matchCache: inout [String: Bool]) -> Bool {
        let escapedValue = NSRegularExpression.escapedPattern(for: matchValue)
        let escapedTag = NSRegularExpression.escapedPattern(for: tagName)
        let escapedMatchAttr = NSRegularExpression.escapedPattern(for: matchAttr)
        let pattern = "<\\s*" + escapedTag + "\\b[^>]*\\b" + escapedMatchAttr + "\\s*=\\s*\"" + escapedValue + "\"[^>]*>"
        let cacheKey = "id|" + escapedTag + "|" + escapedMatchAttr + "|" + escapedValue + "|" + targetAttr
        if let cached = matchCache[cacheKey] { return cached }
        guard let range = sourceHTML.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            matchCache[cacheKey] = false
            return false
        }
        let tag = String(sourceHTML[range])
        let escapedTarget = NSRegularExpression.escapedPattern(for: targetAttr)
        let targetPattern = "\\b" + targetAttr + "\\s*=\\s*\"" + escapedTarget + "\""
        let found = tag.range(of: targetPattern, options: [.regularExpression, .caseInsensitive]) != nil
        matchCache[cacheKey] = found
        return found
    }

    private func explicitBooleanAttributes(in sourceHTML: String) -> [String] {
        guard !sourceHTML.isEmpty else { return [] }
        let candidates = [
            "allowfullscreen",
            "async",
            "autofocus",
            "autoplay",
            "checked",
            "controls",
            "default",
            "defer",
            "disabled",
            "formnovalidate",
            "hidden",
            "ismap",
            "itemscope",
            "loop",
            "multiple",
            "muted",
            "novalidate",
            "open",
            "playsinline",
            "readonly",
            "required",
            "reversed",
            "selected",
            "typemustmatch"
        ]
        var result: [String] = []
        for attr in candidates {
            let escapedAttr = NSRegularExpression.escapedPattern(for: attr)
            let pattern = "\\b" + escapedAttr + "\\s*=\\s*\"\\s*" + escapedAttr + "\\s*\""
            if sourceHTML.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                result.append(attr)
            }
        }
        return result
    }
}

// MARK: - Debug logging (parity with Readability.js)

private extension Readability {
    func debugLog(_ items: [Any], prefix: String = "Reader: (Readability)") {
        guard options.debug else { return }
        let message = items.map { item -> String in
            if let element = item as? Element {
                let attrPairs = element.getAttributes()?.asList().map { attr in
                    attr.getKey() + "=\"" + attr.getValue() + "\""
                }.joined(separator: " ") ?? ""
                let tagName = String(decoding: element.tagNameUTF8(), as: UTF8.self)
                return "<" + tagName + " " + attrPairs + ">"
            } else if let text = item as? TextNode {
                return "#text(\"" + text.getWholeText() + "\")"
            } else {
                return String(describing: item)
            }
        }.joined(separator: " ")
        print(prefix + " " + message)
    }
}
