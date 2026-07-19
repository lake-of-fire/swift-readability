import Foundation

/// Scalar escapes suitable for embedding inside an ICU regular-expression
/// character class when the source JavaScript uses ECMAScript `\s`. Keeping the
/// list beside ``javaScriptIsWhitespace(_:)`` prevents subtle regex paths from
/// drifting back to Foundation's broader interpretation.
let javaScriptWhitespaceRegexCharacterClassContents =
    "\\u0009\\u000A\\u000B\\u000C\\u000D\\u0020\\u00A0\\u1680" +
    "\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF"

/// Produces a same-UTF-16-length input for ICU regexes that emulate a legacy
/// ECMAScript `/i` expression (one without the `u` or `v` flag).
///
/// ICU's case folding treats U+0131, U+017F, and U+212A as ASCII `i`, `s`, and
/// `k` in contexts where ECMAScript's legacy Canonicalize operation does not.
/// Replacing those three scalars with inert private-use scalars prevents false
/// ASCII literal matches while preserving every `NSRange` offset used to read
/// capture groups from the original string.
func javaScriptLegacyIgnoreCaseRegexInput(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: {
        $0.value == 0x0131 || $0.value == 0x017F || $0.value == 0x212A
    }) else {
        return text
    }

    var result = String.UnicodeScalarView()
    result.reserveCapacity(text.unicodeScalars.count)
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0x0131:
            result.append(Unicode.Scalar(0xE000)!)
        case 0x017F:
            result.append(Unicode.Scalar(0xE001)!)
        case 0x212A:
            result.append(Unicode.Scalar(0xE002)!)
        default:
            result.append(scalar)
        }
    }
    return String(result)
}

/// ECMAScript regexes without `u`/`v` define `\w` as ASCII letters, digits,
/// and underscore. This intentionally excludes all non-ASCII letters.
@inline(__always)
func javaScriptLegacyIsWordScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x30...0x39, 0x41...0x5A, 0x5F, 0x61...0x7A:
        return true
    default:
        return false
    }
}

/// Exact boolean equivalent of Mozilla's
/// `/(\b|_)(share|sharedaddy)(\b|_)/i.test(text)`.
func javaScriptLegacySharePatternMatches(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    let tokens = [Array("share".unicodeScalars), Array("sharedaddy".unicodeScalars)]

    func asciiFold(_ value: UInt32) -> UInt32 {
        (0x41...0x5A).contains(value) ? value + 0x20 : value
    }

    for start in scalars.indices {
        for token in tokens where start + token.count <= scalars.count {
            let matches = token.indices.allSatisfy { offset in
                asciiFold(scalars[start + offset].value) == token[offset].value
            }
            guard matches else { continue }

            let leftMatches: Bool
            if start == 0 {
                leftMatches = true
            } else {
                let previous = scalars[start - 1]
                leftMatches = previous.value == 0x5F || !javaScriptLegacyIsWordScalar(previous)
            }

            let end = start + token.count
            let rightMatches: Bool
            if end == scalars.count {
                rightMatches = true
            } else {
                let next = scalars[end]
                rightMatches = next.value == 0x5F || !javaScriptLegacyIsWordScalar(next)
            }

            if leftMatches && rightMatches { return true }
        }
    }
    return false
}

/// String operations whose behavior is defined by ECMAScript rather than by
/// Foundation's locale- and Unicode-oriented character sets.
///
/// Mozilla Readability uses JavaScript `String.prototype.trim` and regular
/// expression `\s` throughout its scoring pipeline. Those operations include
/// U+FEFF, but exclude characters such as U+0085 and U+200B that broader
/// platform character sets can classify differently.
@inline(__always)
func javaScriptIsWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0009, // CHARACTER TABULATION
         0x000A, // LINE FEED
         0x000B, // LINE TABULATION
         0x000C, // FORM FEED
         0x000D, // CARRIAGE RETURN
         0x0020, // SPACE
         0x00A0, // NO-BREAK SPACE
         0x1680, // OGHAM SPACE MARK
         0x2000...0x200A,
         0x2028, // LINE SEPARATOR
         0x2029, // PARAGRAPH SEPARATOR
         0x202F, // NARROW NO-BREAK SPACE
         0x205F, // MEDIUM MATHEMATICAL SPACE
         0x3000, // IDEOGRAPHIC SPACE
         0xFEFF: // ZERO WIDTH NO-BREAK SPACE / BOM
        return true
    default:
        return false
    }
}

func javaScriptIsWhitespaceOnly(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy(javaScriptIsWhitespace(_:))
}

func javaScriptHasTrailingNonWhitespace(_ text: String) -> Bool {
    guard let last = text.unicodeScalars.last else { return false }
    return !javaScriptIsWhitespace(last)
}

/// Mirrors `String.prototype.trim()` using ECMAScript's WhiteSpace and
/// LineTerminator productions.
func javaScriptTrim(_ text: String) -> String {
    let scalars = text.unicodeScalars
    var lower = scalars.startIndex
    var upper = scalars.endIndex

    while lower < upper, javaScriptIsWhitespace(scalars[lower]) {
        scalars.formIndex(after: &lower)
    }
    while lower < upper {
        let previous = scalars.index(before: upper)
        guard javaScriptIsWhitespace(scalars[previous]) else { break }
        upper = previous
    }

    if lower == scalars.startIndex, upper == scalars.endIndex { return text }
    return String(scalars[lower..<upper])
}

func javaScriptTrimEnd(_ text: String) -> String {
    let scalars = text.unicodeScalars
    var upper = scalars.endIndex
    while upper > scalars.startIndex {
        let previous = scalars.index(before: upper)
        guard javaScriptIsWhitespace(scalars[previous]) else { break }
        upper = previous
    }
    if upper == scalars.endIndex { return text }
    return String(scalars[..<upper])
}

/// Mirrors `/\s+/g` with the same ECMAScript whitespace set.
func javaScriptCollapseWhitespaceRuns(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    result.reserveCapacity(text.unicodeScalars.count)
    var insideWhitespace = false
    for scalar in text.unicodeScalars {
        if javaScriptIsWhitespace(scalar) {
            if !insideWhitespace {
                result.append(Unicode.Scalar(0x20)!)
                insideWhitespace = true
            }
        } else {
            result.append(scalar)
            insideWhitespace = false
        }
    }
    return String(result)
}

/// Mirrors Readability's `/\s{2,}/g` replacement. A single whitespace scalar
/// is preserved verbatim; each longer ECMAScript-whitespace run becomes one
/// ASCII space.
func javaScriptNormalizeWhitespaceRuns(_ text: String) -> String {
    var result = String.UnicodeScalarView()
    result.reserveCapacity(text.unicodeScalars.count)
    var pendingWhitespace: Unicode.Scalar?
    var pendingCount = 0

    func flushWhitespace() {
        guard let first = pendingWhitespace else { return }
        result.append(pendingCount == 1 ? first : Unicode.Scalar(0x20)!)
        pendingWhitespace = nil
        pendingCount = 0
    }

    for scalar in text.unicodeScalars {
        if javaScriptIsWhitespace(scalar) {
            if pendingWhitespace == nil { pendingWhitespace = scalar }
            pendingCount += 1
        } else {
            flushWhitespace()
            result.append(scalar)
        }
    }
    flushWhitespace()
    return String(result)
}

/// Length of `text.trim().replace(/\s{2,}/g, " ")` in JavaScript UTF-16
/// code units.
func javaScriptNormalizedTextLength(_ text: String) -> Int {
    javaScriptStringLength(
        javaScriptNormalizeWhitespaceRuns(javaScriptTrim(text))
    )
}
