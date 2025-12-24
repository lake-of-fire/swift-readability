import SwiftSoup

extension Element {
    func attrOrEmpty(_ key: String) -> String {
        (try? attr(key)) ?? ""
    }
    func attrOrEmptyUTF8(_ key: [UInt8]) -> [UInt8] {
        (try? attr(key)) ?? []
    }
    func classNameSafe() -> String {
        (try? className()) ?? ""
    }
    func idSafe() -> String {
        id()
    }
    func tagNameSafe() -> String {
        tagName()
    }

    /// Fallback token to detect text mutations when SwiftSoup doesn't expose one.
    /// Uses the full text hash plus child count to invalidate caches when content changes.
    func textMutationVersionToken() -> Int {
        let textHash = textContentPreservingWhitespace(of: self).hashValue
        return textHash ^ getChildNodes().count
    }
}

extension Elements {
    var firstSafe: Element? { first() }
}

extension Array where Element == UInt8 {
    @inline(__always)
    func equalsIgnoreCaseASCII(_ other: [UInt8]) -> Bool {
        guard self.count == other.count else { return false }
        for (byte1, byte2) in zip(self.lazy, other.lazy) {
            let lower1 = (byte1 >= 65 && byte1 <= 90) ? byte1 + 32 : byte1
            let lower2 = (byte2 >= 65 && byte2 <= 90) ? byte2 + 32 : byte2
            if lower1 != lower2 { return false }
        }
        return true
    }
}

@inline(__always)
func textContentPreservingWhitespace(of node: Node) -> String {
    if let text = node as? TextNode {
        return text.getWholeText()
    }
    if let data = node as? DataNode {
        return data.getWholeData()
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
