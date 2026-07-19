// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import Foundation
import SwiftSoup

/// Common helpers shared by pre/post processors and article grabber.
class ProcessorBase {
    /// Remove nodes of a certain tag name optionally filtered.
    func removeNodes(in element: Element, tagName: String, filter: ((Element) -> Bool)? = nil) {
        // Prefer `select` over `getElementsByTag` to avoid SwiftSoup's cached tag-index
        // returning stale results after DOM mutations.
        guard let elements = try? element.select(tagName) else { return }
        for child in elements.reversed() where child !== element {
            if child.parent() != nil {
                if filter?(child) ?? true {
                    printAndRemove(node: child)
                }
            }
        }
    }

    func printAndRemove(node: Node) {
        if node.parent() != nil {
            try? node.remove()
        }
    }

    func replaceNodes(in parent: Element, tagName: String, newTagName: String) {
        guard let elements = try? parent.getElementsByTag(tagName) else { return }
        for element in elements {
            _ = try? element.tagName(newTagName)
        }
    }

    /// Finds the next element, starting from the given node, ignoring non-element
    /// nodes whose DOM `textContent` is entirely JavaScript whitespace.
    func nextElement(from node: Node?, regEx: RegExUtil) -> Element? {
        var next: Node? = node
        while let current = next {
            if let element = current as? Element { return element }
            if isMozillaWhitespaceNonElementNode(current, regEx: regEx) {
                next = current.nextSibling()
                continue
            }
            break
        }
        return next as? Element
    }

    /// Get the inner text of a node, stripping extra whitespace.
    func getInnerText(_ element: Element, regEx: RegExUtil? = nil, normalizeSpaces: Bool = true) -> String {
        let textContent = javaScriptTrim(textContentPreservingWhitespace(of: element))
        if normalizeSpaces, let regEx {
            return regEx.normalize(textContent)
        }
        return textContent
    }

    /// Fast check for any non-whitespace text descendant without serializing full text.
    func hasNonWhitespaceText(_ element: Element) -> Bool {
        var stack = element.getChildNodes()
        while let node = stack.popLast() {
            if let text = node as? TextNode {
                if !javaScriptIsWhitespaceOnly(text.getWholeText()) {
                    return true
                }
            } else if let el = node as? Element {
                let children = el.getChildNodes()
                if !children.isEmpty {
                    stack.append(contentsOf: children)
                }
            }
        }
        return false
    }

    /// Fast JavaScript-length comparison using UTF-8 bytes as an upper bound.
    /// Falls back to an exact UTF-16 code-unit count only when needed.
    func isTextLengthAtLeast(_ text: String, _ min: Int) -> Bool {
        if text.utf8.count < min { return false }
        return javaScriptStringLength(text) >= min
    }

    /// Fast JavaScript-length comparison using UTF-8 bytes as an upper bound.
    /// Falls back to an exact UTF-16 code-unit count only when needed.
    func isTextLengthLessThan(_ text: String, _ max: Int) -> Bool {
        if text.utf8.count < max { return true }
        return javaScriptStringLength(text) < max
    }
}

/// Mozilla's `_nextNode` skips any non-element whose `textContent` matches its
/// whitespace expression. Comments are observable here: unlike an element's
/// aggregate `textContent`, a Comment node's own `textContent` is its data.
func isMozillaWhitespaceNonElementNode(_ node: Node, regEx: RegExUtil) -> Bool {
    if node is Element { return false }
    if let text = node as? TextNode {
        return regEx.isWhitespace(text.getWholeText())
    }
    if let data = node as? DataNode {
        return regEx.isWhitespace(data.getWholeData())
    }
    if let comment = node as? Comment {
        return regEx.isWhitespace(comment.getData())
    }
    // For example, DocumentType.textContent is null in the browser. JavaScript
    // coerces that null to "null" for RegExp.test, so it must not be skipped.
    return false
}
