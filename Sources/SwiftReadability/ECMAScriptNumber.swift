/// Mirrors `parseInt(value, 10)` for the attribute values used by Mozilla
/// Readability. The return type is `Double` because JavaScript numbers can
/// overflow to infinity, while `Int` would either reject or trap on the same
/// input.
func javaScriptParseIntBase10(_ text: String) -> Double? {
    let scalars = text.unicodeScalars
    var index = scalars.startIndex

    while index < scalars.endIndex, javaScriptIsWhitespace(scalars[index]) {
        scalars.formIndex(after: &index)
    }

    var sign = 1.0
    if index < scalars.endIndex {
        if scalars[index].value == 0x2B { // +
            scalars.formIndex(after: &index)
        } else if scalars[index].value == 0x2D { // -
            sign = -1
            scalars.formIndex(after: &index)
        }
    }

    var value = 0.0
    var consumedDigit = false
    while index < scalars.endIndex {
        let scalar = scalars[index].value
        guard (0x30...0x39).contains(scalar) else { break }
        consumedDigit = true
        value = value * 10 + Double(scalar - 0x30)
        scalars.formIndex(after: &index)
    }

    return consumedDigit ? sign * value : nil
}

/// Mirrors `parseInt(attribute, 10) || 1` in Readability's table sizing.
func javaScriptTableSpan(_ text: String) -> Double {
    guard let parsed = javaScriptParseIntBase10(text), parsed != 0 else { return 1 }
    return parsed
}
