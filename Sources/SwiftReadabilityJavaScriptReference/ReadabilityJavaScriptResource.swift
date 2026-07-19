import Foundation

/// Loads the pinned Mozilla JavaScript oracle shipped by the optional reference product.
public enum ReadabilityJavaScriptResource {
    /// Returns the pinned Readability.js source.
    public static func source() throws -> String {
        let url = try resourceURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Returns the pinned readerability-heuristic JavaScript source.
    public static func readerableSource() throws -> String {
        let url = try readerableResourceURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Returns the package resource URL for Readability.js.
    public static func resourceURL() throws -> URL {
        if let url = Bundle.module.url(
            forResource: "Readability",
            withExtension: "js"
        ) {
            return url
        }
        if let url = Bundle.module.url(
            forResource: "Readability",
            withExtension: "js",
            subdirectory: "Resources"
        ) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// Returns the package resource URL for the readerability JavaScript source.
    public static func readerableResourceURL() throws -> URL {
        if let url = Bundle.module.url(
            forResource: "Readability-readerable",
            withExtension: "js"
        ) {
            return url
        }
        if let url = Bundle.module.url(
            forResource: "Readability-readerable",
            withExtension: "js",
            subdirectory: "Resources"
        ) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
