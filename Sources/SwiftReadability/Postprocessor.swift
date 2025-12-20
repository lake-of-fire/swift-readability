import Foundation
import SwiftSoup

/// Final cleanup after article extraction.
final class Postprocessor {
    private let classesToPreserve: Set<String> = ["page"]
    private let srcsetUrlPattern = try! NSRegularExpression(pattern: "(\\S+)(\\s+[\\d.]+[xw])?(\\s*(?:,|$))", options: [])

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
                    guard let child = try? current.child(0) else {
                        node = getNextNode(from: current)
                        continue
                    }

                    // Copy attributes from parent to child.
                    if let attrs = current.getAttributes() {
                        for attr in attrs {
                            try? child.attr(attr.getKey(), attr.getValue())
                        }
                    }

                    try? current.replaceWith(child)
                    node = child
                    continue
                }
            }

            node = getNextNode(from: current)
        }
    }

    private func isElementWithoutContent(_ node: Element) -> Bool {
        let textValue = (try? node.text()) ?? ""
        let textBlank = textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let childCount = node.children().count
        if textBlank && childCount == 0 { return true }
        // Avoid SwiftSoup tag-query caching; this must reflect current DOM state.
        let brHr = ((try? node.select("br").count) ?? 0) + ((try? node.select("hr").count) ?? 0)
        return textBlank && (childCount == 0 || childCount == brHr)
    }

    private func hasSingleTagInsideElement(_ element: Element, tagName: [UInt8]) -> Bool {
        if element.children().count != 1 { return false }
        guard let onlyChild = try? element.child(0), onlyChild.tagNameUTF8() == tagName else { return false }
        for node in element.getChildNodes() {
            if let text = node as? TextNode, !text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }

    private func removeAndGetNext(_ node: Element) -> Element? {
        let nextNode = getNextNode(from: node, ignoreSelfAndKids: true)
        try? node.remove()
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
        let documentURI = articleUri
        let baseURI = computeBaseURI(originalDocument: originalDocument, documentURI: documentURI)
        guard let baseURL = URL(string: baseURI) else { return }

        func normalizedAbsoluteString(_ url: URL) -> String {
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            if let host = comps.host {
                comps.host = host.lowercased()
            }
            if let scheme = comps.scheme {
                comps.scheme = scheme.lowercased()
            }
            return comps.url?.absoluteString ?? url.absoluteString
        }

        func percentEncodeForURL(_ uri: String) -> String {
            // Encode non-ASCII and other disallowed code points while preserving existing URL syntax.
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
            var result = ""
            result.reserveCapacity(uri.utf16.count)
            for scalar in uri.unicodeScalars {
                if allowed.contains(scalar) {
                    result.append(Character(scalar))
                } else {
                    for byte in String(scalar).utf8 {
                        result += String(format: "%%%02X", byte)
                    }
                }
            }
            return result
        }

        func toAbsoluteURI(_ uri: String) -> String {
            // Leave hash links alone if the base URI matches the document URI.
            if baseURI == documentURI, uri.first == "#" {
                return uri
            }
            if uri.lowercased().hasPrefix("data:") {
                return uri
            }
            if uri.lowercased().hasPrefix("file:") {
                // Match WHATWG URL normalization used by Readability.js.
                // `new URL("file:///C|/path").href` -> `file:///C:/path`
                return uri.replacingOccurrences(
                    of: #"^file:///([A-Za-z])\|/"#,
                    with: "file:///$1:/",
                    options: .regularExpression
                )
            }
            if let resolved = URL(string: uri, relativeTo: baseURL)?.absoluteURL {
                // Match WHATWG URL serialization for origin-only URLs by ensuring a "/" path.
                guard let host = resolved.host, !host.isEmpty else {
                    return normalizedAbsoluteString(resolved)
                }
                if resolved.path.isEmpty, var comps = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
                    comps.path = "/"
                    if let host = comps.host {
                        comps.host = host.lowercased()
                    }
                    if let scheme = comps.scheme {
                        comps.scheme = scheme.lowercased()
                    }
                    return comps.url?.absoluteString ?? normalizedAbsoluteString(resolved)
                }
                return normalizedAbsoluteString(resolved)
            }

            let encoded = percentEncodeForURL(uri)
            if encoded != uri, let resolved = URL(string: encoded, relativeTo: baseURL)?.absoluteURL {
                guard let host = resolved.host, !host.isEmpty else {
                    return normalizedAbsoluteString(resolved)
                }
                if resolved.path.isEmpty, var comps = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
                    comps.path = "/"
                    if let host = comps.host {
                        comps.host = host.lowercased()
                    }
                    if let scheme = comps.scheme {
                        comps.scheme = scheme.lowercased()
                    }
                    return comps.url?.absoluteString ?? normalizedAbsoluteString(resolved)
                }
                return normalizedAbsoluteString(resolved)
            }

            // Foundation URL parsing fails for some strings that WHATWG URL treats as relative (e.g. a
            // percent-escaped prefix followed by a scheme-like substring). Fall back to manual RFC3986-ish resolution.
            let baseDir = baseURL.deletingLastPathComponent().absoluteString
            if encoded.hasPrefix("//"), let scheme = baseURL.scheme {
                let candidate = "\(scheme.lowercased()):\(encoded)"
                return URL(string: candidate).map(normalizedAbsoluteString(_:)) ?? candidate
            }
            if encoded.hasPrefix("/") {
                if let scheme = baseURL.scheme, let host = baseURL.host {
                    let portPart = baseURL.port.map { ":\($0)" } ?? ""
                    return "\(scheme.lowercased())://\(host.lowercased())\(portPart)\(encoded)"
                }
                return baseDir + encoded.dropFirst()
            }
            if encoded.hasPrefix("#") {
                let baseNoFragment = baseURI.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? baseURI
                return baseNoFragment + encoded
            }
            if encoded.hasPrefix("?") {
                let baseNoQuery = baseURI.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? baseURI
                return baseNoQuery + encoded
            }
            return baseDir + encoded
        }

        // <a href="">
        // Avoid SwiftSoup tag-query caching; we mutate the DOM in this phase.
        if let links = try? element.select("a") {
            for link in links {
                let href = link.attrOrEmpty("href")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if href.isEmpty { continue }

                if href.hasPrefix("javascript:") {
                    replaceJavascriptLink(link)
                } else {
                    try? link.attr("href", toAbsoluteURI(href))
                }
            }
        }

        // media tags: src/poster/srcset
        if let medias = try? element.select("img, picture, figure, video, audio, source") {
            for media in medias {
                let src = media.attrOrEmpty("src")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !src.isEmpty {
                    try? media.attr("src", toAbsoluteURI(src))
                }

                let poster = media.attrOrEmpty("poster")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !poster.isEmpty {
                    try? media.attr("poster", toAbsoluteURI(poster))
                }

                let srcset = media.attrOrEmpty("srcset")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !srcset.isEmpty {
                    let newSrcset = replaceMatches(srcsetUrlPattern, in: srcset) { match, nsString in
                        let urlPart = nsString.substring(with: match.range(at: 1))
                        let descriptorRange = match.range(at: 2)
                        let commaPart = nsString.substring(with: match.range(at: 3))
                        let descriptor = descriptorRange.location != NSNotFound ? nsString.substring(with: descriptorRange) : ""
                        return toAbsoluteURI(urlPart) + descriptor + commaPart
                    }
                    try? media.attr("srcset", newSrcset)
                }
            }
        }
    }

    private func computeBaseURI(originalDocument: Document, documentURI: String) -> String {
        guard let documentURL = URL(string: documentURI) else { return documentURI }
        guard let baseElement = try? originalDocument.select("base[href]").first(),
              let baseHref = try? baseElement.attr("href")
        else {
            return documentURI
        }

        let trimmed = baseHref.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return documentURI }
        return URL(string: trimmed, relativeTo: documentURL)?.absoluteString ?? documentURI
    }

    private func replaceJavascriptLink(_ link: Element) {
        let children = Array(link.getChildNodes())
        if children.count == 1, children[0] is TextNode {
            let wholeText = (children[0] as? TextNode)?.getWholeText() ?? ""
            let text = TextNode(wholeText, nil)
            try? link.replaceWith(text)
        } else {
            let container: Element = {
                if let doc = link.ownerDocument(), let span = try? doc.createElement("span") {
                    return span
                }
                return Element(try! Tag.valueOf("span"), "")
            }()
            for child in children {
                try? child.remove()
                try? container.appendChild(child)
            }
            if (try? link.replaceWith(container)) == nil {
                if let parent = link.parent() {
                    let index = link.siblingIndex
                    try? link.remove()
                    try? parent.insertChildren(index, [container])
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
        let classAttr = node.attrOrEmpty("class")
        var seen: Set<String> = []
        let keptClassNames = classAttr
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { classesToPreserve.contains($0) && seen.insert($0).inserted }

        if keptClassNames.isEmpty {
            try? node.removeAttr("class")
        } else {
            try? node.attr("class", keptClassNames.joined(separator: " "))
        }
        for child in node.children() {
            cleanClasses(node: child, classesToPreserve: classesToPreserve)
        }
    }
}
