import Foundation
import SwiftSoup

/// Basic sanitization before extraction.
final class Preprocessor: ProcessorBase {
    private let regEx: RegExUtil

    init(regEx: RegExUtil = RegExUtil()) {
        self.regEx = regEx
    }

    /// Prepare the HTML document for readability to scrape it.
    func prepareDocument(_ document: Document) {
        unwrapNoscriptImages(document)
        normalizeRuby(document)
        removeScripts(document)
        removeStyles(document)
        removeComments(document)
        replaceBrs(document, regEx: regEx)
        replaceNodes(in: document, tagName: "font", newTagName: "span")
        normalizeImageCarousels(document)
    }

    private func normalizeRuby(_ document: Document) {
        guard let rubyElements = try? document.getElementsByTag("ruby").array(), !rubyElements.isEmpty else {
            return
        }
        for ruby in rubyElements {
            if let rpElements = try? ruby.getElementsByTag("rp").array() {
                for rp in rpElements {
                    try? rp.remove()
                }
            }
            if let rbElements = try? ruby.getElementsByTag("rb").array() {
                for rb in rbElements {
                    _ = try? rb.unwrap()
                }
            }
        }
    }

    private func removeScripts(_ document: Document) {
        removeNodes(in: document, tagName: "script")
        removeNodes(in: document, tagName: "noscript")
    }

    private func removeComments(_ document: Document) {
        removeCommentNodes(from: document)
    }

    private func removeCommentNodes(from node: Node) {
        for child in Array(node.getChildNodes()) {
            if child.nodeName() == "#comment" {
                try? child.remove()
            } else {
                removeCommentNodes(from: child)
            }
        }
    }

    // MARK: - Embedded image carousel normalization

    private let imageCarouselPattern = try! NSRegularExpression(
        pattern: "carousel|slider|slideshow|swiper|flickity|splide|keen-slider|glide",
        options: [.caseInsensitive]
    )
    private let imageGalleryRolePattern = try! NSRegularExpression(
        pattern: #"\bimage\s+gallery\b"#,
        options: [.caseInsensitive]
    )
    private let galleryPattern = try! NSRegularExpression(
        pattern: #"\bgallery\b"#,
        options: [.caseInsensitive]
    )
    private let rasterImageURLPattern = try! NSRegularExpression(
        pattern: #"(?i)\.(jpe?g|png|webp|gif)(\?|#|$)"#,
        options: []
    )

    private struct CarouselImageItem {
        let image: Element
        let src: String
    }

    private func normalizeImageCarousels(_ document: Document) {
        let candidates = allElements(in: document).filter { isLikelyImageCarousel($0) }
        var normalized: [Element] = []

        for candidate in candidates {
            if normalized.contains(where: { containsElement($0, candidate) }) {
                continue
            }
            guard candidate.parent() != nil,
                  let replacement = buildReadabilityCarousel(from: candidate, document: document)
            else {
                continue
            }
            normalized.append(candidate)
            _ = try? candidate.replaceWith(replacement)
        }
    }

    private func isLikelyImageCarousel(_ node: Element) -> Bool {
        let marker = [
            node.classNameSafe(),
            node.idSafe(),
            node.attrOrEmpty("role"),
            node.attrOrEmpty("aria-roledescription"),
            node.attrOrEmpty("data-ride"),
            node.attrOrEmpty("data-gallery"),
            node.attrOrEmpty("data-component")
        ].joined(separator: " ")
        let hasStrongCarouselMarker = matches(imageCarouselPattern, in: marker)
        let hasImageGallerySemantics = matches(imageGalleryRolePattern, in: marker) ||
            (matches(galleryPattern, in: marker) && allElements(in: node).contains { child in
                child !== node && matches(imageCarouselPattern, in: child.classNameSafe() + " " + child.idSafe())
            })
        guard hasStrongCarouselMarker || hasImageGallerySemantics else { return false }

        let images = carouselImageItems(in: node)
        guard images.count >= 2 else { return false }

        let text = getInnerText(node, regEx: regEx)
        guard text.count <= 1600 else { return false }

        if text.count > 120, linkDensity(in: node, textLength: text.count) > 0.6 {
            return false
        }

        return true
    }

    private func carouselImageItems(in node: Element) -> [CarouselImageItem] {
        guard let images = try? node.getElementsByTag("img").array() else { return [] }
        var items: [CarouselImageItem] = []
        var seen = Set<String>()

        for image in images {
            let src = bestCarouselImageSource(for: image)
            guard !src.isEmpty, seen.insert(src).inserted else { continue }
            items.append(CarouselImageItem(image: image, src: src))
        }

        return items
    }

    private func bestCarouselImageSource(for image: Element) -> String {
        for attr in [
            "src",
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-flickity-lazyload-src",
            "data-flickity-lazyload",
            "data-url"
        ] {
            let value = image.attrOrEmpty(attr).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeRasterImageURL(value) {
                return value
            }
        }

        if let value = firstImageFromSrcset(
            image.attrOrEmpty("srcset").isEmpty ? image.attrOrEmpty("data-srcset") : image.attrOrEmpty("srcset")
        ) {
            return value
        }
        if let value = firstImageFromSrcset(image.attrOrEmpty("data-flickity-lazyload-srcset")) {
            return value
        }

        if let picture = image.parents().first(where: { $0.tagNameNormal() == "picture" }),
           let sources = try? picture.getElementsByTag("source").array() {
            for source in sources {
                let srcset = source.attrOrEmpty("srcset").isEmpty ? source.attrOrEmpty("data-srcset") : source.attrOrEmpty("srcset")
                if let value = firstImageFromSrcset(srcset) {
                    return value
                }
            }
        }

        return ""
    }

    private func looksLikeRasterImageURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return matches(rasterImageURLPattern, in: value)
    }

    private func firstImageFromSrcset(_ srcset: String) -> String? {
        for candidate in srcset.split(separator: ",") {
            guard let url = candidate.split(whereSeparator: { $0.isWhitespace }).first else {
                continue
            }
            let value = String(url).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeRasterImageURL(value) {
                return value
            }
        }
        return nil
    }

    private func buildReadabilityCarousel(from sourceNode: Element, document: Document) -> Element? {
        let items = carouselImageItems(in: sourceNode)
        guard items.count >= 2,
              let figure = try? document.createElement("figure"),
              let track = try? document.createElement("div")
        else {
            return nil
        }

        _ = try? figure.attr("data-readability-carousel", "true")
        _ = try? figure.attr("role", "group")
        _ = try? figure.attr("aria-label", "Image gallery")
        _ = try? track.attr("data-readability-carousel-track", "")
        _ = try? figure.appendChild(track)

        for item in items {
            guard let slide = try? document.createElement("figure"),
                  let img = try? document.createElement("img")
            else {
                continue
            }
            _ = try? slide.attr("data-readability-carousel-slide", "")
            _ = try? img.attr("src", item.src)

            let alt = item.image.attrOrEmpty("alt")
            if !alt.isEmpty {
                _ = try? img.attr("alt", alt)
            }
            let width = item.image.attrOrEmpty("width")
            if !width.isEmpty {
                _ = try? img.attr("width", width)
            }
            let height = item.image.attrOrEmpty("height")
            if !height.isEmpty {
                _ = try? img.attr("height", height)
            }

            _ = try? slide.appendChild(img)

            if let caption = carouselCaption(for: item.image, boundary: sourceNode),
               let figcaption = try? document.createElement("figcaption") {
                _ = try? figcaption.text(caption)
                _ = try? slide.appendChild(figcaption)
            }

            _ = try? track.appendChild(slide)
        }

        return figure
    }

    private func carouselCaption(for image: Element, boundary: Element) -> String? {
        var current: Element? = image
        while let element = current, element !== boundary {
            if let caption = try? element.select("figcaption, [class*=caption], [class*=credit]").first() {
                let text = getInnerText(caption, regEx: regEx)
                if !text.isEmpty,
                   text.range(of: #"^\d+\s+of\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) == nil {
                    return text
                }
            }
            current = element.parent()
        }
        return nil
    }

    private func containsElement(_ ancestor: Element, _ descendant: Element) -> Bool {
        var current = descendant.parent()
        while let element = current {
            if element === ancestor { return true }
            current = element.parent()
        }
        return false
    }

    private func allElements(in root: Element) -> [Element] {
        var result: [Element] = []
        var stack = [root]
        while let current = stack.popLast() {
            result.append(current)
            let children = current.children()
            for child in children.reversed() {
                stack.append(child)
            }
        }
        return result
    }

    private func linkDensity(in element: Element, textLength: Int) -> Double {
        guard textLength > 0, let links = try? element.getElementsByTag("a").array(), !links.isEmpty else {
            return 0
        }
        let linkLength = links.reduce(0) { partial, link in
            partial + getInnerText(link, regEx: regEx).count
        }
        return Double(linkLength) / Double(textLength)
    }

    private func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
    }

    // MARK: - Noscript image unwrapping (Readability.js _unwrapNoscriptImages)

    private func unwrapNoscriptImages(_ document: Document) {
        // Remove placeholder images without any obvious image source.
        if let imgs = try? document.getElementsByTag("img") {
            for img in imgs {
                var keep = false
                if let attrs = img.getAttributes() {
                    for attr in attrs {
                        let nameBytes = attr.getKeyUTF8()
                        let valueBytes = attr.getValueUTF8()
                        if nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.src) ||
                            nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.srcset) ||
                            nameBytes.equalsIgnoreCaseASCII("data-src".utf8Array) ||
                            nameBytes.equalsIgnoreCaseASCII("data-srcset".utf8Array) {
                            keep = true
                            break
                        }
                        let value = String(decoding: valueBytes, as: UTF8.self)
                        if value.range(of: "\\.(jpg|jpeg|png|webp)", options: [.regularExpression, .caseInsensitive]) != nil {
                            keep = true
                            break
                        }
                    }
                }
                if !keep {
                    try? img.remove()
                }
            }
        }

        // Next, replace previous placeholder single-image siblings with the image inside noscript.
        guard let noscripts = try? document.getElementsByTag("noscript") else { return }
        for noscript in noscripts {
            guard isSingleImage(noscript) else { continue }

            guard let tmp = try? document.createElement("div") else { continue }
            let inner = (try? noscript.html()) ?? ""
            _ = try? tmp.html(inner)

            guard let prevElement = (try? noscript.previousElementSibling()) ?? nil else { continue }
            guard isSingleImage(prevElement) else { continue }

            let prevImg: Element
            if prevElement.tagNameUTF8() == ReadabilityUTF8Arrays.img {
                prevImg = prevElement
            } else if let first = (try? prevElement.getElementsByTag("img"))?.firstSafe {
                prevImg = first
            } else {
                continue
            }

            guard let newImg = (try? tmp.getElementsByTag("img"))?.firstSafe else { continue }

            if let attrs = prevImg.getAttributes() {
                for attr in attrs {
                    let nameBytes = attr.getKeyUTF8()
                    let valueBytes = attr.getValueUTF8()
                    if valueBytes.isEmpty { continue }

                    let isSrcAttr = nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.src) ||
                        nameBytes.equalsIgnoreCaseASCII(ReadabilityUTF8Arrays.srcset)
                    let value = String(decoding: valueBytes, as: UTF8.self)
                    let looksLikeImageURL = value.range(of: "\\.(jpg|jpeg|png|webp)", options: [.regularExpression, .caseInsensitive]) != nil
                    if !(isSrcAttr || looksLikeImageURL) { continue }

                    if newImg.attrOrEmptyUTF8(nameBytes) == valueBytes { continue }

                    if newImg.hasAttr(nameBytes) {
                        let nameString = String(decoding: nameBytes, as: UTF8.self)
                        let attrName = "data-old-" + nameString
                        _ = try? newImg.attr(attrName, value)
                    } else {
                        _ = try? newImg.attr(nameBytes, valueBytes)
                    }
                }
            }

            // Replace the placeholder element with the noscript image.
            if let replacement = tmp.children().firstSafe {
                _ = try? prevElement.replaceWith(replacement)
            }
        }
    }

    private func isSingleImage(_ node: Element) -> Bool {
        var current: Element? = node
        while let element = current {
            if element.tagNameUTF8() == ReadabilityUTF8Arrays.img {
                return true
            }
            if element.children().count != 1 {
                return false
            }
            if hasNonWhitespaceText(element) {
                return false
            }
            current = element.children().firstSafe
        }
        return false
    }

    private func removeStyles(_ document: Document) {
        removeNodes(in: document, tagName: "style")
    }

    /// Replaces 2 or more successive <br> elements with a single <p>.
    private func replaceBrs(_ document: Document, regEx: RegExUtil) {
        guard let body = document.body(), let brs = try? body.select("br") else { return }

        let phrasingElems: Set<[UInt8]> = [
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

        func isWhitespace(_ node: Node) -> Bool {
            if let text = node as? TextNode {
                return regEx.isWhitespace(text.getWholeText())
            }
            if let element = node as? Element {
                return element.tagNameUTF8() == ReadabilityUTF8Arrays.br
            }
            return false
        }

        var phrasingCache: [ObjectIdentifier: Bool] = [:]
        func isPhrasingContent(_ node: Node) -> Bool {
            if node is TextNode { return true }
            guard let element = node as? Element else { return false }
            let key = ObjectIdentifier(element)
            if let cached = phrasingCache[key] { return cached }
            let tagName = element.tagNameUTF8()
            if phrasingElems.contains(tagName) {
                phrasingCache[key] = true
                return true
            }
            if tagName == ReadabilityUTF8Arrays.a ||
                tagName == ReadabilityUTF8Arrays.del ||
                tagName == ReadabilityUTF8Arrays.ins {
                let value = element.getChildNodes().allSatisfy(isPhrasingContent(_:))
                phrasingCache[key] = value
                return value
            }
            phrasingCache[key] = false
            return false
        }

        func nextNodeSkippingWhitespace(_ node: Node?) -> Node? {
            var next = node
            while let current = next {
                if current is Element { return current }
                if let text = current as? TextNode, regEx.isWhitespace(text.getWholeText()) {
                    next = current.nextSibling()
                    continue
                }
                return current
            }
            return nil
        }

        for br in brs {
            var next: Node? = br.nextSibling()
            var replaced = false

            // Remove all <br>s in the chain except for the first one (the current `br`).
            while let n = nextNodeSkippingWhitespace(next), let elem = n as? Element {
                let tagName = elem.tagNameUTF8()
                if tagName != ReadabilityUTF8Arrays.br { break }
                replaced = true
                let sibling = elem.nextSibling()
                try? elem.remove()
                next = sibling
            }

            if replaced {
                let p: Element = {
                    if let doc = br.ownerDocument(), let el = try? doc.createElement("p") { return el }
                    return Element(try! Tag.valueOf("p"), "")
                }()
                _ = try? br.replaceWith(p)

                next = p.nextSibling()
                while let current = next {
                    if let brElem = current as? Element {
                        let tagName = brElem.tagNameUTF8()
                        if tagName == ReadabilityUTF8Arrays.br {
                        if let nextElem = nextNodeSkippingWhitespace(brElem.nextSibling()) as? Element,
                           nextElem.tagNameUTF8() == ReadabilityUTF8Arrays.br {
                            break
                        }
                        }
                    }

                    if !isPhrasingContent(current) {
                        break
                    }

                    let sibling = current.nextSibling()
                    _ = try? p.appendChild(current)
                    next = sibling
                }

                while let last = p.getChildNodes().last, isWhitespace(last) {
                    _ = try? last.remove()
                }

                if let parent = p.parent(), parent.tagNameUTF8() == ReadabilityUTF8Arrays.p {
                    _ = try? parent.tagName(ReadabilityUTF8Arrays.div)
                }
            }
        }
    }
}
