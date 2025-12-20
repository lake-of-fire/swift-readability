import Foundation
import SwiftSoup

public struct ReadabilityOptions {
    public static let defaultMaxElemsToParse = 0
    public static let defaultNTopCandidates = 5
    public static let defaultCharThreshold = 500

    public typealias Serializer = (Element) -> String

    public var debug: Bool
    public var maxElemsToParse: Int
    public var nbTopCandidates: Int
    public var charThreshold: Int
    public var classesToPreserve: [String]
    public var keepClasses: Bool
    public var serializer: Serializer?
    public var useXMLSerializer: Bool
    public var disableJSONLD: Bool
    public var allowedVideoRegex: NSRegularExpression?
    public var linkDensityModifier: Double

    public init(debug: Bool = false,
                maxElemsToParse: Int = ReadabilityOptions.defaultMaxElemsToParse,
                nbTopCandidates: Int = ReadabilityOptions.defaultNTopCandidates,
                charThreshold: Int = ReadabilityOptions.defaultCharThreshold,
                classesToPreserve: [String] = [],
                keepClasses: Bool = false,
                serializer: Serializer? = nil,
                useXMLSerializer: Bool = false,
                disableJSONLD: Bool = false,
                allowedVideoRegex: NSRegularExpression? = nil,
                linkDensityModifier: Double = 0.0) {
        self.debug = debug
        self.maxElemsToParse = maxElemsToParse
        self.nbTopCandidates = nbTopCandidates
        self.charThreshold = charThreshold
        self.classesToPreserve = classesToPreserve
        self.keepClasses = keepClasses
        self.serializer = serializer
        self.useXMLSerializer = useXMLSerializer
        self.disableJSONLD = disableJSONLD
        self.allowedVideoRegex = allowedVideoRegex
        self.linkDensityModifier = linkDensityModifier
    }
}

struct ArticleGrabberOptions {
    var stripUnlikelyCandidates: Bool = true
    var weightClasses: Bool = true
    var cleanConditionally: Bool = true
}

final class ArticleMetadata {
    var title: String?
    var byline: String?
    var excerpt: String?
    var dir: String?
    var charset: String?
    var siteName: String?
    var publishedTime: String?
}

final class ReadabilityObject {
    var contentScore: Double = 0.0
}

public final class Article {
    public let uri: String
    public var title: String?
    public var articleContent: Element? {
        didSet { cachedTextContent = nil }
    }
    public var excerpt: String?
    public var byline: String?
    public var dir: String?
    public var charset: String?
    private var cachedTextContent: String?

    public init(uri: String) {
        self.uri = uri
    }

    public var content: String? { try? articleContent?.html() }
    public var contentWithUtf8Encoding: String? { getContent(withEncoding: "utf-8") }
    public var contentWithDocumentsCharsetOrUtf8: String? { getContent(withEncoding: charset ?? "utf-8") }
    public var textContent: String? {
        if let cachedTextContent { return cachedTextContent }
        let value = (try? articleContent?.text()) ?? articleContent?.ownText()
        cachedTextContent = value
        return value
    }
    public var length: Int { textContent?.count ?? -1 }

    private func getContent(withEncoding encoding: String) -> String? {
        guard let content else { return nil }
        return """
        <html>
          <head>
            <meta charset=\"" + encoding + "\"/>
          </head>
          <body>
            " + content + "
          </body>
        </html>
        """
    }
}
