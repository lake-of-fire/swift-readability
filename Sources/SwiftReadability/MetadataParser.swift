// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import Foundation
import SwiftSoup
import WebURL

/// Port of Readability.js metadata extraction (JSON-LD + meta tags).
final class MetadataParser: ProcessorBase {
    private let regEx: RegExUtil
    // The pinned expressions use JavaScript anchors. ICU's `$` also matches
    // before trailing Unicode line terminators, so Foundation regexes cannot
    // implement these two checks exactly. Their grammar is entirely literal;
    // direct string operations preserve the intentionally asymmetric anchors.
    private static let unanchoredJSONLDArticleTypes = [
        "AdvertiserContentArticle",
        "NewsArticle",
        "AnalysisNewsArticle",
        "AskPublicNewsArticle",
        "BackgroundNewsArticle",
        "OpinionNewsArticle",
        "ReportageNewsArticle",
        "ReviewNewsArticle",
        "Report",
        "SatiricalArticle",
        "ScholarlyArticle",
        "MedicalScholarlyArticle",
        "SocialMediaPosting",
        "BlogPosting",
        "LiveBlogPosting",
        "DiscussionForumPosting",
        "TechArticle",
    ]
    private static let propertyNamespaces = ["article", "dc", "dcterm", "og", "twitter"]
    private static let nameNamespaces = [
        "dc", "dcterm", "og", "twitter", "parsely", "weibo:article", "weibo:webpage",
    ]
    private static let propertyFields = [
        "author", "creator", "description", "published_time", "title", "site_name",
    ]
    private static let nameFields = ["author", "creator", "pub-date", "description", "title", "site_name"]
    private static let namedEntityRegex = try! NSRegularExpression(
        pattern: "&(quot|amp|apos|lt|gt);",
        options: []
    )
    private static let numericEntityRegex = try! NSRegularExpression(
        pattern: "&#(?:x([0-9a-f]+)|([0-9]+));",
        options: [.caseInsensitive]
    )

    init(regEx: RegExUtil = RegExUtil()) {
        self.regEx = regEx
    }

    func getArticleMetadata(_ document: Document, disableJSONLD: Bool) -> ArticleMetadata {
        let jsonld = disableJSONLD ? JSONLDMetadata() : getJSONLDMetadata(document)
        let values = getMetaValues(document)

        let metadata = ArticleMetadata()

        // title
        if let value = jsonld.title, !value.isEmpty {
            metadata.title = value
        } else if let value = values["dc:title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["dcterm:title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["og:title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["weibo:article:title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["weibo:webpage:title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["twitter:title"], !value.isEmpty {
            metadata.title = value
        } else if let value = values["parsely-title"], !value.isEmpty {
            metadata.title = value
        }

        if metadata.title == nil {
            metadata.title = getArticleTitle(document)
        }

        // author
        let articleAuthor: String? = {
            guard let author = values["article:author"], !isUrl(author) else { return nil }
            return author
        }()

        if let value = jsonld.byline, !value.isEmpty {
            metadata.byline = value
        } else if let value = values["dc:creator"], !value.isEmpty {
            metadata.byline = value
        } else if let value = values["dcterm:creator"], !value.isEmpty {
            metadata.byline = value
        } else if let value = values["author"], !value.isEmpty {
            metadata.byline = value
        } else if let value = values["parsely-author"], !value.isEmpty {
            metadata.byline = value
        } else if let value = articleAuthor, !value.isEmpty {
            metadata.byline = value
        }
        metadata.creatorNames = jsonld.creatorNames

        // excerpt/description
        if let value = jsonld.excerpt, !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["dc:description"], !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["dcterm:description"], !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["og:description"], !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["weibo:article:description"], !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["weibo:webpage:description"], !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["description"], !value.isEmpty {
            metadata.excerpt = value
        } else if let value = values["twitter:description"], !value.isEmpty {
            metadata.excerpt = value
        }

        // site name
        if let value = jsonld.siteName, !value.isEmpty {
            metadata.siteName = value
        } else if let value = values["og:site_name"], !value.isEmpty {
            metadata.siteName = value
        }

        // published time
        if let value = jsonld.datePublished, !value.isEmpty {
            metadata.publishedTime = value
        } else if let value = values["article:published_time"], !value.isEmpty {
            metadata.publishedTime = value
        } else if let value = values["parsely-pub-date"], !value.isEmpty {
            metadata.publishedTime = value
        }

        // Unescape common HTML entities + numeric references (Readability.js behavior).
        metadata.title = unescapeHtmlEntities(metadata.title)
        metadata.byline = unescapeHtmlEntities(metadata.byline)
        metadata.excerpt = unescapeHtmlEntities(metadata.excerpt)
        metadata.siteName = unescapeHtmlEntities(metadata.siteName)
        metadata.publishedTime = unescapeHtmlEntities(metadata.publishedTime)

        return metadata
    }

    // MARK: - Meta tags

    private func getMetaValues(_ document: Document) -> [String: String] {
        var values: [String: String] = [:]

        guard let metas = try? document.select("meta") else { return values }
        for element in metas {
            let content = String(decoding: element.attrOrEmptyUTF8(ReadabilityUTF8Arrays.content), as: UTF8.self)
            if content.isEmpty { continue }

            let elementName = String(decoding: element.attrOrEmptyUTF8(ReadabilityUTF8Arrays.name), as: UTF8.self)
            let elementProperty = String(decoding: element.attrOrEmptyUTF8(ReadabilityUTF8Arrays.property), as: UTF8.self)

            if !elementProperty.isEmpty, let key = metaPropertyKey(in: elementProperty) {
                values[key] = javaScriptTrim(content)
                continue
            }

            if !elementName.isEmpty, let key = metaNameKey(in: elementName) {
                values[key] = javaScriptTrim(content)
            }
        }

        return values
    }

    // MARK: - JSON-LD

    private struct JSONLDMetadata {
        var title: String?
        var byline: String?
        var creatorNames: [String] = []
        var excerpt: String?
        var siteName: String?
        var datePublished: String?
    }

    private enum JSONLDArticleSearch {
        case match([String: Any])
        case noMatch
        case invalidScript
    }

    private func getJSONLDMetadata(_ document: Document) -> JSONLDMetadata {
        // Mozilla enumerates all script elements and performs exact equality on
        // the type attribute. SwiftSoup's CSS attribute equality is deliberately
        // case-insensitive and trims its operand, so a selector here would accept
        // inputs that the pinned JavaScript authority rejects.
        guard let scripts = try? document.getElementsByTag("script") else { return JSONLDMetadata() }

        for script in scripts {
            guard script.attrOrEmpty("type") == "application/ld+json" else { continue }

            let content = strippingJSONLDCDATAMarkers(from: script.data())

            guard let data = content.data(using: .utf8) else { continue }
            guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else { continue }

            // If JSON-LD is an array, find an entry with a supported @type.
            var candidate: [String: Any]
            if let array = parsed as? [Any] {
                switch firstJSONLDArticle(in: array) {
                case let .match(found):
                    candidate = found
                case .noMatch, .invalidScript:
                    continue
                }
            } else if let dict = parsed as? [String: Any] {
                candidate = dict
            } else {
                continue
            }

            // Validate schema.org context.
            let contextMatches: Bool = {
                guard let ctx = candidate["@context"] else { return false }
                if let ctxStr = ctx as? String {
                    return schemaContextMatches(ctxStr)
                }
                if let ctxDict = ctx as? [String: Any],
                   let vocab = ctxDict["@vocab"] as? String {
                    return schemaContextMatches(vocab)
                }
                return false
            }()
            if !contextMatches { continue }

            // If no @type but has @graph, search graph for a supported @type.
            if !javaScriptJSONValueIsTruthy(candidate["@type"]),
               let graph = candidate["@graph"] as? [Any] {
                switch firstJSONLDArticle(in: graph) {
                case let .match(graphObject):
                    candidate = graphObject
                case .noMatch, .invalidScript:
                    continue
                }
            }

            guard javaScriptJSONValueIsTruthy(candidate["@type"]),
                  let typeValue = candidate["@type"] as? String,
                  matchesType(typeValue) else { continue }

            var meta = JSONLDMetadata()

            let name = candidate["name"] as? String
            let headline = candidate["headline"] as? String

            if let name, let headline, name != headline {
                let htmlTitle = getArticleTitle(document)
                let nameMatches = textSimilarity(textA: name, textB: htmlTitle) > 0.75
                let headlineMatches = textSimilarity(textA: headline, textB: htmlTitle) > 0.75
                if headlineMatches && !nameMatches {
                    meta.title = headline
                } else {
                    meta.title = name
                }
            } else if let name {
                meta.title = javaScriptTrim(name)
            } else if let headline {
                meta.title = javaScriptTrim(headline)
            }

            if let author = candidate["author"] {
                if let authorDict = author as? [String: Any],
                   let authorName = authorDict["name"] as? String {
                    meta.byline = javaScriptTrim(authorName)
                } else if let authorArray = author as? [Any],
                          let firstAuthor = authorArray.first as? [String: Any],
                          firstAuthor["name"] is String {
                    // This first-element gate is observable Mozilla behavior:
                    // malformed leading entries make the whole array ineligible,
                    // even when a later entry has a valid name.
                    let names = authorArray
                        .compactMap { ($0 as? [String: Any])?["name"] as? String }
                        .map(javaScriptTrim(_:))
                    if !names.isEmpty {
                        meta.byline = names.joined(separator: ", ")
                    }
                }
            }

            if let creator = candidate["creator"] {
                if let name = creator as? String {
                    meta.creatorNames = [name]
                } else if let creatorDictionary = creator as? [String: Any],
                          let name = creatorDictionary["name"] as? String {
                    meta.creatorNames = [name]
                } else if let creatorArray = creator as? [Any] {
                    meta.creatorNames = creatorArray.compactMap { value in
                        if let name = value as? String { return name }
                        return (value as? [String: Any])?["name"] as? String
                    }
                }
                meta.creatorNames = meta.creatorNames
                    .map(javaScriptTrim(_:))
                    .filter { !$0.isEmpty }
                    .reduce(into: []) { names, name in
                        if !names.contains(name) { names.append(name) }
                    }
            }

            if let description = candidate["description"] as? String {
                meta.excerpt = javaScriptTrim(description)
            }

            if let publisher = candidate["publisher"] as? [String: Any],
               let publisherName = publisher["name"] as? String {
                meta.siteName = javaScriptTrim(publisherName)
            }

            if let datePublished = candidate["datePublished"] as? String {
                meta.datePublished = javaScriptTrim(datePublished)
            }

            return meta
        }

        return JSONLDMetadata()
    }

    /// Mirrors the ordered `.find` callback in Mozilla `_getJSONLD`.
    /// JSON `null` throws on property access in JavaScript; a truthy non-string
    /// `@type` throws when `.match` is invoked. Either exception rejects the
    /// current script instead of allowing a later array entry to win.
    private func firstJSONLDArticle(in values: [Any]) -> JSONLDArticleSearch {
        for value in values {
            if value is NSNull {
                return .invalidScript
            }
            guard let dictionary = value as? [String: Any] else {
                // Property access on other JSON primitives and arrays yields an
                // absent @type, which is falsey and lets `.find` continue.
                continue
            }
            let type = dictionary["@type"]
            guard javaScriptJSONValueIsTruthy(type) else { continue }
            guard let typeString = type as? String else {
                return .invalidScript
            }
            if matchesType(typeString) {
                return .match(dictionary)
            }
        }
        return .noMatch
    }

    private func javaScriptJSONValueIsTruthy(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let boolean = value as? Bool { return boolean }
        if let string = value as? String { return !string.isEmpty }
        if let number = value as? NSNumber {
            let double = number.doubleValue
            return double != 0 && !double.isNaN
        }
        // Objects and arrays are truthy, including empty ones.
        return true
    }

    private func matchesType(_ typeValue: String) -> Bool {
        typeValue.hasPrefix("Article") ||
            MetadataParser.unanchoredJSONLDArticleTypes.contains(where: typeValue.contains(_:)) ||
            typeValue.hasSuffix("APIReference")
    }

    private func schemaContextMatches(_ value: String) -> Bool {
        value == "http://schema.org" ||
            value == "http://schema.org/" ||
            value == "https://schema.org" ||
            value == "https://schema.org/"
    }

    // MARK: - Helpers

    /// Returns the first metadata property match, mirroring Mozilla's global,
    /// unanchored `/\s*(namespace)\s*:\s*(field)\s*/gi` expression. A scalar
    /// scanner is intentional: Foundation regular expressions implement ICU
    /// `\s`, whose table differs observably from ECMAScript's.
    private func metaPropertyKey(in value: String) -> String? {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty else { return nil }

        for start in scalars.indices {
            var namespaceStart = start
            consumeJavaScriptWhitespace(in: scalars, index: &namespaceStart)

            for namespace in MetadataParser.propertyNamespaces {
                guard var index = endOfASCIICaseInsensitiveMatch(
                    namespace,
                    in: scalars,
                    at: namespaceStart
                ) else { continue }

                consumeJavaScriptWhitespace(in: scalars, index: &index)
                guard index < scalars.count, scalars[index].value == 0x3A else { continue }
                index += 1
                consumeJavaScriptWhitespace(in: scalars, index: &index)

                for field in MetadataParser.propertyFields {
                    guard var fieldEnd = endOfASCIICaseInsensitiveMatch(
                        field,
                        in: scalars,
                        at: index
                    ) else {
                        continue
                    }
                    consumeJavaScriptWhitespace(in: scalars, index: &fieldEnd)
                    return "\(namespace):\(field)"
                }
            }
        }
        return nil
    }

    /// Mirrors Mozilla's anchored metadata `name` pattern and its subsequent
    /// lowercasing, ECMAScript-whitespace removal, and dot-to-colon rewrite.
    private func metaNameKey(in value: String) -> String? {
        let scalars = Array(value.unicodeScalars)
        var index = 0
        consumeJavaScriptWhitespace(in: scalars, index: &index)
        let valueStart = index

        var fieldStart = valueStart
        for namespace in MetadataParser.nameNamespaces {
            guard var candidate = endOfASCIICaseInsensitiveMatch(namespace, in: scalars, at: valueStart) else {
                continue
            }
            consumeJavaScriptWhitespace(in: scalars, index: &candidate)
            guard candidate < scalars.count,
                  scalars[candidate].value == 0x2D ||
                    scalars[candidate].value == 0x2E ||
                    scalars[candidate].value == 0x3A else {
                continue
            }
            candidate += 1
            consumeJavaScriptWhitespace(in: scalars, index: &candidate)
            fieldStart = candidate
            break
        }

        guard var end = MetadataParser.nameFields.lazy.compactMap({
            self.endOfASCIICaseInsensitiveMatch($0, in: scalars, at: fieldStart)
        }).first else {
            return nil
        }
        consumeJavaScriptWhitespace(in: scalars, index: &end)
        guard end == scalars.count else { return nil }

        var normalized = String.UnicodeScalarView()
        normalized.reserveCapacity(scalars.count)
        for scalar in scalars where !javaScriptIsWhitespace(scalar) {
            let value = scalar.value
            if value >= 0x41, value <= 0x5A {
                normalized.append(Unicode.Scalar(value + 0x20)!)
            } else if value == 0x2E {
                normalized.append(Unicode.Scalar(0x3A)!)
            } else {
                normalized.append(scalar)
            }
        }
        return String(normalized)
    }

    private func consumeJavaScriptWhitespace(
        in scalars: [Unicode.Scalar],
        index: inout Int
    ) {
        while index < scalars.count, javaScriptIsWhitespace(scalars[index]) {
            index += 1
        }
    }

    private func endOfASCIICaseInsensitiveMatch(
        _ literal: String,
        in scalars: [Unicode.Scalar],
        at start: Int
    ) -> Int? {
        let expected = literal.unicodeScalars
        guard start + expected.count <= scalars.count else { return nil }
        var index = start
        for expectedScalar in expected {
            let actualValue = scalars[index].value
            let foldedActual = actualValue >= 0x41 && actualValue <= 0x5A
                ? actualValue + 0x20
                : actualValue
            guard foldedActual == expectedScalar.value else { return nil }
            index += 1
        }
        return index
    }

    /// Mirrors `/^\s*<!\[CDATA\[|\]\]>\s*$/g` without importing ICU's
    /// broader whitespace classification.
    private func strippingJSONLDCDATAMarkers(from source: String) -> String {
        let opening = Array("<![CDATA[".unicodeScalars)
        let closing = Array("]]>".unicodeScalars)
        var scalars = Array(source.unicodeScalars)

        var contentStart = 0
        consumeJavaScriptWhitespace(in: scalars, index: &contentStart)
        if scalars.dropFirst(contentStart).starts(with: opening) {
            scalars.removeFirst(contentStart + opening.count)
        }

        var contentEnd = scalars.count
        while contentEnd > 0, javaScriptIsWhitespace(scalars[contentEnd - 1]) {
            contentEnd -= 1
        }
        if contentEnd >= closing.count,
           scalars[(contentEnd - closing.count)..<contentEnd].elementsEqual(closing) {
            scalars.removeSubrange((contentEnd - closing.count)..<scalars.count)
        }

        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars)
        return String(result)
    }

    private func isUrl(_ string: String) -> Bool {
        // Mozilla calls `new URL(string)` without a base. WebURL mirrors that
        // WHATWG contract; Foundation.URL accepts incomplete URLs (for example
        // `http://`) and would incorrectly discard them as author metadata.
        WebURL(string) != nil
    }

    private func unescapeHtmlEntities(_ string: String?) -> String? {
        guard var string, !string.isEmpty else { return string }

        let htmlEscapeMap: [String: String] = [
            "quot": "\"",
            "amp": "&",
            "apos": "'",
            "lt": "<",
            "gt": ">"
        ]

        // Replace common named entities.
        string = replaceMatches(MetadataParser.namedEntityRegex, in: string) { match, nsString in
            guard match.numberOfRanges >= 2 else { return "" }
            let name = nsString.substring(with: match.range(at: 1))
            return htmlEscapeMap[name] ?? ""
        }

        // Replace numeric entities.
        let ns = string as NSString
        let matches = MetadataParser.numericEntityRegex.matches(in: string, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return string }

        var result = ""
        var lastLocation = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))

            let hexRange = match.range(at: 1)
            let decRange = match.range(at: 2)
            let numberString: String
            let radix: Int
            if hexRange.location != NSNotFound {
                numberString = ns.substring(with: hexRange)
                radix = 16
            } else {
                numberString = ns.substring(with: decRange)
                radix = 10
            }

            let parsed = UInt64(numberString, radix: radix) ?? 0
            var codePoint = parsed
            if codePoint == 0 || codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
                codePoint = 0xFFFD
            }
            if let scalar = UnicodeScalar(Int(codePoint)) {
                result.append(Character(scalar))
            } else {
                result.append("\u{FFFD}")
            }

            lastLocation = match.range.location + match.range.length
        }
        result += ns.substring(from: lastLocation)
        return result
    }

    private func replaceMatches(
        _ regex: NSRegularExpression,
        in string: String,
        replacement: (_ match: NSTextCheckingResult, _ nsString: NSString) -> String
    ) -> String {
        let ns = string as NSString
        let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return string }
        var result = ""
        var lastLocation = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: lastLocation, length: match.range.location - lastLocation))
            result += replacement(match, ns)
            lastLocation = match.range.location + match.range.length
        }
        result += ns.substring(from: lastLocation)
        return result
    }

    private func textSimilarity(textA: String, textB: String) -> Double {
        let tokensA = tokenize(textA.lowercased())
        let tokensB = tokenize(textB.lowercased())
        if tokensA.isEmpty || tokensB.isEmpty { return 0 }

        let uniqTokensB = tokensB.filter { !tokensA.contains($0) }
        let bJoined = tokensB.joined(separator: " ")
        let uniqJoined = uniqTokensB.joined(separator: " ")
        guard !bJoined.isEmpty else { return 0 }

        let distanceB = Double(javaScriptStringLength(uniqJoined)) /
            Double(javaScriptStringLength(bJoined))
        return 1.0 - distanceB
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            // JavaScript `/\W+/` without the Unicode flag defines `\w` as
            // exactly ASCII letters, digits, and underscore. Foundation's
            // CharacterSet.alphanumerics is broader and changes title choice
            // for non-Latin metadata.
            let value = scalar.value
            let isWord = (value >= 65 && value <= 90) ||
                (value >= 97 && value <= 122) ||
                (value >= 48 && value <= 57) ||
                value == 95
            if isWord {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Mirrors the HTML `document.title` getter before Readability applies
    /// JavaScript `trim()`: only HTML ASCII whitespace is stripped/collapsed.
    /// SwiftSoup's `Document.title()` uses Swift's broader whitespace model and
    /// would incorrectly discard U+0085, among other observable characters.
    private func htmlDocumentTitle(_ document: Document) -> String {
        guard let titleElements = try? document.getElementsByTag("title"),
              let titleElement = titleElements.first() else {
            return ""
        }

        let rawTitle = textContentPreservingWhitespace(of: titleElement)
        var result = String.UnicodeScalarView()
        result.reserveCapacity(rawTitle.unicodeScalars.count)
        var pendingSpace = false

        for scalar in rawTitle.unicodeScalars {
            switch scalar.value {
            case 0x0009, 0x000A, 0x000C, 0x000D, 0x0020:
                if !result.isEmpty { pendingSpace = true }
            default:
                if pendingSpace {
                    result.append(Unicode.Scalar(0x20)!)
                    pendingSpace = false
                }
                result.append(scalar)
            }
        }

        return String(result)
    }

    // MARK: - Title extraction (Readability.js _getArticleTitle)

    private func getArticleTitle(_ doc: Document) -> String {
        var curTitle = ""
        var origTitle = ""

        let title = javaScriptTrim(htmlDocumentTitle(doc))
        curTitle = title
        origTitle = title

        var titleHadHierarchicalSeparators = false

        func wordCount(_ str: String) -> Int {
            // JavaScript `split(/\s+/)` retains empty fields at either edge,
            // so its count is one plus the number of whitespace runs.
            var count = 1
            var inWhitespace = false
            for scalar in str.unicodeScalars {
                if javaScriptIsWhitespace(scalar) {
                    if !inWhitespace { count += 1 }
                    inWhitespace = true
                } else {
                    inWhitespace = false
                }
            }
            return count
        }

        let separators = Set<UInt32>([
            0x7C, 0x2D, 0x2013, 0x2014, 0x5C, 0x2F, 0x3E, 0xBB,
        ])
        let hierarchicalSeparators = Set<UInt32>([0x5C, 0x2F, 0x3E, 0xBB])

        func spacedSeparatorMatches(_ text: String, allowed: Set<UInt32>) -> [(start: Int, end: Int)] {
            let scalars = Array(text.unicodeScalars)
            guard scalars.count >= 3 else { return [] }
            var matches: [(start: Int, end: Int)] = []
            var index = 0
            while index + 2 < scalars.count {
                if javaScriptIsWhitespace(scalars[index]),
                   allowed.contains(scalars[index + 1].value),
                   javaScriptIsWhitespace(scalars[index + 2]) {
                    matches.append((index, index + 3))
                    index += 3 // JavaScript global regular expressions do not overlap.
                } else {
                    index += 1
                }
            }
            return matches
        }

        func string(from scalars: ArraySlice<Unicode.Scalar>) -> String {
            var result = String.UnicodeScalarView()
            result.append(contentsOf: scalars)
            return String(result)
        }

        func removingSpacedSeparators(from text: String) -> String {
            let scalars = Array(text.unicodeScalars)
            let matches = spacedSeparatorMatches(text, allowed: separators)
            guard !matches.isEmpty else { return text }
            var result = String.UnicodeScalarView()
            var cursor = 0
            for match in matches {
                result.append(contentsOf: scalars[cursor..<match.start])
                cursor = match.end
            }
            result.append(contentsOf: scalars[cursor..<scalars.count])
            return String(result)
        }

        let separatorMatches = spacedSeparatorMatches(curTitle, allowed: separators)
        if let lastSeparator = separatorMatches.last {
            titleHadHierarchicalSeparators = !spacedSeparatorMatches(
                curTitle,
                allowed: hierarchicalSeparators
            ).isEmpty
            let titleScalars = Array(origTitle.unicodeScalars)
            curTitle = string(from: titleScalars[..<lastSeparator.start])

            if wordCount(curTitle) < 3 {
                let titleScalars = Array(origTitle.unicodeScalars)
                if let firstIndex = titleScalars.firstIndex(where: {
                    separators.contains($0.value)
                }) {
                    curTitle = string(from: titleScalars[(firstIndex + 1)...])
                }
            }
        } else if curTitle.contains(": ") {
            let trimmedTitle = javaScriptTrim(curTitle)
            let headings = (try? doc.select("h1, h2").array()) ?? []
            var headingTexts = Set<String>()
            headingTexts.reserveCapacity(headings.count)
            for heading in headings {
                // DOM textContent preserves descendant whitespace. Element.text()
                // normalizes it and can manufacture an exact title match that
                // Mozilla would not observe.
                let text = textContentPreservingWhitespace(of: heading)
                let trimmedText = javaScriptTrim(text)
                if !trimmedText.isEmpty {
                    headingTexts.insert(trimmedText)
                }
            }
            let match = headingTexts.contains(trimmedTitle)

            if !match {
                if let idx = origTitle.lastIndex(of: ":") {
                    curTitle = String(origTitle[origTitle.index(after: idx)...])
                }
                if wordCount(curTitle) < 3, let idx = origTitle.firstIndex(of: ":") {
                    curTitle = String(origTitle[origTitle.index(after: idx)...])
                } else if let idx = origTitle.firstIndex(of: ":") {
                    let prefix = String(origTitle[..<idx])
                    if wordCount(prefix) > 5 {
                        curTitle = origTitle
                    }
                }
            }
        } else if isTextLengthAtLeast(curTitle, 151) || isTextLengthLessThan(curTitle, 15) {
            if let hOnes = try? doc.getElementsByTag("h1"), hOnes.count == 1, let first = hOnes.first() {
                curTitle = getInnerText(first, regEx: regEx)
            }
        }

        curTitle = javaScriptTrim(curTitle)
        curTitle = regEx.normalize(curTitle)

        let curTitleWordCount = wordCount(curTitle)
        if curTitleWordCount <= 4 {
            let origWithoutSeps = removingSpacedSeparators(from: origTitle)
            if !titleHadHierarchicalSeparators || curTitleWordCount != wordCount(origWithoutSeps) - 1 {
                curTitle = origTitle
            }
        }

        return curTitle
    }
}
