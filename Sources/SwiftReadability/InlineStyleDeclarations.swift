import Foundation

/// The CSSOM subset used by Mozilla Readability's inline visibility checks.
///
/// Mozilla reads `element.style.display` and `element.style.visibility`, not the
/// raw `style` attribute. Reproducing that distinction matters: declaration
/// boundaries, comments, CSS escapes, malformed-token recovery, property
/// grammar, duplicate declarations, and priority all affect the two values.
/// This parser intentionally implements only those two properties, but follows
/// the pinned jsdom CSSOM used by the Mozilla fixture oracle at each boundary.
struct InlineStyleDeclarations {
    private struct Declaration {
        /// `nil` represents a declaration accepted by the CSS value lexer but
        /// not serializable by the pinned display descriptor (`block math`).
        /// Such a declaration still participates in duplicate/priority rules.
        let value: String?
        let important: Bool
    }

    private enum ParsedPropertyValue {
        case rejected
        case accepted(String?)
    }

    private var declarations: [String: Declaration] = [:]

    private static let globalKeywords: Set<String> = [
        "inherit", "initial", "revert", "revert-layer", "unset"
    ]

    private static let displayOutsideKeywords: Set<String> = [
        "block", "inline", "run-in"
    ]
    private static let displayInsideKeywords: Set<String> = [
        "flow", "flow-root", "table", "flex", "grid", "ruby"
    ]
    private static let displayFlowKeywords: Set<String> = ["flow", "flow-root"]
    private static let singleDisplayKeywords: Set<String> = [
        "block", "inline", "run-in",
        "flow", "flow-root", "table", "flex", "grid", "ruby", "math",
        "list-item",
        "table-row-group", "table-header-group", "table-footer-group",
        "table-row", "table-cell", "table-column-group", "table-column", "table-caption",
        "ruby-base", "ruby-text", "ruby-base-container", "ruby-text-container",
        "contents", "none",
        "inline-block", "inline-list-item", "inline-table", "inline-flex", "inline-grid",
        "-ms-inline-flexbox", "-ms-grid", "-ms-inline-grid",
        "-webkit-flex", "-webkit-inline-flex", "-webkit-box", "-webkit-inline-box",
        "-moz-inline-stack", "-moz-box", "-moz-inline-box",
        "grid-lanes", "inline-grid-lanes",
    ]
    private static let visibilityKeywords: Set<String> = [
        "visible", "hidden", "force-hidden", "collapse"
    ]

    init(_ source: String) {
        guard !source.isEmpty else { return }

        for segment in Self.declarationSegments(in: source) {
            guard let (rawName, rawValue) = Self.nameAndValue(in: segment),
                  let name = Self.propertyName(from: rawName),
                  name == "display" || name == "visibility",
                  let declaration = Self.parseDeclarationValue(rawValue, for: name)
            else {
                continue
            }

            // The pinned CSSOM retains the first important declaration. A
            // later normal or important duplicate cannot replace it; absent
            // priority, the later valid declaration wins.
            if declarations[name]?.important == true {
                continue
            }
            declarations[name] = declaration
        }
    }

    func value(for property: String) -> String? {
        declarations[Self.asciiLowercased(property)]?.value
    }

    private static func parseDeclarationValue(_ rawSource: String, for property: String) -> Declaration? {
        let prioritySplit = splitPriority(from: rawSource)
        guard prioritySplit.valid else { return nil }

        let rawValue = rawCSSValue(from: prioritySplit.value)
        let parsed: ParsedPropertyValue
        if hasVarFunction(in: rawValue) {
            // This deliberately mirrors jsdom's pinned raw `hasVarFunc`
            // shortcut, including its case sensitivity and occurrence inside
            // otherwise-invalid strings/functions.
            parsed = .accepted(javaScriptTrim(rawValue))
        } else if property == "display" {
            parsed = parseDisplay(rawValue)
        } else {
            parsed = parseVisibility(rawValue)
        }

        switch parsed {
        case .rejected:
            return nil
        case .accepted(let value):
            return Declaration(value: value, important: prioritySplit.important)
        }
    }

    // MARK: - Property values

    private static func parseDisplay(_ rawValue: String) -> ParsedPropertyValue {
        guard let tokens = identifierTokens(in: rawValue), !tokens.isEmpty else {
            return .rejected
        }

        if tokens.count == 1, globalKeywords.contains(tokens[0]) {
            return .accepted(tokens[0])
        }
        guard displayGrammarAccepts(tokens) else { return .rejected }

        // The pinned descriptor normalizes modern multi-keyword syntax into
        // the legacy serialization exposed through `element.style.display`.
        return .accepted(normalizedDisplayValue(tokens))
    }

    private static func parseVisibility(_ rawValue: String) -> ParsedPropertyValue {
        guard let tokens = identifierTokens(in: rawValue), tokens.count == 1 else {
            return .rejected
        }
        let value = tokens[0]
        guard globalKeywords.contains(value) || visibilityKeywords.contains(value) else {
            return .rejected
        }
        return .accepted(value)
    }

    private static func displayGrammarAccepts(_ tokens: [String]) -> Bool {
        switch tokens.count {
        case 1:
            return singleDisplayKeywords.contains(tokens[0])
        case 2:
            let first = tokens[0]
            let second = tokens[1]
            let outsideAndInside =
                (displayOutsideKeywords.contains(first) && displayInsideKeywords.contains(second)) ||
                (displayOutsideKeywords.contains(second) && displayInsideKeywords.contains(first))
            let listItemPair =
                (first == "list-item" &&
                    (displayOutsideKeywords.contains(second) || displayFlowKeywords.contains(second))) ||
                (second == "list-item" &&
                    (displayOutsideKeywords.contains(first) || displayFlowKeywords.contains(first)))
            let outsideAndMath =
                (displayOutsideKeywords.contains(first) && second == "math") ||
                (displayOutsideKeywords.contains(second) && first == "math")
            return outsideAndInside || listItemPair || outsideAndMath
        case 3:
            return tokens.filter { $0 == "list-item" }.count == 1 &&
                tokens.filter { displayOutsideKeywords.contains($0) }.count == 1 &&
                tokens.filter { displayFlowKeywords.contains($0) }.count == 1
        default:
            return false
        }
    }

    private static func normalizedDisplayValue(_ tokens: [String]) -> String? {
        switch tokens.count {
        case 1:
            return tokens[0] == "flow" ? "block" : tokens[0]
        case 2:
            let first = tokens[0]
            let second = tokens[1]
            let outer: String
            let inner: String

            if first == "list-item" {
                outer = second
                inner = first
            } else if second == "list-item" {
                outer = first
                inner = second
            } else if displayOutsideKeywords.contains(first) {
                outer = first
                inner = second
            } else if displayOutsideKeywords.contains(second) {
                outer = second
                inner = first
            } else {
                return nil
            }

            if inner == "list-item" {
                switch outer {
                case "block", "flow":
                    return "list-item"
                case "flow-root", "inline", "run-in":
                    return "\(outer) list-item"
                default:
                    return nil
                }
            }

            switch outer {
            case "block":
                switch inner {
                case "flow": return "block"
                case "flow-root", "flex", "grid", "table": return inner
                case "ruby": return "block ruby"
                default: return nil
                }
            case "inline":
                switch inner {
                case "flow": return "inline"
                case "flow-root": return "inline-block"
                case "flex", "grid", "table": return "inline-\(inner)"
                case "ruby": return "ruby"
                default: return nil
                }
            case "run-in":
                switch inner {
                case "flow": return "run-in"
                case "flow-root", "flex", "grid", "table", "ruby":
                    return "run-in \(inner)"
                default:
                    return nil
                }
            default:
                return nil
            }
        case 3:
            guard let outside = tokens.first(where: { displayOutsideKeywords.contains($0) }),
                  let flow = tokens.first(where: { displayFlowKeywords.contains($0) }),
                  tokens.contains("list-item")
            else {
                return nil
            }
            switch outside {
            case "block":
                return flow == "flow" ? "list-item" : "flow-root list-item"
            case "inline", "run-in":
                return flow == "flow"
                    ? "\(outside) list-item"
                    : "\(outside) flow-root list-item"
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// Returns lowercased identifier tokens after CSS comments and CSS
    /// whitespace have formed token boundaries. The pinned css-tree lexer does
    /// not canonicalize escapes before matching property grammar, so any escape
    /// in a standard display/visibility value rejects that value.
    private static func identifierTokens(in source: String) -> [String]? {
        let scalars = Array(javaScriptTrim(source).unicodeScalars)
        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        var index = 0

        func finishToken() {
            guard !current.isEmpty else { return }
            tokens.append(asciiLowercased(String(current)))
            current.removeAll(keepingCapacity: true)
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if isCSSWhitespace(scalar) {
                finishToken()
                index += 1
                continue
            }
            if startsComment(in: scalars, at: index) {
                finishToken()
                index = indexAfterComment(in: scalars, from: index)
                continue
            }
            if scalar.value == 0x5C { // CSS escape
                return nil
            }
            guard isIdentifierNameScalar(scalar) else { return nil }
            current.append(scalar)
            index += 1
        }
        finishToken()
        return tokens
    }

    // MARK: - Declaration parsing

    /// Splits a declaration list only at top-level semicolons. CSS escapes,
    /// strings, comments, and all three simple-block forms protect embedded
    /// semicolons. An unescaped newline ends a bad string, matching CSS Syntax
    /// recovery and allowing the next declaration to be parsed.
    private static func declarationSegments(in source: String) -> [String] {
        let scalars = Array(source.unicodeScalars)
        var segments: [String] = []
        var current = String.UnicodeScalarView()
        var quote: UInt32?
        var blockStack: [UInt32] = []
        var index = 0

        func finishSegment() {
            segments.append(String(current))
            current.removeAll(keepingCapacity: true)
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if let activeQuote = quote {
                if scalar.value == 0x5C {
                    appendEscape(in: scalars, at: &index, to: &current)
                    continue
                }
                current.append(scalar)
                index += 1
                if scalar.value == activeQuote {
                    quote = nil
                } else if isCSSNewline(scalar) {
                    quote = nil
                }
                continue
            }

            if startsComment(in: scalars, at: index) {
                appendComment(in: scalars, at: &index, to: &current)
                continue
            }
            if scalar.value == 0x5C {
                appendEscape(in: scalars, at: &index, to: &current)
                continue
            }
            if scalar.value == 0x22 || scalar.value == 0x27 {
                quote = scalar.value
                current.append(scalar)
                index += 1
                continue
            }
            if let closing = matchingClose(for: scalar.value) {
                blockStack.append(closing)
                current.append(scalar)
                index += 1
                continue
            }
            if blockStack.last == scalar.value {
                blockStack.removeLast()
                current.append(scalar)
                index += 1
                continue
            }
            if scalar.value == 0x3B, blockStack.isEmpty { // ;
                finishSegment()
                index += 1
                continue
            }

            current.append(scalar)
            index += 1
        }
        finishSegment()
        return segments
    }

    private static func nameAndValue(in declaration: String) -> (String, String)? {
        let scalars = Array(declaration.unicodeScalars)
        guard let colon = firstTopLevelDelimiter(0x3A, in: scalars) else { return nil }
        return (
            string(from: scalars[..<colon]),
            string(from: scalars[(colon + 1)...])
        )
    }

    private static func propertyName(from source: String) -> String? {
        let scalars = Array(source.unicodeScalars)
        var index = skipCSSSpaceAndComments(in: scalars, from: 0)
        let start = index

        while index < scalars.count {
            if isCSSWhitespace(scalars[index]) || startsComment(in: scalars, at: index) {
                break
            }
            if scalars[index].value == 0x5C { return nil }
            index += 1
        }
        guard index > start else { return nil }
        let name = asciiLowercased(string(from: scalars[start..<index]))
        index = skipCSSSpaceAndComments(in: scalars, from: index)
        guard index == scalars.count else { return nil }
        return name
    }

    private static func splitPriority(from source: String) -> (
        value: String,
        important: Bool,
        valid: Bool
    ) {
        let scalars = Array(source.unicodeScalars)
        guard let bang = firstTopLevelDelimiter(0x21, in: scalars) else {
            return (source, false, true)
        }

        let value = string(from: scalars[..<bang])
        let suffix = Array(scalars[(bang + 1)...])
        var index = skipCSSSpaceAndComments(in: suffix, from: 0)
        guard let identifierEnd = consumeCSSIdentifier(in: suffix, from: index) else {
            return (value, false, false)
        }
        index = skipCSSSpaceAndComments(in: suffix, from: identifierEnd)
        return (value, true, index == suffix.count)
    }

    /// css-tree skips leading whitespace/comments before capturing its raw
    /// declaration value, then jsdom applies JavaScript `trim()` in the property
    /// parser/descriptor. Trailing comments remain observable for var values.
    private static func rawCSSValue(from source: String) -> String {
        let scalars = Array(source.unicodeScalars)
        let start = skipCSSSpaceAndComments(in: scalars, from: 0)
        return javaScriptTrim(string(from: scalars[start...]))
    }

    private static func hasVarFunction(in source: String) -> Bool {
        let scalars = Array(source.unicodeScalars)
        guard scalars.count >= 4 else { return false }

        for index in 0...(scalars.count - 4) {
            guard scalars[index].value == 0x76,     // v
                  scalars[index + 1].value == 0x61, // a
                  scalars[index + 2].value == 0x72, // r
                  scalars[index + 3].value == 0x28  // (
            else {
                continue
            }
            if index == 0 { return true }
            let previous = scalars[index - 1]
            if previous.value == 0x2A || previous.value == 0x2F || previous.value == 0x28 ||
                javaScriptIsWhitespace(previous) {
                return true
            }
        }
        return false
    }

    // MARK: - CSS scanner helpers

    private static func firstTopLevelDelimiter(_ delimiter: UInt32, in scalars: [Unicode.Scalar]) -> Int? {
        var quote: UInt32?
        var blockStack: [UInt32] = []
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if let activeQuote = quote {
                if scalar.value == 0x5C {
                    index = indexAfterEscape(in: scalars, from: index)
                    continue
                }
                index += 1
                if scalar.value == activeQuote || isCSSNewline(scalar) {
                    quote = nil
                }
                continue
            }
            if startsComment(in: scalars, at: index) {
                index = indexAfterComment(in: scalars, from: index)
                continue
            }
            if scalar.value == 0x5C {
                index = indexAfterEscape(in: scalars, from: index)
                continue
            }
            if scalar.value == 0x22 || scalar.value == 0x27 {
                quote = scalar.value
                index += 1
                continue
            }
            if let closing = matchingClose(for: scalar.value) {
                blockStack.append(closing)
                index += 1
                continue
            }
            if blockStack.last == scalar.value {
                blockStack.removeLast()
                index += 1
                continue
            }
            if scalar.value == delimiter, blockStack.isEmpty {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func consumeCSSIdentifier(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        guard start < scalars.count else { return nil }
        var index = start

        if scalars[index].value == 0x2D { // -
            index += 1
            guard index < scalars.count else { return nil }
            if scalars[index].value == 0x2D {
                index += 1
            } else if isIdentifierStartScalar(scalars[index]) {
                index += 1
            } else if isValidEscape(in: scalars, at: index) {
                index = indexAfterEscape(in: scalars, from: index)
            } else {
                return nil
            }
        } else if isIdentifierStartScalar(scalars[index]) {
            index += 1
        } else if isValidEscape(in: scalars, at: index) {
            index = indexAfterEscape(in: scalars, from: index)
        } else {
            return nil
        }

        while index < scalars.count {
            if isIdentifierNameScalar(scalars[index]) {
                index += 1
            } else if isValidEscape(in: scalars, at: index) {
                index = indexAfterEscape(in: scalars, from: index)
            } else {
                break
            }
        }
        return index
    }

    private static func skipCSSSpaceAndComments(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        var index = start
        while index < scalars.count {
            if isCSSWhitespace(scalars[index]) {
                index += 1
            } else if startsComment(in: scalars, at: index) {
                index = indexAfterComment(in: scalars, from: index)
            } else {
                break
            }
        }
        return index
    }

    private static func startsComment(in scalars: [Unicode.Scalar], at index: Int) -> Bool {
        index + 1 < scalars.count &&
            scalars[index].value == 0x2F && scalars[index + 1].value == 0x2A
    }

    private static func indexAfterComment(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        var index = start + 2
        while index + 1 < scalars.count {
            if scalars[index].value == 0x2A, scalars[index + 1].value == 0x2F {
                return index + 2
            }
            index += 1
        }
        return scalars.count
    }

    private static func appendComment(
        in scalars: [Unicode.Scalar],
        at index: inout Int,
        to output: inout String.UnicodeScalarView
    ) {
        let end = indexAfterComment(in: scalars, from: index)
        output.append(contentsOf: scalars[index..<end])
        index = end
    }

    private static func appendEscape(
        in scalars: [Unicode.Scalar],
        at index: inout Int,
        to output: inout String.UnicodeScalarView
    ) {
        let end = indexAfterEscape(in: scalars, from: index)
        output.append(contentsOf: scalars[index..<end])
        index = end
    }

    private static func indexAfterEscape(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        var index = start + 1
        guard index < scalars.count else { return index }

        if isHexDigit(scalars[index]) {
            var count = 0
            while index < scalars.count, count < 6, isHexDigit(scalars[index]) {
                index += 1
                count += 1
            }
            if index < scalars.count, isCSSWhitespace(scalars[index]) {
                if scalars[index].value == 0x0D,
                   index + 1 < scalars.count,
                   scalars[index + 1].value == 0x0A {
                    return index + 2
                }
                return index + 1
            }
            return index
        }

        if scalars[index].value == 0x0D,
           index + 1 < scalars.count,
           scalars[index + 1].value == 0x0A {
            return index + 2
        }
        return index + 1
    }

    private static func isValidEscape(in scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard index < scalars.count, scalars[index].value == 0x5C, index + 1 < scalars.count else {
            return false
        }
        return !isCSSNewline(scalars[index + 1])
    }

    private static func matchingClose(for value: UInt32) -> UInt32? {
        switch value {
        case 0x28: return 0x29 // ( )
        case 0x5B: return 0x5D // [ ]
        case 0x7B: return 0x7D // { }
        default: return nil
        }
    }

    private static func isIdentifierStartScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x5F, 0x61...0x7A, 0x80...0x10FFFF:
            return true
        default:
            return false
        }
    }

    private static func isIdentifierNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierStartScalar(scalar) || (0x30...0x39).contains(scalar.value) || scalar.value == 0x2D
    }

    private static func isCSSWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009, 0x000A, 0x000C, 0x000D, 0x0020:
            return true
        default:
            return false
        }
    }

    private static func isCSSNewline(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x000A || scalar.value == 0x000C || scalar.value == 0x000D
    }

    private static func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66:
            return true
        default:
            return false
        }
    }

    private static func asciiLowercased(_ source: String) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(source.unicodeScalars.count)
        for scalar in source.unicodeScalars {
            let value = scalar.value
            result.append(Unicode.Scalar((0x41...0x5A).contains(value) ? value + 0x20 : value)!)
        }
        return String(result)
    }

    private static func string<C: Collection>(from scalars: C) -> String
    where C.Element == Unicode.Scalar {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(scalars.count)
        result.append(contentsOf: scalars)
        return String(result)
    }
}
