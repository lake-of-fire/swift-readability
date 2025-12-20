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
                    printAndRemove(node: child, reason: "removeNode('" + tagName + "')")
                }
            }
        }
    }

    func printAndRemove(node: Node, reason: String) {
        if node.parent() != nil {
            // debug logging omitted
            try? node.remove()
        }
    }

    func replaceNodes(in parent: Element, tagName: String, newTagName: String) {
        guard let elements = try? parent.getElementsByTag(tagName) else { return }
        for element in elements {
            try? element.tagName(newTagName)
        }
    }

    /// Finds the next element, starting from the given node, ignoring whitespace text nodes.
    func nextElement(from node: Node?, regEx: RegExUtil) -> Element? {
        var next: Node? = node
        while let current = next {
            if let element = current as? Element { return element }
            if let text = current as? TextNode, regEx.isWhitespace(text.text()) {
                next = current.nextSibling()
                continue
            }
            break
        }
        return next as? Element
    }

    /// Get the inner text of a node, stripping extra whitespace.
    func getInnerText(_ element: Element, regEx: RegExUtil? = nil, normalizeSpaces: Bool = true) -> String {
        let textContent = (try? element.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizeSpaces, let regEx {
            return regEx.normalize(textContent)
        }
        return textContent
    }

    /// Fast length comparisons using UTF-8 byte count as an upper bound.
    /// Falls back to full character count only when needed.
    func isTextLengthAtLeast(_ text: String, _ min: Int) -> Bool {
        if text.utf8.count < min { return false }
        return text.count >= min
    }

    func isTextLengthLessThan(_ text: String, _ max: Int) -> Bool {
        if text.utf8.count < max { return true }
        return text.count < max
    }
}
