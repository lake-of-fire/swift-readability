import Foundation

/// One frozen HTML input shared by the native benchmark and differential oracle.
public struct ReadabilityFixture: Sendable {
    public let name: String
    public let html: String
    public let url: URL

    public init(name: String, html: String, url: URL) {
        self.name = name
        self.html = html
        self.url = url
    }
}

/// Fail-closed loading for Mozilla-format fixture directories.
public enum FixtureCorpus {
    private struct Manifest: Decodable {
        let baseURL: URL?
    }

    public static func load(
        pagesURL: URL,
        manifestURL: URL? = nil,
        nameFilter: String? = nil
    ) throws -> [ReadabilityFixture] {
        let resolvedManifestURL = manifestURL
            ?? pagesURL.deletingLastPathComponent().appendingPathComponent("readability-suite.json")
        let manifestData = try Data(contentsOf: resolvedManifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        let baseURL = manifest.baseURL ?? URL(string: "http://fakehost/test/page.html")!

        let entries = try FileManager.default.contentsOfDirectory(
            at: pagesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let directories = try entries.filter {
            try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
        guard !directories.isEmpty else {
            throw CorpusError("No fixture directories found at \(pagesURL.path)")
        }

        let fixtures = try directories
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter { directory in
                guard let nameFilter else { return true }
                return directory.lastPathComponent.contains(nameFilter)
            }
            .map { directory in
                let name = directory.lastPathComponent
                let sourceURL = directory.appendingPathComponent("source.html")
                let sourceData: Data
                do {
                    sourceData = try Data(contentsOf: sourceURL)
                } catch {
                    throw CorpusError("Unable to read source.html for fixture \(name): \(error)")
                }
                // `String(contentsOf:encoding:)` silently consumes a leading
                // UTF-8 BOM, while the JavaScript oracle's `readFileSync(...,
                // "utf8")` preserves it as U+FEFF. Decode without transport
                // normalization, then verify a byte-for-byte UTF-8 round trip
                // so malformed input still fails closed.
                let html = String(decoding: sourceData, as: UTF8.self)
                guard Data(html.utf8) == sourceData else {
                    throw CorpusError("Unable to decode source.html for fixture \(name) as valid UTF-8")
                }
                return ReadabilityFixture(
                    name: name,
                    html: html,
                    url: baseURL
                )
            }

        guard !fixtures.isEmpty else {
            throw CorpusError("Fixture filter matched zero inputs")
        }
        return fixtures
    }
}

public struct CorpusError: Error, LocalizedError, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}
