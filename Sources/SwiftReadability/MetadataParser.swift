import Foundation
import SwiftSoup

/// Port of Readability.js metadata extraction (JSON-LD + meta tags).
final class MetadataParser: ProcessorBase {
    private let regEx: RegExUtil
    private static let schemaDotOrgRegex = try! NSRegularExpression(
        pattern: "^https?\\:\\/\\/schema\\.org\\/?$",
        options: [.caseInsensitive]
    )
    private static let jsonLdArticleTypesRegex = try! NSRegularExpression(
        pattern: "^Article|AdvertiserContentArticle|NewsArticle|AnalysisNewsArticle|AskPublicNewsArticle|BackgroundNewsArticle|OpinionNewsArticle|ReportageNewsArticle|ReviewNewsArticle|Report|SatiricalArticle|ScholarlyArticle|MedicalScholarlyArticle|SocialMediaPosting|BlogPosting|LiveBlogPosting|DiscussionForumPosting|TechArticle|APIReference$",
        options: []
    )
    private static let metaPropertyPattern = try! NSRegularExpression(
        pattern: "\\s*(article|dc|dcterm|og|twitter)\\s*:\\s*(author|creator|description|published_time|title|site_name)\\s*",
        options: [.caseInsensitive]
    )
    private static let metaNamePattern = try! NSRegularExpression(
        pattern: "^\\s*(?:(dc|dcterm|og|twitter|parsely|weibo:(article|webpage))\\s*[-\\.:]\\s*)?(author|creator|pub-date|description|title|site_name)\\s*$",
        options: [.caseInsensitive]
    )
    private static let namedEntityRegex = try! NSRegularExpression(
        pattern: "&(quot|amp|apos|lt|gt);",
        options: []
    )
    private static let numericEntityRegex = try! NSRegularExpression(
        pattern: "&#(?:x([0-9a-f]+)|([0-9]+));",
        options: [.caseInsensitive]
    )
    private static let titleSeparatorRegexCI = try! NSRegularExpression(
        pattern: "\\s[\\|\\-–—\\\\/>»]\\s",
        options: [.caseInsensitive]
    )
    private static let titleSeparatorRegex = try! NSRegularExpression(
        pattern: "\\s[\\|\\-–—\\\\/>»]\\s",
        options: []
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
        let propertyPattern = MetadataParser.metaPropertyPattern
        let namePattern = MetadataParser.metaNamePattern

        guard let metas = try? document.select("meta") else { return values }
        for element in metas {
            let content = String(decoding: element.attrOrEmptyUTF8(ReadabilityUTF8Arrays.content), as: UTF8.self)
            if content.isEmpty { continue }

            let elementName = String(decoding: element.attrOrEmptyUTF8(ReadabilityUTF8Arrays.name), as: UTF8.self)
            let elementProperty = String(decoding: element.attrOrEmptyUTF8(ReadabilityUTF8Arrays.property), as: UTF8.self)

            var matchedProperty = false

            if !elementProperty.isEmpty {
                let range = NSRange(location: 0, length: elementProperty.utf16.count)
                if let match = propertyPattern.firstMatch(in: elementProperty, options: [], range: range) {
                    let start = elementProperty.index(elementProperty.startIndex, offsetBy: match.range.location)
                    let end = elementProperty.index(start, offsetBy: match.range.length)
                    let key = elementProperty[start..<end]
                        .lowercased()
                        .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                    values[key] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    matchedProperty = true
                }
            }

            if matchedProperty { continue }

            if !elementName.isEmpty {
                let range = NSRange(location: 0, length: elementName.utf16.count)
                if namePattern.firstMatch(in: elementName, options: [], range: range) != nil {
                    let key = elementName
                        .lowercased()
                        .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                        .replacingOccurrences(of: ".", with: ":")
                    values[key] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return values
    }

    // MARK: - JSON-LD

    private struct JSONLDMetadata {
        var title: String?
        var byline: String?
        var excerpt: String?
        var siteName: String?
        var datePublished: String?
    }

    private func getJSONLDMetadata(_ document: Document) -> JSONLDMetadata {
        guard let scripts = try? document.select("script[type=application/ld+json]") else { return JSONLDMetadata() }

        func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
            regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil
        }

        for script in scripts {
            var content = script.data()
            content = content.replacingOccurrences(of: "^\\s*<!\\[CDATA\\[", with: "", options: .regularExpression)
            content = content.replacingOccurrences(of: "\\]\\]>\\s*$", with: "", options: .regularExpression)

            guard let data = content.data(using: .utf8) else { continue }
            guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else { continue }

            // If JSON-LD is an array, find an entry with a supported @type.
            var candidate: [String: Any]
            if let array = parsed as? [Any] {
                guard let found = array.compactMap({ $0 as? [String: Any] }).first(where: { dict in
                    let type = dict["@type"] as? String
                    return type.map(matchesType) ?? false
                }) else {
                    continue
                }
                candidate = found
            } else if let dict = parsed as? [String: Any] {
                candidate = dict
            } else {
                continue
            }

            // Validate schema.org context.
            let contextMatches: Bool = {
                guard let ctx = candidate["@context"] else { return false }
                if let ctxStr = ctx as? String {
                    return matches(MetadataParser.schemaDotOrgRegex, ctxStr)
                }
                if let ctxDict = ctx as? [String: Any],
                   let vocab = ctxDict["@vocab"] as? String {
                    return matches(MetadataParser.schemaDotOrgRegex, vocab)
                }
                return false
            }()
            if !contextMatches { continue }

            // If no @type but has @graph, search graph for a supported @type.
            if candidate["@type"] == nil, let graph = candidate["@graph"] as? [Any] {
                if let graphObj = graph.compactMap({ $0 as? [String: Any] }).first(where: { dict in
                    let type = dict["@type"] as? String
                    return type.map(matchesType) ?? false
                }) {
                    candidate = graphObj
                }
            }

            guard let typeValue = candidate["@type"] as? String, matchesType(typeValue) else { continue }

            var meta = JSONLDMetadata()

            let name = candidate["name"] as? String
            let headline = candidate["headline"] as? String

            if let name, let headline, name != headline {
                let htmlTitle = getArticleTitle(document)
                let nameMatches = textSimilarity(textA: name, textB: htmlTitle) > 0.75
                let headlineMatches = textSimilarity(textA: headline, textB: htmlTitle) > 0.75
                if headlineMatches && !nameMatches {
                    meta.title = headline.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    meta.title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if let name {
                meta.title = name.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let headline {
                meta.title = headline.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let author = candidate["author"] {
                if let authorDict = author as? [String: Any],
                   let authorName = authorDict["name"] as? String {
                    meta.byline = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let authorArray = author as? [Any] {
                    let names = authorArray
                        .compactMap { ($0 as? [String: Any])?["name"] as? String }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if !names.isEmpty {
                        meta.byline = names.joined(separator: ", ")
                    }
                }
            }

            if let description = candidate["description"] as? String {
                meta.excerpt = description.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let publisher = candidate["publisher"] as? [String: Any],
               let publisherName = publisher["name"] as? String {
                meta.siteName = publisherName.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let datePublished = candidate["datePublished"] as? String {
                meta.datePublished = datePublished.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return meta
        }

        return JSONLDMetadata()
    }

    private func matchesType(_ typeValue: String) -> Bool {
        return MetadataParser.jsonLdArticleTypesRegex.firstMatch(
            in: typeValue,
            options: [],
            range: NSRange(location: 0, length: typeValue.utf16.count)
        ) != nil
    }

    // MARK: - Helpers

    private func isUrl(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil
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

        let distanceB = Double(uniqJoined.count) / Double(bJoined.count)
        return 1.0 - distanceB
    }

    private func tokenize(_ text: String) -> [String] {
        // JS: .split(/\W+/).filter(Boolean), where \w is ASCII [A-Za-z0-9_]
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isWord =
                (v >= 48 && v <= 57) || // 0-9
                (v >= 65 && v <= 90) || // A-Z
                (v >= 97 && v <= 122) || // a-z
                (v == 95) // _
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

    // MARK: - Title extraction (Readability.js _getArticleTitle)

    private func getArticleTitle(_ doc: Document) -> String {
        var curTitle = ""
        var origTitle = ""

        if let title = try? doc.title().trimmingCharacters(in: .whitespacesAndNewlines) {
            curTitle = title
            origTitle = title
        }

        var titleHadHierarchicalSeparators = false

        func wordCount(_ str: String) -> Int {
            str.split(whereSeparator: { $0.isWhitespace }).count
        }

        let separators: [Character] = ["|", "-", "–", "—", "\\", "/", ">", "»"]
        func containsSpacedSeparator(_ text: String) -> Bool {
            for sep in separators {
                let pattern = "\\s\\" + String(sep) + "\\s"
                if text.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            }
            return false
        }

        if containsSpacedSeparator(curTitle) {
            titleHadHierarchicalSeparators = curTitle.range(of: "\\s[\\\\/>»]\\s", options: .regularExpression) != nil
            let ns = origTitle as NSString
            let matches = MetadataParser.titleSeparatorRegexCI.matches(in: origTitle, options: [], range: NSRange(location: 0, length: ns.length))
            if let last = matches.last {
                curTitle = ns.substring(to: last.range.location)
            }

            if wordCount(curTitle) < 3 {
                if let firstIndex = origTitle.firstIndex(where: { separators.contains($0) }) {
                    curTitle = String(origTitle[origTitle.index(after: firstIndex)...])
                }
            }
        } else if curTitle.contains(": ") {
            let trimmedTitle = curTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let headings = (try? doc.select("h1, h2").array()) ?? []
            var headingTexts = Set<String>()
            headingTexts.reserveCapacity(headings.count)
            for heading in headings {
                let text = ((try? heading.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    headingTexts.insert(text)
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

        curTitle = curTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        curTitle = regEx.normalize(curTitle)

        let curTitleWordCount = wordCount(curTitle)
        if curTitleWordCount <= 4 {
            let origWithoutSeps = MetadataParser.titleSeparatorRegex.stringByReplacingMatches(in: origTitle, options: [], range: NSRange(location: 0, length: origTitle.utf16.count), withTemplate: "")
            if !titleHadHierarchicalSeparators || curTitleWordCount != wordCount(origWithoutSeps) - 1 {
                curTitle = origTitle
            }
        }

        return curTitle
    }
}
