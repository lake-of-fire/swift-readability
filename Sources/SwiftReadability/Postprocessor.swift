// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import Foundation
import SwiftSoup

/// Final cleanup after article extraction.
final class Postprocessor: ProcessorBase {
    private let classesToPreserve: Set<String> = ["page"]
    // ICU and ECMAScript disagree about `\s`/`\S` (notably U+0085 and U+FEFF).
    // Spell out ECMA-262's whitespace set so srcset tokenization matches Mozilla.
    private let srcsetUrlPattern = try! NSRegularExpression(
        pattern: #"([^\u0009\u000A\u000B\u000C\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+)([\u0009\u000A\u000B\u000C\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+[0-9.]+[xw])?([\u0009\u000A\u000B\u000C\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]*(?:,|$))"#,
        options: []
    )

    func postProcessContent(originalDocument: Document,
                            articleContent: Element,
                            articleUri: String,
                            keepClasses: Bool,
                            classesToPreserve: [String] = []) {
        fixRelativeUris(originalDocument: originalDocument, element: articleContent, articleUri: articleUri)
        simplifyNestedElements(articleContent)
        guard !keepClasses else { return }
        let preserve = self.classesToPreserve.union(classesToPreserve)
        cleanClasses(node: articleContent, classesToPreserve: preserve)
    }

    // MARK: - Nested element simplification (Readability.js _simplifyNestedElements)

    private func simplifyNestedElements(_ articleContent: Element) {
        var node: Element? = articleContent

        while let current = node {
            if current.parent() != nil,
               (current.tagNameUTF8() == ReadabilityUTF8Arrays.div || current.tagNameUTF8() == ReadabilityUTF8Arrays.section),
               !(current.idSafe().hasPrefix("readability")) {
                if isElementWithoutContent(current) {
                    node = removeAndGetNext(current)
                    continue
                }

                if hasSingleTagInsideElement(current, tagName: ReadabilityUTF8Arrays.div) ||
                    hasSingleTagInsideElement(current, tagName: ReadabilityUTF8Arrays.section) {
                    let child = current.child(0)

                    // Copy attributes from parent to child.
                    if let attrs = current.getAttributes() {
                        for attr in attrs {
                            _ = try? child.attr(attr.getKeyUTF8(), attr.getValueUTF8())
                        }
                    }

                    _ = try? current.replaceWith(child)
                    node = child
                    continue
                }
            }

            node = getNextNode(from: current)
        }
    }

    private func isElementWithoutContent(_ node: Element) -> Bool {
        let textBlank = !hasNonWhitespaceText(node)
        let childCount = node.children().count
        if textBlank && childCount == 0 { return true }
        // Avoid SwiftSoup tag-query caching; this must reflect current DOM state.
        let brHr = ((try? node.select("br").count) ?? 0) + ((try? node.select("hr").count) ?? 0)
        return textBlank && (childCount == 0 || childCount == brHr)
    }

    private func hasSingleTagInsideElement(_ element: Element, tagName: [UInt8]) -> Bool {
        if element.children().count != 1 { return false }
        let onlyChild = element.child(0)
        guard onlyChild.tagNameUTF8() == tagName else { return false }
        for node in element.getChildNodes() {
            if let text = node as? TextNode,
               javaScriptHasTrailingNonWhitespace(text.getWholeText()) {
                return false
            }
        }
        return true
    }

    private func removeAndGetNext(_ node: Element) -> Element? {
        let nextNode = getNextNode(from: node, ignoreSelfAndKids: true)
        _ = try? node.remove()
        return nextNode
    }

    private func getNextNode(from node: Element, ignoreSelfAndKids: Bool = false) -> Element? {
        if !ignoreSelfAndKids, node.children().count > 0 {
            return node.children().firstSafe
        }
        if let next = try? node.nextElementSibling() { return next }
        var parent = node.parent()
        while let p = parent, (try? p.nextElementSibling()) == nil {
            parent = p.parent()
        }
        if let sib = try? parent?.nextElementSibling() { return sib }
        return nil
    }

    private func fixRelativeUris(originalDocument: Document, element: Element, articleUri: String) {
        // Mozilla calls the browser's `new URL(reference, baseURI)` here. Foundation.URL
        // implements different legacy URL rules (notably for backslashes, default ports,
        // encoded dot-segments, and invalid hosts), so using it would make the extracted
        // document platform-dependent. WebURL implements the WHATWG parser directly in
        // Swift and validates it against the browser web-platform-tests.
        guard let urlContext = BrowserURLContext(
            document: originalDocument,
            documentURI: articleUri
        ) else { return }

        func toAbsoluteURI(_ uri: String) -> String {
            // Leave hash links alone if the base URI matches the document URI.
            if urlContext.baseURL == urlContext.documentURL, uri.first == "#" {
                return uri
            }

            // The URL constructor is deliberately forgiving for path escapes and deliberately
            // strict for invalid hosts. A failed parse must preserve the original attribute.
            return urlContext.resolve(uri) ?? uri
        }

        // <a href="">
        // Avoid SwiftSoup tag-query caching; we mutate the DOM in this phase.
        if let links = try? element.select("a") {
            for link in links {
                let href = String(decoding: link.attrOrEmptyUTF8(ReadabilityUTF8Arrays.href), as: UTF8.self)
                if href.isEmpty { continue }

                if href.hasPrefix("javascript:") {
                    replaceJavascriptLink(link)
                } else {
                    let resolved = toAbsoluteURI(href)
                    _ = try? link.attr(ReadabilityUTF8Arrays.href, resolved.utf8Array)
                }
            }
        }

        // media tags: src/poster/srcset
        if let medias = try? element.select("img, picture, figure, video, audio, source") {
            for media in medias {
                let src = String(decoding: media.attrOrEmptyUTF8(ReadabilityUTF8Arrays.src), as: UTF8.self)
                if !src.isEmpty {
                    let resolved = toAbsoluteURI(src)
                    _ = try? media.attr(ReadabilityUTF8Arrays.src, resolved.utf8Array)
                }

                let poster = String(decoding: media.attrOrEmptyUTF8(ReadabilityUTF8Arrays.poster), as: UTF8.self)
                if !poster.isEmpty {
                    let resolved = toAbsoluteURI(poster)
                    _ = try? media.attr(ReadabilityUTF8Arrays.poster, resolved.utf8Array)
                }

                let srcset = String(decoding: media.attrOrEmptyUTF8(ReadabilityUTF8Arrays.srcset), as: UTF8.self)
                if !srcset.isEmpty {
                    let newSrcset = replaceMatches(srcsetUrlPattern, in: srcset) { match, nsString in
                        let urlPart = nsString.substring(with: match.range(at: 1))
                        let descriptorRange = match.range(at: 2)
                        let commaPart = nsString.substring(with: match.range(at: 3))
                        let descriptor = descriptorRange.location != NSNotFound ? nsString.substring(with: descriptorRange) : ""
                        return toAbsoluteURI(urlPart) + descriptor + commaPart
                    }
                    _ = try? media.attr(ReadabilityUTF8Arrays.srcset, newSrcset.utf8Array)
                }
            }
        }
    }

    private func replaceJavascriptLink(_ link: Element) {
        let children = Array(link.getChildNodes())
        if children.count == 1, children[0] is TextNode {
            let wholeText = (children[0] as? TextNode)?.getWholeText() ?? ""
            let text = TextNode(wholeText, nil)
            _ = try? link.replaceWith(text)
        } else {
            let container: Element = {
                if let doc = link.ownerDocument(), let span = try? doc.createElement("span") {
                    return span
                }
                return Element(try! Tag.valueOf("span"), "")
            }()
            for child in children {
                _ = try? child.remove()
                _ = try? container.appendChild(child)
            }
            if (try? link.replaceWith(container)) == nil {
                if let parent = link.parent() {
                    let index = link.siblingIndex
                    _ = try? link.remove()
                    _ = try? parent.insertChildren(index, [container])
                }
            }
        }
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

    private func cleanClasses(node: Element, classesToPreserve: Set<String>) {
        let classAttr = String(decoding: node.attrOrEmptyUTF8(ReadabilityUTF8Arrays.class_), as: UTF8.self)
        let keptClassNames = javaScriptWhitespaceSeparatedTokens(classAttr)
            .filter(classesToPreserve.contains(_:))

        if keptClassNames.isEmpty {
            _ = try? node.removeAttr(ReadabilityUTF8Arrays.class_)
        } else {
            _ = try? node.attr(ReadabilityUTF8Arrays.class_, keptClassNames.joined(separator: " ").utf8Array)
        }
        for child in node.children() {
            cleanClasses(node: child, classesToPreserve: classesToPreserve)
        }
    }

    /// Mirrors JavaScript `split(/\s+/)`. Empty edge tokens can be omitted here
    /// because `_cleanClasses` immediately filters against nonempty class names.
    private func javaScriptWhitespaceSeparatedTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = String.UnicodeScalarView()

        func flushCurrent() {
            guard !current.isEmpty else { return }
            tokens.append(String(current))
            current.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if javaScriptIsWhitespace(scalar) {
                flushCurrent()
            } else {
                current.append(scalar)
            }
        }
        flushCurrent()
        return tokens
    }
}
