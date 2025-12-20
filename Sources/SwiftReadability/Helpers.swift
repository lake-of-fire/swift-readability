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
        (try? id()) ?? ""
    }
    func tagNameSafe() -> String {
        (try? tagName()) ?? ""
    }
}

extension Elements {
    var firstSafe: Element? { (try? first()) ?? nil }
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
