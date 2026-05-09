import Foundation

public enum ReadabilityJavaScriptResource {
    public static func source() throws -> String {
        let url = try resourceURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

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
        if let url = Bundle.module.url(
            forResource: "Readability",
            withExtension: "js",
            subdirectory: "tmp-readability"
        ) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
