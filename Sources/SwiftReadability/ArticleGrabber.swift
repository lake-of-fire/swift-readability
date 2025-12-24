import Foundation
import SwiftSoup

/// Core content-extraction algorithm (ported from Readability4J / Mozilla Readability).
final class ArticleGrabber: ProcessorBase {
    // Element tags to score by default.
    private let defaultTagsToScore: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.section,
        ReadabilityUTF8Arrays.h2,
        ReadabilityUTF8Arrays.h3,
        ReadabilityUTF8Arrays.h4,
        ReadabilityUTF8Arrays.h5,
        ReadabilityUTF8Arrays.h6,
        ReadabilityUTF8Arrays.p,
        ReadabilityUTF8Arrays.td,
        ReadabilityUTF8Arrays.pre
    ]
    private let divToPElems: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.blockquote,
        ReadabilityUTF8Arrays.dl,
        ReadabilityUTF8Arrays.div,
        ReadabilityUTF8Arrays.img,
        ReadabilityUTF8Arrays.ol,
        ReadabilityUTF8Arrays.p,
        ReadabilityUTF8Arrays.pre,
        ReadabilityUTF8Arrays.table,
        ReadabilityUTF8Arrays.ul
    ]
    private let divToPElemsStrings: [String] = [
        "blockquote",
        "dl",
        "div",
        "img",
        "ol",
        "p",
        "pre",
        "table",
        "ul"
    ]
    private let blockTagsForTextLength: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.article,
        ReadabilityUTF8Arrays.blockquote,
        ReadabilityUTF8Arrays.dd,
        ReadabilityUTF8Arrays.dl,
        ReadabilityUTF8Arrays.div,
        ReadabilityUTF8Arrays.dt,
        ReadabilityUTF8Arrays.figure,
        ReadabilityUTF8Arrays.form,
        ReadabilityUTF8Arrays.h1,
        ReadabilityUTF8Arrays.h2,
        ReadabilityUTF8Arrays.h3,
        ReadabilityUTF8Arrays.h4,
        ReadabilityUTF8Arrays.h5,
        ReadabilityUTF8Arrays.h6,
        ReadabilityUTF8Arrays.header,
        ReadabilityUTF8Arrays.li,
        ReadabilityUTF8Arrays.ol,
        ReadabilityUTF8Arrays.p,
        ReadabilityUTF8Arrays.pre,
        ReadabilityUTF8Arrays.section,
        ReadabilityUTF8Arrays.table,
        ReadabilityUTF8Arrays.tbody,
        ReadabilityUTF8Arrays.td,
        ReadabilityUTF8Arrays.tfoot,
        ReadabilityUTF8Arrays.th,
        ReadabilityUTF8Arrays.thead,
        ReadabilityUTF8Arrays.tr,
        ReadabilityUTF8Arrays.ul
    ]
    private let phrasingElems: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.abbr,
        ReadabilityUTF8Arrays.audio,
        ReadabilityUTF8Arrays.b,
        ReadabilityUTF8Arrays.bdo,
        ReadabilityUTF8Arrays.br,
        ReadabilityUTF8Arrays.button,
        ReadabilityUTF8Arrays.cite,
        ReadabilityUTF8Arrays.code,
        ReadabilityUTF8Arrays.data,
        ReadabilityUTF8Arrays.datalist,
        ReadabilityUTF8Arrays.dfn,
        ReadabilityUTF8Arrays.em,
        ReadabilityUTF8Arrays.embed,
        ReadabilityUTF8Arrays.i,
        ReadabilityUTF8Arrays.img,
        ReadabilityUTF8Arrays.input,
        ReadabilityUTF8Arrays.kbd,
        ReadabilityUTF8Arrays.label,
        ReadabilityUTF8Arrays.mark,
        ReadabilityUTF8Arrays.math,
        ReadabilityUTF8Arrays.meter,
        ReadabilityUTF8Arrays.noscript,
        ReadabilityUTF8Arrays.object,
        ReadabilityUTF8Arrays.output,
        ReadabilityUTF8Arrays.progress,
        ReadabilityUTF8Arrays.q,
        ReadabilityUTF8Arrays.ruby,
        ReadabilityUTF8Arrays.samp,
        ReadabilityUTF8Arrays.script,
        ReadabilityUTF8Arrays.select,
        ReadabilityUTF8Arrays.small,
        ReadabilityUTF8Arrays.span,
        ReadabilityUTF8Arrays.strong,
        ReadabilityUTF8Arrays.sub,
        ReadabilityUTF8Arrays.sup,
        ReadabilityUTF8Arrays.textarea,
        ReadabilityUTF8Arrays.time,
        ReadabilityUTF8Arrays.var_,
        ReadabilityUTF8Arrays.wbr
    ]
    private let alterToDivExceptions: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.div,
        ReadabilityUTF8Arrays.article,
        ReadabilityUTF8Arrays.section,
        ReadabilityUTF8Arrays.p,
        ReadabilityUTF8Arrays.ol,
        ReadabilityUTF8Arrays.ul
    ]
    private let presentationalAttributes: [[UInt8]] = [
        ReadabilityUTF8Arrays.align,
        ReadabilityUTF8Arrays.background,
        ReadabilityUTF8Arrays.bgcolor,
        ReadabilityUTF8Arrays.border,
        ReadabilityUTF8Arrays.cellpadding,
        ReadabilityUTF8Arrays.cellspacing,
        ReadabilityUTF8Arrays.frame,
        ReadabilityUTF8Arrays.hspace,
        ReadabilityUTF8Arrays.rules,
        ReadabilityUTF8Arrays.style,
        ReadabilityUTF8Arrays.valign,
        ReadabilityUTF8Arrays.vspace
    ]
    private let deprecatedSizeAttributeElems: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.table,
        ReadabilityUTF8Arrays.th,
        ReadabilityUTF8Arrays.td,
        ReadabilityUTF8Arrays.hr,
        ReadabilityUTF8Arrays.pre
    ]
    private let embeddedNodes: Set<[UInt8]> = [
        ReadabilityUTF8Arrays.object,
        ReadabilityUTF8Arrays.embed,
        ReadabilityUTF8Arrays.iframe
    ]
    private let dataTableDescendants: Set<String> = ["col", "colgroup", "tfoot", "thead", "th"]
    private let unlikelyRoles: [[UInt8]] = [
        "menu".utf8Array,
        "menubar".utf8Array,
        "complementary".utf8Array,
        "navigation".utf8Array,
        "alert".utf8Array,
        "alertdialog".utf8Array,
        "dialog".utf8Array
    ]
    private static let b64DataUrlRegex = try! NSRegularExpression(
        pattern: "^data:\\s*([^\\s;,]+)\\s*;\\s*base64\\s*,",
        options: [.caseInsensitive]
    )

    private let options: ReadabilityOptions
    private let regEx: RegExUtil

    private(set) var articleByline: String?
    private(set) var articleDir: String?

    private let nbTopCandidates: Int
    private let charThreshold: Int
    private let linkDensityModifier: Double

    // Dictionaries keyed by Element identity
    private var readabilityObjects: [ObjectIdentifier: ReadabilityObject] = [:]
    private var readabilityDataTable: [ObjectIdentifier: Bool] = [:]
    private final class LinkDensityCache {
        var map: [ObjectIdentifier: Double] = [:]
        var textMutationVersion: Int = -1
    }

    init(options: ReadabilityOptions, regEx: RegExUtil = RegExUtil()) {
        self.options = options
        self.regEx = regEx
        self.nbTopCandidates = options.nbTopCandidates
        self.charThreshold = options.charThreshold
        self.linkDensityModifier = options.linkDensityModifier
    }

    func grabArticle(doc: Document,
                     metadata: ArticleMetadata,
                     options: ArticleGrabberOptions = ArticleGrabberOptions(),
                     pageElement: Element? = nil,
                     timing: TimingSink? = nil) -> Element? {
        var options = options
        let isPaging = pageElement != nil
        let page = pageElement ?? doc.body()

        guard let page else { return nil }

        let outputSettings = doc.outputSettings()
        let originalPrettyPrint = outputSettings.prettyPrint()
        outputSettings.prettyPrint(pretty: false)
        let pageCacheHtml = (try? page.html()) ?? ""
        outputSettings.prettyPrint(pretty: originalPrettyPrint)

        var attempts: [(Element, Int)] = []
        var textLengthCache: [ObjectIdentifier: Int] = [:]
        let linkDensityCache = LinkDensityCache()
        while true {
            let elementsToScore: [Element]
            if let timing {
                elementsToScore = timing.measure("grab.prepareNodes") {
                    prepareNodes(
                        doc: doc,
                        metadata: metadata,
                        options: options,
                        timing: timing,
                        textLengthCache: &textLengthCache,
                        linkDensityCache: linkDensityCache
                    )
                }
            } else {
                elementsToScore = prepareNodes(
                    doc: doc,
                    metadata: metadata,
                    options: options,
                    textLengthCache: &textLengthCache,
                    linkDensityCache: linkDensityCache
                )
            }

            let candidates: [Element]
            if let timing {
                candidates = timing.measure("grab.scoreElements") {
                    scoreElements(
                        elementsToScore: elementsToScore,
                        options: options,
                        timing: timing,
                        textLengthCache: &textLengthCache
                    )
                }
            } else {
                candidates = scoreElements(
                    elementsToScore: elementsToScore,
                    options: options,
                    textLengthCache: &textLengthCache
                )
            }

            let (topCandidate, created): (Element, Bool)
            if let timing {
                (topCandidate, created) = timing.measure("grab.getTopCandidate") {
                    getTopCandidate(
                        page: page,
                        candidates: candidates,
                        options: options,
                        timing: timing,
                        textLengthCache: &textLengthCache,
                        linkDensityCache: linkDensityCache
                    )
                }
            } else {
                (topCandidate, created) = getTopCandidate(
                    page: page,
                    candidates: candidates,
                    options: options,
                    textLengthCache: &textLengthCache,
                    linkDensityCache: linkDensityCache
                )
            }

            let articleContent: Element
            if let timing {
                articleContent = timing.measure("grab.createArticleContent") {
                    createArticleContent(
                        doc: doc,
                        topCandidate: topCandidate,
                        isPaging: isPaging,
                        linkDensityCache: linkDensityCache
                    )
                }
            } else {
                articleContent = createArticleContent(
                    doc: doc,
                    topCandidate: topCandidate,
                    isPaging: isPaging,
                    linkDensityCache: linkDensityCache
                )
            }

            if let timing {
                _ = timing.measure("grab.prepArticle") {
                    prepArticle(
                        articleContent: articleContent,
                        options: options,
                        metadata: metadata,
                        timing: timing,
                        linkDensityCache: linkDensityCache
                    )
                }
            } else {
                prepArticle(
                    articleContent: articleContent,
                    options: options,
                    metadata: metadata,
                        linkDensityCache: linkDensityCache
                )
            }

            if created {
                _ = try? topCandidate.attr(ReadabilityUTF8Arrays.id, ReadabilityUTF8Arrays.readabilityPage1)
                _ = try? topCandidate.addClass("page")
            } else {
                guard let div = try? doc.createElement("div") else { return nil }
                _ = try? div.attr(ReadabilityUTF8Arrays.id, ReadabilityUTF8Arrays.readabilityPage1)
                _ = try? div.addClass("page")
                for child in Array(articleContent.getChildNodes()) {
                    _ = try? child.remove()
                    _ = try? div.appendChild(child)
                }
                _ = try? articleContent.appendChild(div)
            }

            let textLength = getInnerText(articleContent, regEx: regEx, normalizeSpaces: true).count
            if textLength < self.charThreshold {
                _ = try? page.html(pageCacheHtml)
                // Restoring the page HTML replaces the DOM nodes. Any per-node state we keep in
                // dictionaries must be cleared between attempts to avoid stale lookups (and pointer reuse).
                readabilityObjects.removeAll(keepingCapacity: true)
                readabilityDataTable.removeAll(keepingCapacity: true)

                if options.stripUnlikelyCandidates {
                    options.stripUnlikelyCandidates = false
                    attempts.append((articleContent, textLength))
                    continue
                } else if options.weightClasses {
                    options.weightClasses = false
                    attempts.append((articleContent, textLength))
                    continue
                } else if options.cleanConditionally {
                    options.cleanConditionally = false
                    attempts.append((articleContent, textLength))
                    continue
                } else {
                    attempts.append((articleContent, textLength))
                    attempts.sort { $0.1 > $1.1 }
                    guard let best = attempts.first, best.1 > 0 else { return nil }
                    return best.0
                }
            }

            if let timing {
                _ = timing.measure("grab.getTextDirection") {
                    getTextDirection(topCandidate: topCandidate, doc: doc)
                }
            } else {
                getTextDirection(topCandidate: topCandidate, doc: doc)
            }
            return articleContent
        }
    }

    // MARK: First step: prepare nodes
    private func prepareNodes(doc: Document,
                              metadata: ArticleMetadata,
                              options: ArticleGrabberOptions,
                              timing: TimingSink? = nil,
                              textLengthCache: inout [ObjectIdentifier: Int],
                              linkDensityCache: LinkDensityCache) -> [Element] {
        var elementsToScore: [Element] = []
        var node: Element? = doc.body()
        var shouldRemoveTitleHeader = true
        let articleTitle = (metadata.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        while let current = node {
            let currentTagName = current.tagNameUTF8()
            let matchString = current.classNameSafe() + " " + current.idSafe()

            let isVisible = timing?.measure("grab.prepareNodes.visibility") {
                isProbablyVisible(current)
            } ?? isProbablyVisible(current)
            if !isVisible {
                node = removeAndGetNext(node: current, reason: "hidden")
                continue
            }

            // aria-modal + role=dialog content isn't visible to the user.
            let ariaModal = current.attrOrEmptyUTF8(ReadabilityUTF8Arrays.ariaModal)
            let role = current.attrOrEmptyUTF8(ReadabilityUTF8Arrays.role)
            if ariaModal.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.true_),
               role.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.dialog) {
                node = removeAndGetNext(node: current, reason: "aria-modal dialog")
                continue
            }

            let isByline = timing?.measure("grab.prepareNodes.byline") {
                checkByline(node: current, matchString: matchString, metadata: metadata)
            } ?? checkByline(node: current, matchString: matchString, metadata: metadata)
            if isByline {
                node = removeAndGetNext(node: current, reason: "byline")
                continue
            }

            let headerDup = timing?.measure("grab.prepareNodes.headerDup") {
                shouldRemoveTitleHeader &&
                !articleTitle.isEmpty &&
                headerDuplicatesTitle(node: current, articleTitle: articleTitle)
            } ?? (shouldRemoveTitleHeader &&
                  !articleTitle.isEmpty &&
                  headerDuplicatesTitle(node: current, articleTitle: articleTitle))
            if headerDup {
                shouldRemoveTitleHeader = false
                node = removeAndGetNext(node: current, reason: "header duplicates title")
                continue
            }

            if options.stripUnlikelyCandidates {
                let isUnlikely = timing?.measure("grab.prepareNodes.unlikely") {
                    guard currentTagName != ReadabilityUTF8Arrays.body,
                          currentTagName != ReadabilityUTF8Arrays.a else { return false }
                    if !regEx.isUnlikelyCandidate(matchString) { return false }
                    if regEx.okMaybeItsACandidate(matchString) { return false }
                    if hasAncestorTag(node: current, tagName: ReadabilityUTF8Arrays.table) { return false }
                    if hasAncestorTag(node: current, tagName: ReadabilityUTF8Arrays.code) { return false }
                    return true
                } ?? {
                    guard currentTagName != ReadabilityUTF8Arrays.body,
                          currentTagName != ReadabilityUTF8Arrays.a else { return false }
                    if !regEx.isUnlikelyCandidate(matchString) { return false }
                    if regEx.okMaybeItsACandidate(matchString) { return false }
                    if hasAncestorTag(node: current, tagName: ReadabilityUTF8Arrays.table) { return false }
                    if hasAncestorTag(node: current, tagName: ReadabilityUTF8Arrays.code) { return false }
                    return true
                }()
                if isUnlikely {
                    node = removeAndGetNext(node: current, reason: "Removing unlikely candidate")
                    continue
                }

                if unlikelyRoles.contains(where: { role.equalsIgnoreCaseASCII($0) }) {
                    let roleString = String(decoding: role, as: UTF8.self)
                    node = removeAndGetNext(node: current, reason: "unlikely role " + roleString)
                    continue
                }
            }

            let noContent = timing?.measure("grab.prepareNodes.noContent") {
                (currentTagName == ReadabilityUTF8Arrays.div ||
                currentTagName == ReadabilityUTF8Arrays.section ||
                currentTagName == ReadabilityUTF8Arrays.header ||
                currentTagName == ReadabilityUTF8Arrays.h1 ||
                currentTagName == ReadabilityUTF8Arrays.h2 ||
                currentTagName == ReadabilityUTF8Arrays.h3 ||
                currentTagName == ReadabilityUTF8Arrays.h4 ||
                currentTagName == ReadabilityUTF8Arrays.h5 ||
                currentTagName == ReadabilityUTF8Arrays.h6) &&
                isElementWithoutContent(node: current)
            } ?? ((currentTagName == ReadabilityUTF8Arrays.div ||
                    currentTagName == ReadabilityUTF8Arrays.section ||
                    currentTagName == ReadabilityUTF8Arrays.header ||
                    currentTagName == ReadabilityUTF8Arrays.h1 ||
                    currentTagName == ReadabilityUTF8Arrays.h2 ||
                    currentTagName == ReadabilityUTF8Arrays.h3 ||
                    currentTagName == ReadabilityUTF8Arrays.h4 ||
                    currentTagName == ReadabilityUTF8Arrays.h5 ||
                    currentTagName == ReadabilityUTF8Arrays.h6) &&
                    isElementWithoutContent(node: current))
            if noContent {
                node = removeAndGetNext(node: current, reason: "node without content")
                continue
            }

            if defaultTagsToScore.contains(currentTagName) {
                elementsToScore.append(current)
            }

            if currentTagName == ReadabilityUTF8Arrays.div {
                if let timing {
                    _ = timing.measure("grab.prepareNodes.phrasing") {
                        putPhrasingContentIntoParagraphs(div: current)
                    }
                } else {
                    putPhrasingContentIntoParagraphs(div: current)
                }

                let hasSingleP = timing?.measure("grab.prepareNodes.hasSingleP") {
                    hasSinglePInsideElement(element: current)
                } ?? hasSinglePInsideElement(element: current)
                if hasSingleP {
                    let currentTextLength = textLength(
                        of: current,
                        normalizeSpaces: true,
                        cache: &textLengthCache
                    )
                    let linkDensity = getLinkDensity(
                        element: current,
                        textLength: currentTextLength,
                        timing: timing,
                        cache: linkDensityCache
                    )
                    if linkDensity < 0.25 {
                        let newNode = current.child(0)
                        _ = try? current.replaceWith(newNode)
                        elementsToScore.append(newNode)
                        node = getNextNode(node: newNode)
                        continue
                    }
                } else if !hasChildBlockElement(element: current) {
                    setNodeTag(node: current, tagName: ReadabilityUTF8Arrays.p)
                    elementsToScore.append(current)
                }
            }

            node = getNextNode(node: current)
        }
        return elementsToScore
    }

    private func putPhrasingContentIntoParagraphs(div: Element) {
        guard let doc = div.ownerDocument() else { return }
        var phrasingCache: [ObjectIdentifier: Bool] = [:]

        var childNode: Node? = div.getChildNodes().first
        while let child = childNode {
            let nextSibling = child.nextSibling()

            if isPhrasingContent(child, cache: &phrasingCache) {
                let insertionIndex = child.siblingIndex
                var fragment: [Node] = []

                var node: Node? = child
                var nextAfterFragment: Node? = nextSibling
                while let current = node, isPhrasingContent(current, cache: &phrasingCache) {
                    let next = current.nextSibling()
                    fragment.append(current)
                    _ = try? current.remove()
                    node = next
                    nextAfterFragment = next
                }

                while let first = fragment.first, isWhitespace(first) {
                    fragment.removeFirst()
                }
                while let last = fragment.last, isWhitespace(last) {
                    fragment.removeLast()
                }

                if !fragment.isEmpty, let p = try? doc.createElement("p") {
                    for n in fragment {
                        _ = try? p.appendChild(n)
                    }
                    _ = try? div.insertChildren(insertionIndex, [p])
                }

                childNode = nextAfterFragment
            } else {
                childNode = nextSibling
            }
        }
    }

    private func isWhitespace(_ node: Node) -> Bool {
        if let text = node as? TextNode {
            return text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let element = node as? Element {
            return element.tagNameUTF8() == ReadabilityUTF8Arrays.br
        }
        return false
    }

    private func isPhrasingContent(_ node: Node, cache: inout [ObjectIdentifier: Bool]) -> Bool {
        if node is TextNode {
            return true
        }
        guard let element = node as? Element else { return false }
        let key = ObjectIdentifier(element)
        if let cached = cache[key] { return cached }
        let tagName = element.tagNameUTF8()
        if phrasingElems.contains(tagName) {
            cache[key] = true
            return true
        }
        if tagName == ReadabilityUTF8Arrays.a ||
            tagName == ReadabilityUTF8Arrays.del ||
            tagName == ReadabilityUTF8Arrays.ins {
            let value = element.getChildNodes().allSatisfy { child in
                isPhrasingContent(child, cache: &cache)
            }
            cache[key] = value
            return value
        }
        cache[key] = false
        return false
    }

    private let displayNonePattern = try! NSRegularExpression(pattern: "display\\s*:\\s*none", options: [.caseInsensitive])
    private let visibilityHiddenPattern = try! NSRegularExpression(pattern: "visibility\\s*:\\s*hidden", options: [.caseInsensitive])
    private let commasPattern = try! NSRegularExpression(pattern: "[\\u002C\\u060C\\uFE50\\uFE10\\uFE11\\u2E41\\u2E34\\u2E32\\uFF0C]", options: [])
    private let adWordsPattern = try! NSRegularExpression(
        pattern: #"^(ad(vertising|vertisement)?|pub(licité)?|werb(ung)?|广告|Реклама|Anuncio)$"#,
        options: [.caseInsensitive]
    )
    private let loadingWordsPattern = try! NSRegularExpression(
        pattern: #"^((loading|正在加载|Загрузка|chargement|cargando)(…|\.\.\.)?)$"#,
        options: [.caseInsensitive]
    )

    private func isProbablyVisible(_ node: Element) -> Bool {
        let style = String(decoding: node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.style), as: UTF8.self)
        if displayNonePattern.firstMatch(in: style, options: [], range: NSRange(location: 0, length: style.utf16.count)) != nil {
            return false
        }
        if visibilityHiddenPattern.firstMatch(in: style, options: [], range: NSRange(location: 0, length: style.utf16.count)) != nil {
            return false
        }
        if node.hasAttr(ReadabilityUTF8Arrays.hidden) {
            return false
        }
        if node.hasAttr(ReadabilityUTF8Arrays.ariaHidden),
           node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.ariaHidden) == ReadabilityUTF8Arrays.true_ {
            let className = node.classNameSafe()
            if !className.contains("fallback-image") {
                return false
            }
        }
        return true
    }

    private func checkByline(node: Element, matchString: String, metadata: ArticleMetadata) -> Bool {
        if articleByline != nil { return false }
        if let metaByline = metadata.byline, !metaByline.isEmpty { return false }

        if isValidByline(node: node, matchString: matchString) {
            if let nameNode = try? node.select("[itemprop*=name]").first() {
                articleByline = textContentPreservingWhitespace(of: nameNode)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                articleByline = textContentPreservingWhitespace(of: node)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return true
        }
        return false
    }

    private func isValidByline(node: Element, matchString: String) -> Bool {
        let rel = String(decoding: node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.rel), as: UTF8.self)
        let itemprop = String(decoding: node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.itemprop), as: UTF8.self)
        let bylineText = textContentPreservingWhitespace(of: node)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bylineUtf8Length = bylineText.utf8.count
        if bylineUtf8Length == 0 { return false }
        let bylineLength = bylineUtf8Length < 100 ? bylineUtf8Length : bylineText.count

        return (
            rel == "author" ||
            (itemprop.contains("author")) ||
            regEx.isByline(matchString)
        ) && bylineLength > 0 && bylineLength < 100
    }

    private func headerDuplicatesTitle(node: Element, articleTitle: String) -> Bool {
        let tag = node.tagNameUTF8()
        if tag != ReadabilityUTF8Arrays.h1 && tag != ReadabilityUTF8Arrays.h2 { return false }
        let heading = getInnerText(node, normalizeSpaces: false)
        return textSimilarity(articleTitle, heading) > 0.75
    }

    private func textSimilarity(_ textA: String, _ textB: String) -> Double {
        // Port of Readability.js _textSimilarity.
        func tokenize(_ text: String) -> [String] {
            var tokens: [String] = []
            var current = ""
            current.reserveCapacity(text.count)

            for scalar in text.unicodeScalars {
                let v = scalar.value
                let isWordChar =
                    (v >= 48 && v <= 57) || // 0-9
                    (v >= 65 && v <= 90) || // A-Z
                    (v >= 97 && v <= 122) || // a-z
                    v == 95 // _
                if isWordChar {
                    current.append(Character(scalar))
                } else if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { tokens.append(current) }
            return tokens
        }

        let tokensA = tokenize(textA.lowercased()).filter { !$0.isEmpty }
        let tokensB = tokenize(textB.lowercased()).filter { !$0.isEmpty }
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0 }

        let tokenSetA = Set(tokensA)
        let uniqTokensB = tokensB.filter { !tokenSetA.contains($0) }
        let joinedAllB = tokensB.joined(separator: " ")
        let joinedUniqB = uniqTokensB.joined(separator: " ")
        guard !joinedAllB.isEmpty else { return 0 }
        let distanceB = Double(joinedUniqB.utf16.count) / Double(joinedAllB.utf16.count)
        return 1 - distanceB
    }

    private func textContentPreservingWhitespace(of node: Node) -> String {
        if let text = node as? TextNode {
            return text.getWholeText()
        }
        if let element = node as? Element {
            return collectTextPreservingWhitespace(from: element)
        }
        return ""
    }

    private func collectTextPreservingWhitespace(from element: Element) -> String {
        var output: [String] = []
        output.reserveCapacity(8)
        var stack = Array(element.getChildNodes().reversed())
        while let node = stack.popLast() {
            if let text = node as? TextNode {
                output.append(text.getWholeText())
            } else if let data = node as? DataNode {
                output.append(data.getWholeData())
            } else if let el = node as? Element {
                let children = el.getChildNodes()
                if !children.isEmpty {
                    stack.append(contentsOf: children.reversed())
                }
            }
        }
        if output.isEmpty { return "" }
        return output.joined()
    }

    private func isElementWithoutContent(node: Element) -> Bool {
        let textBlank = !hasNonWhitespaceText(node)
        if !textBlank { return false }
        let childCount = node.children().count
        if childCount == 0 { return true }
        let brHr = ((try? node.getElementsByTag("br").count) ?? 0) + ((try? node.getElementsByTag("hr").count) ?? 0)
        return childCount == brHr
    }

    private func hasSinglePInsideElement(element: Element) -> Bool {
        if element.children().count != 1 { return false }
        let child = element.child(0)
        guard child.tagNameUTF8() == ReadabilityUTF8Arrays.p else { return false }
        for node in element.getChildNodes() {
            if let text = node as? TextNode, regEx.hasContent(text.getWholeText()) {
                return false
            }
        }
        return true
    }

    private func hasChildBlockElement(element: Element) -> Bool {
        for child in element.children() {
            if divToPElems.contains(child.tagNameUTF8()) || hasChildBlockElement(element: child) {
                return true
            }
        }
        return false
    }

    private func setNodeTag(node: Element, tagName: [UInt8]) {
        _ = try? node.tagName(tagName)
    }

    // MARK: Second step: score elements
    private func scoreElements(elementsToScore: [Element],
                               options: ArticleGrabberOptions,
                               timing: TimingSink? = nil,
                               textLengthCache: inout [ObjectIdentifier: Int]) -> [Element] {
        var candidates: [Element] = []
        for element in elementsToScore {
            if element.parent() == nil { continue }
            let innerText = timing?.measure("grab.scoreElements.innerText") {
                getInnerText(element, regEx: regEx)
            } ?? getInnerText(element, regEx: regEx)
            let key = ObjectIdentifier(element)
            if textLengthCache[key] == nil {
                textLengthCache[key] = innerText.count
            }
            if isTextLengthLessThan(innerText, 25) { continue }
            let ancestors = timing?.measure("grab.scoreElements.ancestors") {
                getNodeAncestors(node: element, maxDepth: 5)
            } ?? getNodeAncestors(node: element, maxDepth: 5)
            if ancestors.isEmpty { continue }

            var contentScore = 1.0
            let commasCount = timing?.measure("grab.scoreElements.commas") {
                let commasRange = NSRange(location: 0, length: innerText.utf16.count)
                return commasPattern.numberOfMatches(in: innerText, options: [], range: commasRange)
            } ?? {
                let commasRange = NSRange(location: 0, length: innerText.utf16.count)
                return commasPattern.numberOfMatches(in: innerText, options: [], range: commasRange)
            }()
            contentScore += Double(commasCount + 1)
            if innerText.utf8.count >= 100 {
                contentScore += min(floor(Double(innerText.count) / 100.0), 3.0)
            }

            for (level, ancestor) in ancestors.enumerated() {
                if ancestor.tagNameUTF8().isEmpty { continue }
                if getReadabilityObject(element: ancestor) == nil {
                    candidates.append(ancestor)
                    _ = initializeNode(node: ancestor, options: options)
                }
                let scoreDivider: Int
                if level == 0 { scoreDivider = 1 }
                else if level == 1 { scoreDivider = 2 }
                else { scoreDivider = level * 3 }

                if let readability = getReadabilityObject(element: ancestor) {
                    readability.contentScore += contentScore / Double(scoreDivider)
                }
            }
        }
        return candidates
    }

    private func initializeNode(node: Element, options: ArticleGrabberOptions) -> ReadabilityObject {
        let readability = ReadabilityObject()
        readabilityObjects[ObjectIdentifier(node)] = readability

        switch node.tagNameUTF8() {
        case ReadabilityUTF8Arrays.div: readability.contentScore += 5
        case ReadabilityUTF8Arrays.pre, ReadabilityUTF8Arrays.td, ReadabilityUTF8Arrays.blockquote: readability.contentScore += 3
        case ReadabilityUTF8Arrays.address,
             ReadabilityUTF8Arrays.ol,
             ReadabilityUTF8Arrays.ul,
             ReadabilityUTF8Arrays.dl,
             ReadabilityUTF8Arrays.dd,
             ReadabilityUTF8Arrays.dt,
             ReadabilityUTF8Arrays.li,
             ReadabilityUTF8Arrays.form:
            readability.contentScore -= 3
        case ReadabilityUTF8Arrays.h1,
             ReadabilityUTF8Arrays.h2,
             ReadabilityUTF8Arrays.h3,
             ReadabilityUTF8Arrays.h4,
             ReadabilityUTF8Arrays.h5,
             ReadabilityUTF8Arrays.h6,
             ReadabilityUTF8Arrays.th:
            readability.contentScore -= 5
        default: break
        }

        readability.contentScore += Double(getClassWeight(e: node, options: options))
        return readability
    }

    private func getClassWeight(e: Element, options: ArticleGrabberOptions) -> Int {
        if options.weightClasses == false { return 0 }
        var weight = 0
        let className = e.classNameSafe()
        if !className.isEmpty {
            if regEx.isNegative(className) { weight -= 25 }
            if regEx.isPositive(className) { weight += 25 }
        }
        let id = e.idSafe()
        if !id.isEmpty {
            if regEx.isNegative(id) { weight -= 25 }
            if regEx.isPositive(id) { weight += 25 }
        }
        return weight
    }

    private func getNodeAncestors(node: Element, maxDepth: Int = 0) -> [Element] {
        var ancestors: [Element] = []
        var next: Element? = node
        var depth = 0
        while let parent = next?.parent() {
            ancestors.append(parent)
            depth += 1
            if maxDepth > 0 && depth == maxDepth { break }
            next = parent
        }
        return ancestors
    }

    private func textLength(of element: Element,
                            normalizeSpaces: Bool,
                            cache: inout [ObjectIdentifier: Int]) -> Int {
        let key = ObjectIdentifier(element)
        if let cached = cache[key] { return cached }
        let length: Int
        if normalizeSpaces {
            length = normalizedTextLength(of: element)
        } else {
            length = getInnerText(element, regEx: regEx, normalizeSpaces: normalizeSpaces).count
        }
        cache[key] = length
        return length
    }

    private func normalizedTextLength(of element: Element) -> Int {
        var length = 0
        var lastWasWhitespace = true
        var stack = Array(element.getChildNodes().reversed())

        while let node = stack.popLast() {
            if let text = node as? TextNode {
                accumulateNormalizedLength(from: text.getWholeText(),
                                           length: &length,
                                           lastWasWhitespace: &lastWasWhitespace)
            } else if let data = node as? DataNode {
                accumulateNormalizedLength(from: data.getWholeData(),
                                           length: &length,
                                           lastWasWhitespace: &lastWasWhitespace)
            } else if let el = node as? Element {
                let tagName = el.tagNameUTF8()
                if tagName == ReadabilityUTF8Arrays.br ||
                    tagName == ReadabilityUTF8Arrays.hr ||
                    blockTagsForTextLength.contains(tagName) {
                    lastWasWhitespace = true
                }

                let children = el.getChildNodes()
                if !children.isEmpty {
                    stack.append(contentsOf: children.reversed())
                }
            }
        }
        return length
    }

    private func accumulateNormalizedLength(from text: String,
                                            length: inout Int,
                                            lastWasWhitespace: inout Bool) {
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                lastWasWhitespace = true
                continue
            }
            if lastWasWhitespace && length > 0 {
                length += 1
            }
            length += 1
            lastWasWhitespace = false
        }
    }

    // MARK: Third step: top candidate
    private func getTopCandidate(page: Element,
                                 candidates: [Element],
                                 options: ArticleGrabberOptions,
                                 timing: TimingSink? = nil,
                                 textLengthCache: inout [ObjectIdentifier: Int],
                                 linkDensityCache: LinkDensityCache) -> (Element, Bool) {
        var topCandidates: [Element] = []

        for candidate in candidates {
            guard let readability = getReadabilityObject(element: candidate) else { continue }
            let candidateTextLength = timing?.measure("grab.getTopCandidate.innerText") {
                textLength(of: candidate, normalizeSpaces: true, cache: &textLengthCache)
            } ?? textLength(of: candidate, normalizeSpaces: true, cache: &textLengthCache)
            let candidateScore = readability.contentScore * (1 - getLinkDensity(
                element: candidate,
                textLength: candidateTextLength,
                timing: timing,
                cache: linkDensityCache
            ))
            readability.contentScore = candidateScore

            for t in 0..<nbTopCandidates {
                let aTopCandidate = topCandidates.count > t ? topCandidates[t] : nil
                let topReadability = aTopCandidate.flatMap { getReadabilityObject(element: $0) }
                if aTopCandidate == nil || (topReadability != nil && candidateScore > topReadability!.contentScore) {
                    topCandidates.insert(candidate, at: t)
                    if topCandidates.count > nbTopCandidates {
                        topCandidates.removeLast()
                    }
                    break
                }
            }
        }

        var topCandidate = topCandidates.first
        if topCandidate == nil || topCandidate?.tagNameUTF8() == ReadabilityUTF8Arrays.body {
            let newTop = (try? page.ownerDocument()?.createElement("div")) ?? Element(try! Tag.valueOf("div"), "")
            for child in Array(page.getChildNodes()) {
                _ = try? child.remove()
                _ = try? newTop.appendChild(child)
            }
            _ = try? page.appendChild(newTop)
            _ = initializeNode(node: newTop, options: options)
            return (newTop, true)
        } else {
            var parentOfTop = topCandidate!.parent()
            var alternativeAncestors: [[Element]] = []
            if let topScore = getReadabilityObject(element: topCandidate!)?.contentScore {
                if let timing {
                    _ = timing.measure("grab.getTopCandidate.altAncestors") {
                        for other in topCandidates where other != topCandidate! {
                            if let otherScore = getReadabilityObject(element: other)?.contentScore,
                               otherScore / topScore >= 0.75 {
                                alternativeAncestors.append(getNodeAncestors(node: other))
                            }
                        }
                    }
                } else {
                    for other in topCandidates where other != topCandidate! {
                        if let otherScore = getReadabilityObject(element: other)?.contentScore,
                           otherScore / topScore >= 0.75 {
                            alternativeAncestors.append(getNodeAncestors(node: other))
                        }
                    }
                }
            }

            let minimumTopCandidates = 3
            if alternativeAncestors.count >= minimumTopCandidates {
                while let parent = parentOfTop, parent.tagNameUTF8() != ReadabilityUTF8Arrays.body {
                    var listsContaining = 0
                    for list in alternativeAncestors {
                        if list.contains(parent) { listsContaining += 1 }
                        if listsContaining >= minimumTopCandidates { break }
                    }
                    if listsContaining >= minimumTopCandidates {
                        topCandidate = parent
                        break
                    }
                    parentOfTop = parent.parent()
                }
            }

            if getReadabilityObject(element: topCandidate!) == nil {
                _ = initializeNode(node: topCandidate!, options: options)
            }

            parentOfTop = topCandidate!.parent()
            var lastScore = getReadabilityObject(element: topCandidate!)?.contentScore ?? 0.0
            let scoreThreshold = lastScore / 3.0

            while let parent = parentOfTop, parent.tagNameUTF8() != ReadabilityUTF8Arrays.body {
                guard let parentReadability = getReadabilityObject(element: parent) else {
                    parentOfTop = parent.parent(); continue
                }
                let parentScore = parentReadability.contentScore
                if parentScore < scoreThreshold { break }
                if parentScore > lastScore {
                    topCandidate = parent
                    break
                }
                lastScore = parentScore
                parentOfTop = parent.parent()
            }

            var cur = topCandidate!
            parentOfTop = cur.parent()
            while let parent = parentOfTop, parent.tagNameUTF8() != ReadabilityUTF8Arrays.body, parent.children().count == 1 {
                cur = parent
                parentOfTop = cur.parent()
            }
            topCandidate = cur
            if getReadabilityObject(element: topCandidate!) == nil {
                _ = initializeNode(node: topCandidate!, options: options)
            }
            return (topCandidate!, false)
        }
    }

    private func getLinkDensity(element: Element,
                                textLength: Int? = nil,
                                timing: TimingSink? = nil,
                                cache: LinkDensityCache) -> Double {
        let currentVersion = element.textMutationVersionToken()
        if cache.textMutationVersion != currentVersion {
            cache.map.removeAll(keepingCapacity: true)
            cache.textMutationVersion = currentVersion
        }
        let cacheKey = ObjectIdentifier(element)
        if let cached = cache.map[cacheKey] {
            return cached
        }
        let textLength = textLength ?? getInnerText(element, regEx: regEx).count
        if textLength == 0 { return 0.0 }
        var linkLength = 0.0
        let links: Elements?
        if let timing {
            links = timing.measure("grab.getLinkDensity.select") {
                try? element.select("a")
            }
        } else {
            links = try? element.select("a")
        }
        if let links {
            var textCache: [ObjectIdentifier: Int] = [:]
            textCache.reserveCapacity(links.count)
            for link in links {
                let href = link.attrOrEmptyUTF8(ReadabilityUTF8Arrays.href)
                // Match Readability.js REGEXPS.hashUrl: /^#.+/ (exclude bare "#").
                let coefficient: Double = (href.count > 1 && href.first == ReadabilityUTF8Arrays.hash.first) ? 0.3 : 1.0
                let identifier = ObjectIdentifier(link)
                let linkTextLength: Int
                if let cached = textCache[identifier] {
                    linkTextLength = cached
                } else {
                    linkTextLength = timing?.measure("grab.getLinkDensity.innerText") {
                        getInnerText(link, regEx: regEx).count
                    } ?? getInnerText(link, regEx: regEx).count
                    textCache[identifier] = linkTextLength
                }
                if linkTextLength == 0 { continue }
                linkLength += Double(linkTextLength) * coefficient
            }
        }
        let density = linkLength / Double(textLength)
        cache.map[cacheKey] = density
        return density
    }

    // MARK: Fourth step: create article content
    private func createArticleContent(doc: Document,
                                      topCandidate: Element,
                                      isPaging: Bool,
                                      linkDensityCache: LinkDensityCache) -> Element {
        let articleContent = (try? doc.createElement("div")) ?? Element(try! Tag.valueOf("div"), "")
        if isPaging {
            _ = try? articleContent.attr(ReadabilityUTF8Arrays.id, ReadabilityUTF8Arrays.readabilityContent)
        }
        guard let topReadability = getReadabilityObject(element: topCandidate) else { return articleContent }

        let siblingScoreThreshold = max(10.0, topReadability.contentScore * 0.2)
        let siblings = topCandidate.parent()?.children() ?? Elements()
        let topClassName = topCandidate.classNameSafe()
        for sibling in Array(siblings) {
            var append = false
            let siblingReadability = getReadabilityObject(element: sibling)
            if sibling == topCandidate {
                append = true
            } else {
                var contentBonus = 0.0
                let siblingClassName = sibling.classNameSafe()
                if siblingClassName == topClassName, !topClassName.isEmpty {
                    contentBonus += topReadability.contentScore * 0.2
                }
                if let sr = siblingReadability,
                   (sr.contentScore + contentBonus) >= siblingScoreThreshold {
                    append = true
                } else if shouldKeepSibling(sibling: sibling) {
                    let nodeContent = getInnerText(sibling, regEx: regEx)
                    let nodeLength = nodeContent.utf8.count < 81 ? nodeContent.utf8.count : nodeContent.count
                    let linkDensity = getLinkDensity(
                        element: sibling,
                        textLength: nodeLength,
                        cache: linkDensityCache
                    )
                    if nodeLength > 80 && linkDensity < 0.25 {
                        append = true
                    } else if nodeLength < 80 && nodeLength > 0 && linkDensity == 0.0 &&
                                nodeContent.range(of: "\\.( |$)", options: .regularExpression) != nil {
                        append = true
                    }
                }
            }

            if append {
                if !alterToDivExceptions.contains(sibling.tagNameUTF8()) {
                    setNodeTag(node: sibling, tagName: ReadabilityUTF8Arrays.div)
                }
                _ = try? articleContent.appendChild(sibling)
            }
        }
        return articleContent
    }

    private func shouldKeepSibling(sibling: Element) -> Bool {
        return sibling.tagNameUTF8() == ReadabilityUTF8Arrays.p
    }

    // MARK: Fifth step: prep article
    private func prepArticle(articleContent: Element,
                             options: ArticleGrabberOptions,
                             metadata: ArticleMetadata,
                             timing: TimingSink? = nil,
                             linkDensityCache: LinkDensityCache) {
        if let timing {
            _ = timing.measure("grab.cleanStyles") { cleanStyles(e: articleContent) }
            _ = timing.measure("grab.markDataTables") { markDataTables(root: articleContent) }
            _ = timing.measure("grab.fixLazyImages") { fixLazyImages(root: articleContent) }
        } else {
            cleanStyles(e: articleContent)
            markDataTables(root: articleContent)
            fixLazyImages(root: articleContent)
        }

        if let timing {
            _ = timing.measure("grab.cleanConditionally.form") { cleanConditionally(e: articleContent, tag: "form", options: options, timing: timing, linkDensityCache: linkDensityCache) }
            _ = timing.measure("grab.cleanConditionally.fieldset") { cleanConditionally(e: articleContent, tag: "fieldset", options: options, timing: timing, linkDensityCache: linkDensityCache) }
            _ = timing.measure("grab.clean.object") { clean(e: articleContent, tag: "object") }
            _ = timing.measure("grab.clean.embed") { clean(e: articleContent, tag: "embed") }
            _ = timing.measure("grab.clean.footer") { clean(e: articleContent, tag: "footer") }
            _ = timing.measure("grab.clean.link") { clean(e: articleContent, tag: "link") }
            _ = timing.measure("grab.clean.aside") { clean(e: articleContent, tag: "aside") }
        } else {
            cleanConditionally(e: articleContent, tag: "form", options: options, linkDensityCache: linkDensityCache)
            cleanConditionally(e: articleContent, tag: "fieldset", options: options, linkDensityCache: linkDensityCache)
            clean(e: articleContent, tag: "object")
            clean(e: articleContent, tag: "embed")
            clean(e: articleContent, tag: "footer")
            clean(e: articleContent, tag: "link")
            clean(e: articleContent, tag: "aside")
        }

        let shareRegex = try! NSRegularExpression(pattern: "(\\b|_)(share|sharedaddy)(\\b|_)", options: [.caseInsensitive])
        let shareElementThreshold = ReadabilityOptions.defaultCharThreshold
        for topCandidate in articleContent.children() {
            cleanMatchedNodes(e: topCandidate) { node, matchString in
                let range = NSRange(location: 0, length: matchString.utf16.count)
                if shareRegex.firstMatch(in: matchString, options: [], range: range) == nil {
                    return false
                }
                let text = self.textContentPreservingWhitespace(of: node)
                return self.isTextLengthLessThan(text, shareElementThreshold)
            }
        }

        if let timing {
            _ = timing.measure("grab.clean.iframe") { clean(e: articleContent, tag: "iframe") }
            _ = timing.measure("grab.clean.input") { clean(e: articleContent, tag: "input") }
            _ = timing.measure("grab.clean.textarea") { clean(e: articleContent, tag: "textarea") }
            _ = timing.measure("grab.clean.select") { clean(e: articleContent, tag: "select") }
            _ = timing.measure("grab.clean.button") { clean(e: articleContent, tag: "button") }
            _ = timing.measure("grab.cleanHeaders") { cleanHeaders(e: articleContent, options: options) }
            _ = timing.measure("grab.cleanConditionally.table") { cleanConditionally(e: articleContent, tag: "table", options: options, timing: timing, linkDensityCache: linkDensityCache) }
            _ = timing.measure("grab.cleanConditionally.ul") { cleanConditionally(e: articleContent, tag: "ul", options: options, timing: timing, linkDensityCache: linkDensityCache) }
            _ = timing.measure("grab.cleanConditionally.div") { cleanConditionally(e: articleContent, tag: "div", options: options, timing: timing, linkDensityCache: linkDensityCache) }
        } else {
            clean(e: articleContent, tag: "iframe")
            clean(e: articleContent, tag: "input")
            clean(e: articleContent, tag: "textarea")
            clean(e: articleContent, tag: "select")
            clean(e: articleContent, tag: "button")
            cleanHeaders(e: articleContent, options: options)
            cleanConditionally(e: articleContent, tag: "table", options: options, linkDensityCache: linkDensityCache)
            cleanConditionally(e: articleContent, tag: "ul", options: options, linkDensityCache: linkDensityCache)
            cleanConditionally(e: articleContent, tag: "div", options: options, linkDensityCache: linkDensityCache)
        }

        // Replace H1 with H2 as H1 should be only title that is displayed separately.
        if let h1s = try? articleContent.select("h1") {
            for h1 in h1s {
                _ = try? h1.tagName("h2")
            }
        }

        removeNodes(in: articleContent, tagName: "p") { paragraph in
            let imgCount = (try? paragraph.getElementsByTag("img").count) ?? 0
            let embedCount = (try? paragraph.getElementsByTag("embed").count) ?? 0
            let objectCount = (try? paragraph.getElementsByTag("object").count) ?? 0
            let iframeCount = (try? paragraph.getElementsByTag("iframe").count) ?? 0
            let total = imgCount + embedCount + objectCount + iframeCount
            if total != 0 { return false }
            return !self.hasNonWhitespaceText(paragraph)
        }

        if let brs = try? articleContent.select("br") {
            for br in brs {
                if let next = nextElement(from: br.nextSibling(), regEx: regEx), next.tagNameUTF8() == ReadabilityUTF8Arrays.p {
                    _ = try? br.remove()
                }
            }
        }

        // Remove single-cell tables (Readability.js _prepArticle)
        if let tables = try? articleContent.getElementsByTag("table") {
            for table in Array(tables) {
                let tbody: Element = {
                    if self.hasSingleTagInsideElement(table, tagName: ReadabilityUTF8Arrays.tbody) {
                        return table.child(0)
                    }
                    return table
                }()

                guard self.hasSingleTagInsideElement(tbody, tagName: ReadabilityUTF8Arrays.tr),
                      let row = tbody.children().firstSafe
                else { continue }

                guard self.hasSingleTagInsideElement(row, tagName: ReadabilityUTF8Arrays.td),
                      let cell = row.children().firstSafe
                else { continue }

                var phrasingCache: [ObjectIdentifier: Bool] = [:]
                let allPhrasing = cell.getChildNodes().allSatisfy { child in
                    self.isPhrasingContent(child, cache: &phrasingCache)
                }
                setNodeTag(node: cell, tagName: allPhrasing ? ReadabilityUTF8Arrays.p : ReadabilityUTF8Arrays.div)
                _ = try? cell.remove()
                _ = try? table.replaceWith(cell)
            }
        }
    }

    private func hasSingleTagInsideElement(_ element: Element, tagName: [UInt8]) -> Bool {
        if element.children().count != 1 { return false }
        guard let onlyChild = element.children().firstSafe,
              onlyChild.tagNameUTF8() == tagName
        else { return false }

        for node in element.getChildNodes() {
            if let text = node as? TextNode, regEx.hasContent(text.getWholeText()) {
                return false
            }
        }
        return true
    }

    private func fixLazyImages(root: Element) {
        guard let nodes = try? root.select("img, picture, figure") else { return }
        for elem in nodes {
            var src = String(decoding: elem.attrOrEmptyUTF8(ReadabilityUTF8Arrays.src), as: UTF8.self)
            if !src.isEmpty {
                let range = NSRange(location: 0, length: src.utf16.count)
                if let match = ArticleGrabber.b64DataUrlRegex.firstMatch(in: src, options: [], range: range),
                   match.numberOfRanges > 1,
                   let mimeRange = Range(match.range(at: 1), in: src)
                {
                    let mimeType = String(src[mimeRange])
                    if mimeType != "image/svg+xml" {
                        var srcCouldBeRemoved = false
                        if let attrs = elem.getAttributes()?.asList() {
                            for attr in attrs {
                                let keyBytes = attr.getKeyUTF8()
                                if keyBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.src) { continue }
                                let value = String(decoding: attr.getValueUTF8(), as: UTF8.self)
                                if value.range(of: "\\.(jpg|jpeg|png|webp)", options: [.regularExpression, .caseInsensitive]) != nil {
                                    srcCouldBeRemoved = true
                                    break
                                }
                            }
                        }

                        if srcCouldBeRemoved {
                            let b64Starts = match.range(at: 0).length
                            let b64Length = src.utf16.count - b64Starts
                            if b64Length < 133 {
                                _ = try? elem.removeAttr(ReadabilityUTF8Arrays.src)
                                src = String(decoding: elem.attrOrEmptyUTF8(ReadabilityUTF8Arrays.src), as: UTF8.self)
                            }
                        }
                    }
                }
            }

            let srcset = String(decoding: elem.attrOrEmptyUTF8(ReadabilityUTF8Arrays.srcset), as: UTF8.self)
            let hasSrcSet = !srcset.isEmpty && srcset != "null"
            if (!src.isEmpty || hasSrcSet) && !elem.classNameSafe().lowercased().contains("lazy") {
                continue
            }

            guard let attrs = elem.getAttributes()?.asList() else { continue }
            for attr in attrs {
                let nameBytes = attr.getKeyUTF8()
                if nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.src) ||
                    nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.srcset) ||
                    nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.alt) {
                    continue
                }
                let value = String(decoding: attr.getValueUTF8(), as: UTF8.self)
                var copyTo: String?
                if value.range(of: "\\.(jpg|jpeg|png|webp)\\s+\\d", options: [.regularExpression, .caseInsensitive]) != nil {
                    copyTo = "srcset"
                } else if value.range(of: "^\\s*\\S+\\.(jpg|jpeg|png|webp)\\S*\\s*$", options: [.regularExpression, .caseInsensitive]) != nil {
                    copyTo = "src"
                }

                guard let copyTo else { continue }

                let tagName = elem.tagNameUTF8()
                if tagName == ReadabilityUTF8Arrays.img || tagName == ReadabilityUTF8Arrays.picture {
                    _ = try? elem.attr(copyTo, value)
                } else if tagName == ReadabilityUTF8Arrays.figure {
                    if ((try? elem.select("img, picture").count) ?? 0) > 0 {
                        continue
                    }
                    let img: Element = {
                        if let doc = elem.ownerDocument(), let created = try? doc.createElement("img") {
                            return created
                        }
                        return Element(try! Tag.valueOf("img"), "")
                    }()
                    _ = try? img.attr(copyTo, value)
                    _ = try? elem.appendChild(img)
                }
            }
        }
    }

    private func cleanStyles(e: Element) {
        if e.tagNameUTF8() == ReadabilityUTF8Arrays.svg { return }
        for attrName in presentationalAttributes {
            _ = try? e.removeAttr(attrName)
        }
        if deprecatedSizeAttributeElems.contains(e.tagNameUTF8()) {
            _ = try? e.removeAttr(ReadabilityUTF8Arrays.width)
            _ = try? e.removeAttr(ReadabilityUTF8Arrays.height)
        }
        for child in e.children() {
            cleanStyles(e: child)
        }
    }

    private func markDataTables(root: Element) {
        guard let tables = try? root.getElementsByTag("table") else { return }
        for table in tables {
            let role = (try? table.attr(ReadabilityUTF8Arrays.role)) ?? []
            if role.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.presentation) { setReadabilityDataTable(table: table, value: false); continue }
            let datatable = (try? table.attr(ReadabilityUTF8Arrays.datatable)) ?? []
            if datatable.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.zero) { setReadabilityDataTable(table: table, value: false); continue }
            let summary = (try? table.attr(ReadabilityUTF8Arrays.summary)) ?? []
            if !summary.isEmpty { setReadabilityDataTable(table: table, value: true); continue }

            let caption = (try? table.getElementsByTag("caption")) ?? Elements()
            if caption.count > 0 && caption[0].childNodeSize() > 0 {
                setReadabilityDataTable(table: table, value: true); continue
            }

            var foundDescendant = false
            for tag in dataTableDescendants {
                if ((try? table.getElementsByTag(tag).count) ?? 0) > 0 {
                    setReadabilityDataTable(table: table, value: true)
                    foundDescendant = true
                    break
                }
            }
            if foundDescendant { continue }

            // SwiftSoup (like Jsoup) includes the element itself in getElementsByTag results.
            // Readability.js checks for *descendant* tables, so require more than just the table itself.
            if ((try? table.getElementsByTag("table").count) ?? 0) > 1 {
                setReadabilityDataTable(table: table, value: false); continue
            }

            let sizeInfo = getRowAndColumnCount(table: table)
            // single column/row tables are commonly used for page layout purposes.
            if sizeInfo.0 == 1 || sizeInfo.1 == 1 {
                setReadabilityDataTable(table: table, value: false); continue
            }
            if sizeInfo.0 >= 10 || sizeInfo.1 > 4 {
                setReadabilityDataTable(table: table, value: true); continue
            }
            setReadabilityDataTable(table: table, value: sizeInfo.0 * sizeInfo.1 > 10)
        }
    }

    private func getRowAndColumnCount(table: Element) -> (Int, Int) {
        var rows = 0
        var columns = 0
        if let trs = try? table.getElementsByTag("tr") {
        for tr in trs {
            let rowspan = (try? tr.attr(ReadabilityUTF8Arrays.rowspan)) ?? []
            rows += Int(String(decoding: rowspan, as: UTF8.self)) ?? 1
            var colsInRow = 0
            if let cells = try? tr.getElementsByTag("td") {
            for cell in cells {
                let colspan = (try? cell.attr(ReadabilityUTF8Arrays.colspan)) ?? []
                colsInRow += Int(String(decoding: colspan, as: UTF8.self)) ?? 1
            }}
            columns = max(columns, colsInRow)
        }
        }
        return (rows, columns)
    }

    private func getTextDensity(_ element: Element, tags: [String], textLength: Int? = nil, timing: TimingSink? = nil) -> Double {
        let textLength = textLength ?? getInnerText(element, regEx: regEx, normalizeSpaces: true).count
        if textLength == 0 { return 0 }

        let selector = tags
            .map { $0.lowercased() }
            .joined(separator: ",")
        let children: Elements?
        if let timing {
            children = timing.measure("grab.getTextDensity.select") {
                try? element.select(selector)
            }
        } else {
            children = try? element.select(selector)
        }
        guard !selector.isEmpty, let children else { return 0 }

        var childrenLength = 0
        var textCache: [ObjectIdentifier: Int] = [:]
        textCache.reserveCapacity(children.count)
        for child in children {
            // SwiftSoup may include the root element itself in `select` results; Readability.js only counts descendants.
            if child === element { continue }
            let identifier = ObjectIdentifier(child)
            let childLength: Int
            if let cached = textCache[identifier] {
                childLength = cached
            } else {
                childLength = timing?.measure("grab.getTextDensity.innerText") {
                    getInnerText(child, regEx: regEx, normalizeSpaces: true).count
                } ?? getInnerText(child, regEx: regEx, normalizeSpaces: true).count
                textCache[identifier] = childLength
            }
            childrenLength += childLength
        }
        return Double(childrenLength) / Double(textLength)
    }

    private func cleanConditionally(e: Element,
                                    tag: String,
                                    options: ArticleGrabberOptions,
                                    timing: TimingSink? = nil,
                                    linkDensityCache: LinkDensityCache) {
        if options.cleanConditionally == false { return }
        let initialIsList = tag == "ul" || tag == "ol"

        removeNodes(in: e, tagName: tag) { node in
            let isDataTable: (Element) -> Bool = { element in
                self.getReadabilityDataTable(element: element)
            }
            var isList = initialIsList
            let innerText = timing?.measure("grab.cleanConditionally.innerText") {
                self.getInnerText(node, regEx: self.regEx)
            } ?? self.getInnerText(node, regEx: self.regEx)
            let innerTextLength = innerText.count
            var nodeLength = 0
            if !isList {
                nodeLength = innerTextLength
                let listNodes: Elements?
                if let timing {
                    listNodes = timing.measure("grab.cleanConditionally.listSelect") {
                        try? node.select("ul, ol")
                    }
                } else {
                    listNodes = try? node.select("ul, ol")
                }
                if nodeLength > 0, let listNodes {
                    var listLength = 0
                    for list in listNodes {
                        listLength += self.getInnerText(list, regEx: self.regEx).count
                    }
                    isList = Double(listLength) / Double(nodeLength) > 0.9
                }
            }

            if tag == "table", isDataTable(node) {
                return false
            }
            if self.hasAncestorTag(node: node, tagName: ReadabilityUTF8Arrays.table, maxDepth: -1, filterFn: isDataTable) {
                return false
            }
            if self.hasAncestorTag(node: node, tagName: ReadabilityUTF8Arrays.code) {
                return false
            }

            // keep element if it has a data table
            if let tables = try? node.select("table") {
                for tbl in tables {
                    if isDataTable(tbl) { return false }
                }
            }

            let weight = self.getClassWeight(e: node, options: options)
            if weight < 0 { return true }

            if self.countOccurrences(innerText, ascii: self.asciiComma, max: 10) < 10 {
                let p = (try? node.select("p").count) ?? 0
                let img = (try? node.select("img").count) ?? 0
                let li = ((try? node.select("li").count) ?? 0) - 100
                let input = (try? node.select("input").count) ?? 0
                let headingDensity = self.getTextDensity(
                    node,
                    tags: ["h1", "h2", "h3", "h4", "h5", "h6"],
                    textLength: innerTextLength,
                    timing: timing
                )
                var embedCount = 0
                let embeds: Elements?
                if let timing {
                    embeds = timing.measure("grab.cleanConditionally.embedsSelect") {
                        try? node.select("object, embed, iframe")
                    }
                } else {
                    embeds = try? node.select("object, embed, iframe")
                }
                if let embeds {
                    for embed in embeds {
                        if let attrs = embed.getAttributes()?.asList() {
                            for attr in attrs {
                                let value = String(decoding: attr.getValueUTF8(), as: UTF8.self)
                                if self.regEx.isVideo(value) {
                                    return false
                                }
                            }
                        }
                        if embed.tagNameUTF8() == ReadabilityUTF8Arrays.object, self.regEx.isVideo((try? embed.html()) ?? "") {
                            return false
                        }
                        embedCount += 1
                    }
                }
                let linkDensity = self.getLinkDensity(
                    element: node,
                    textLength: innerTextLength,
                    timing: timing,
                    cache: linkDensityCache
                )
                let innerTextRange = NSRange(location: 0, length: innerText.utf16.count)
                if self.adWordsPattern.firstMatch(in: innerText, options: [], range: innerTextRange) != nil ||
                   self.loadingWordsPattern.firstMatch(in: innerText, options: [], range: innerTextRange) != nil {
                    return true
                }

                let contentLength = innerTextLength
                let textishTags = Set(["span", "li", "td"]).union(self.divToPElemsStrings)
                let textDensity = self.getTextDensity(node, tags: Array(textishTags), textLength: innerTextLength, timing: timing)
                let isFigureChild = self.hasAncestorTag(node: node, tagName: ReadabilityUTF8Arrays.figure)
                let linkDensityModifier = self.linkDensityModifier

                var haveToRemove = false
                if !isFigureChild && img > 1 && Double(p) / Double(img) < 0.5 {
                    haveToRemove = true
                } else if !isList && li > p {
                    haveToRemove = true
                } else if input > Int(floor(Double(p) / 3.0)) {
                    haveToRemove = true
                } else if !isList &&
                            !isFigureChild &&
                            headingDensity < 0.9 &&
                            contentLength < 25 &&
                            (img == 0 || img > 2) &&
                            linkDensity > 0 {
                    haveToRemove = true
                } else if !isList && weight < 25 && linkDensity > 0.2 + linkDensityModifier {
                    haveToRemove = true
                } else if weight >= 25 && linkDensity > 0.5 + linkDensityModifier {
                    haveToRemove = true
                } else if (embedCount == 1 && contentLength < 75) || embedCount > 1 {
                    haveToRemove = true
                } else if img == 0 && textDensity == 0 {
                    haveToRemove = true
                }

                // Allow simple lists of images to remain in pages.
                if isList && haveToRemove {
                    for child in node.children() where child.children().count > 1 {
                        return haveToRemove
                    }
                    let liCount = (try? node.getElementsByTag("li").count) ?? 0
                    if img == liCount {
                        return false
                    }
                }

                return haveToRemove
            }
            return false
        }
    }

    private func hasAncestorTag(node: Element, tagName: [UInt8], maxDepth: Int = 3, filterFn: ((Element) -> Bool)? = nil) -> Bool {
        var parent: Element? = node
        var depth = 0
        while let p = parent?.parent() {
            if maxDepth > 0 && depth > maxDepth { return false }
            if p.tagNameUTF8() == tagName && (filterFn?(p) ?? true) { return true }
            parent = p
            depth += 1
        }
        return false
    }

    private func getCharCount(node: Element, c: Character = ",") -> Int {
        return getCharCount(text: getInnerText(node, regEx: regEx), c: c)
    }

    private func getCharCount(text: String, c: Character = ",") -> Int {
        if let ascii = c.asciiValue {
            return countOccurrences(text, ascii: ascii, max: nil)
        }
        return text.split(separator: c).count - 1
    }

    private let asciiComma: UInt8 = 44

    private func countOccurrences(_ text: String, ascii: UInt8, max: Int?) -> Int {
        var count = 0
        if let max, max <= 0 { return 0 }
        for byte in text.utf8 {
            if byte == ascii {
                count += 1
                if let max, count >= max { return count }
            }
        }
        return count
    }

    private func clean(e: Element, tag: String) {
        let isEmbed = embeddedNodes.contains(tag.utf8Array)
        removeNodes(in: e, tagName: tag) { element in
            if isEmbed {
                let attributeValues = element.getAttributes()?.asList()
                    .map { String(decoding: $0.getValueUTF8(), as: UTF8.self) }
                    .joined(separator: "|") ?? ""
                if self.regEx.isVideo(attributeValues) { return false }
                if self.regEx.isVideo((try? element.html()) ?? "") { return false }
            }
            return true
        }
    }

    private func cleanMatchedNodes(e: Element, filter: (_ node: Element, _ matchString: String) -> Bool) {
        let endOfSearchMarker = getNextNode(node: e, ignoreSelfAndKids: true)
        var next = getNextNode(node: e)
        while let current = next, current != endOfSearchMarker {
            let matchString = current.classNameSafe() + " " + current.idSafe()
            if filter(current, matchString) {
                next = removeAndGetNext(node: current, reason: "cleanMatchedNodes")
            } else {
                next = getNextNode(node: current)
            }
        }
    }

    private func cleanHeaders(e: Element, options: ArticleGrabberOptions) {
        for tag in ["h1", "h2"] {
            removeNodes(in: e, tagName: tag) { header in
                self.getClassWeight(e: header, options: options) < 0
            }
        }
    }

    // MARK: util
    private func removeAndGetNext(node: Element, reason: String = "") -> Element? {
        let nextNode = getNextNode(node: node, ignoreSelfAndKids: true)
        printAndRemove(node: node, reason: reason)
        return nextNode
    }

    private func getNextNode(node: Element, ignoreSelfAndKids: Bool = false) -> Element? {
        if !ignoreSelfAndKids, node.children().count > 0 {
            return node.child(0)
        }
        if let next = try? node.nextElementSibling() { return next }
        var parent = node.parent()
        while let p = parent, (try? p.nextElementSibling()) == nil {
            parent = p.parent()
        }
        if let sib = try? parent?.nextElementSibling() { return sib }
        return nil
    }

    private func getTextDirection(topCandidate: Element, doc: Document) {
        var ancestors: [Element] = []
        if let parent = topCandidate.parent() { ancestors.append(parent) }
        ancestors.append(topCandidate)
        ancestors.append(contentsOf: getNodeAncestors(node: topCandidate.parent() ?? topCandidate))
        if let body = doc.body() { ancestors.append(body) }
        if let html = try? doc.select("html").first() { ancestors.append(html) }

        for ancestor in ancestors {
            let dir = String(decoding: (try? ancestor.attr(ReadabilityUTF8Arrays.dir)) ?? [], as: UTF8.self)
            if !dir.isEmpty {
                self.articleDir = dir
                return
            }
        }
    }

    private func getReadabilityObject(element: Element) -> ReadabilityObject? {
        readabilityObjects[ObjectIdentifier(element)]
    }

    private func getReadabilityDataTable(element: Element) -> Bool {
        readabilityDataTable[ObjectIdentifier(element)] ?? false
    }

    private func setReadabilityDataTable(table: Element, value: Bool) {
        readabilityDataTable[ObjectIdentifier(table)] = value
    }
}
