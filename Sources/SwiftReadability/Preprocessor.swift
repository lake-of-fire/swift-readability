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
        removeScripts(document)
        removeStyles(document)
        removeComments(document)
        replaceBrs(document, regEx: regEx)
        replaceNodes(in: document, tagName: "font", newTagName: "span")
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
            try? tmp.html(inner)

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
                        try? newImg.attr(attrName, value)
                    } else {
                        try? newImg.attr(nameBytes, valueBytes)
                    }
                }
            }

            // Replace the placeholder element with the noscript image.
            if let replacement = tmp.children().firstSafe {
                try? prevElement.replaceWith(replacement)
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
                try? br.replaceWith(p)

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
                    try? p.appendChild(current)
                    next = sibling
                }

                while let last = p.getChildNodes().last, isWhitespace(last) {
                    try? last.remove()
                }

                if let parent = p.parent(), parent.tagNameUTF8() == ReadabilityUTF8Arrays.p {
                    try? parent.tagName(ReadabilityUTF8Arrays.div)
                }
            }
        }
    }
}
