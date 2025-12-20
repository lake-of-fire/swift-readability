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
