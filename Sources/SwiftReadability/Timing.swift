// Materially modified from the inherited Swift port.
// See NOTICE and THIRD_PARTY_NOTICES.md for provenance and license terms.

import Foundation

protocol TimingSink: AnyObject {
    func measure<T>(_ label: String, _ block: () throws -> T) rethrows -> T
}

/// Executes one algorithmic path whether instrumentation is enabled or not.
///
/// Keeping the measured and unmeasured paths identical prevents benchmark-only
/// behavior drift, particularly when a closure legitimately returns `nil`.
@inline(__always)
func measured<T>(
    _ label: String,
    by timing: TimingSink?,
    _ block: () throws -> T
) rethrows -> T {
    guard let timing else { return try block() }
    return try timing.measure(label, block)
}
