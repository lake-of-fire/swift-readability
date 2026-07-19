/// Returns the number of UTF-16 code units in `string`, matching JavaScript
/// `String.prototype.length` and DOM string `.length` semantics.
///
/// Swift's `String.count` measures extended grapheme clusters instead. That is
/// appropriate for user-visible character counts, but it changes Mozilla
/// Readability's scoring and threshold decisions for supplementary scalars and
/// combining sequences. Use this helper only when porting a JavaScript string
/// length decision; collection counts and deliberately grapheme-based policies
/// should continue to use their native Swift representations.
@inline(__always)
func javaScriptStringLength(_ string: String) -> Int {
    string.utf16.count
}
