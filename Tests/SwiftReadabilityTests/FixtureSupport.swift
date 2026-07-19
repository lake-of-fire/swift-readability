import Foundation
import SwiftReadability

struct FixtureSuiteManifest: Decodable, Sendable {
    enum ExtensionProfile: String, Decodable, Sendable {
        case publisherAdaptations

        var readabilityExtensions: ReadabilityExtensions {
            switch self {
            case .publisherAdaptations: .publisherAdaptations
            }
        }
    }

    struct KnownFailure: Decodable, Sendable {
        let name: String
        let runners: [String]
    }

    struct FixtureAssertions: Decodable, Sendable {
        let textExcludes: [String]?
        let contentExcludes: [String]?
        let contentIncludes: [String]?
    }

    let baseURL: URL?
    let extensionProfiles: [String: ExtensionProfile]?
    let assertions: [String: FixtureAssertions]?
    let knownFailures: [KnownFailure]

    static let fallbackBaseURL = URL(string: "http://fakehost/test/page.html")!

    func knownFailureNames(for runner: String) -> Set<String> {
        Set(knownFailures.compactMap { failure in
            guard failure.runners.contains(runner) || failure.runners.contains("*") else { return nil }
            return failure.name
        })
    }
}

struct Fixture: Sendable, CustomStringConvertible {
    enum ExpectedHTMLSource: String, Sendable {
        case legacyFixtureSnapshot
        case rawInputOracleOverlay
    }

    let name: String
    let url: URL
    let source: String
    let expectedHTML: String?
    let expectedHTMLSource: ExpectedHTMLSource?
    let expectedMetadata: ReadabilityTests.ExpectedMetadata?
    let assertions: FixtureSuiteManifest.FixtureAssertions?
    let extensionProfile: FixtureSuiteManifest.ExtensionProfile?

    var description: String { "Fixture(\(name))" }
}

struct FixtureSelection: Sendable {
    let names: Set<String>?
    let regexPattern: String?
    let includeKnownFailures: Bool

    static let all = FixtureSelection(names: nil, regexPattern: nil, includeKnownFailures: true)

    static func environment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> FixtureSelection {
        let names = environment["SWIFT_READABILITY_FIXTURES"]
            .map { value in
                Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            }
            .map { Set($0.filter { !$0.isEmpty }) }

        return FixtureSelection(
            names: names?.isEmpty == false ? names : nil,
            regexPattern: environment["SWIFT_READABILITY_FIXTURE_REGEX"],
            includeKnownFailures: environment["SWIFT_READABILITY_INCLUDE_KNOWN_FAILURES"] == "1"
        )
    }
}

struct FixtureLoadingError: Error, CustomStringConvertible, LocalizedError, Sendable {
    let message: String

    var description: String { message }
    var errorDescription: String? { message }
}

struct FixtureRepository: Sendable {
    let rootURL: URL

    static var packageResources: FixtureRepository {
        guard let rootURL = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            preconditionFailure("SwiftReadability test resources do not contain the Fixtures directory")
        }
        return FixtureRepository(rootURL: rootURL)
    }

    func load(selection: FixtureSelection) throws -> [Fixture] {
        let manifest = try loadManifest()
        let pagesURL = rootURL.appendingPathComponent("test-pages", isDirectory: true)
        let fileManager = FileManager.default

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: pagesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw FixtureLoadingError(message: "Unable to enumerate fixture directory at \(pagesURL.path): \(error)")
        }

        let fixtureDirectories = try entries.filter { entry in
            try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
        let availableNames = Set(fixtureDirectories.map(\.lastPathComponent))
        guard !availableNames.isEmpty else {
            throw FixtureLoadingError(message: "No fixture directories found at \(pagesURL.path)")
        }

        if let names = selection.names {
            let unknownNames = names.subtracting(availableNames).sorted()
            guard unknownNames.isEmpty else {
                throw FixtureLoadingError(message: "Unknown fixture selection: \(unknownNames.joined(separator: ", "))")
            }
        }

        let assertionNames = Set(manifest.assertions?.keys.map { $0 } ?? [])
        let unknownAssertionNames = assertionNames.subtracting(availableNames).sorted()
        guard unknownAssertionNames.isEmpty else {
            throw FixtureLoadingError(
                message: "Manifest assertions reference unknown fixtures: \(unknownAssertionNames.joined(separator: ", "))"
            )
        }

        let extensionProfileNames = Set(manifest.extensionProfiles?.keys.map { $0 } ?? [])
        let unknownExtensionProfileNames = extensionProfileNames.subtracting(availableNames).sorted()
        guard unknownExtensionProfileNames.isEmpty else {
            throw FixtureLoadingError(
                message: "Manifest extension profiles reference unknown fixtures: \(unknownExtensionProfileNames.joined(separator: ", "))"
            )
        }

        let unknownFailureNames = Set(manifest.knownFailures.map(\.name)).subtracting(availableNames).sorted()
        guard unknownFailureNames.isEmpty else {
            throw FixtureLoadingError(
                message: "Manifest known failures reference unknown fixtures: \(unknownFailureNames.joined(separator: ", "))"
            )
        }

        let fixtureRegex: NSRegularExpression?
        if let regexPattern = selection.regexPattern {
            do {
                fixtureRegex = try NSRegularExpression(pattern: regexPattern)
            } catch {
                throw FixtureLoadingError(message: "Invalid SWIFT_READABILITY_FIXTURE_REGEX \(regexPattern.debugDescription): \(error)")
            }
        } else {
            fixtureRegex = nil
        }

        let excludedFailures = selection.includeKnownFailures ? [] : manifest.knownFailureNames(for: "swift")
        let baseURL = manifest.baseURL ?? FixtureSuiteManifest.fallbackBaseURL
        var fixtures: [Fixture] = []

        for directory in fixtureDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = directory.lastPathComponent
            if let names = selection.names, !names.contains(name) { continue }
            if let fixtureRegex {
                let range = NSRange(location: 0, length: name.utf16.count)
                if fixtureRegex.firstMatch(in: name, range: range) == nil { continue }
            }
            if excludedFailures.contains(name) { continue }

            let sourceURL = directory.appendingPathComponent("source.html")
            let source = try readRequiredText(sourceURL, label: "source", fixtureName: name)
            let expectedHTMLURL = directory.appendingPathComponent("expected.html")
            let rawInputExpectedHTMLURL = directory.appendingPathComponent("expected-raw-input.html")
            let rawInputExpectedHTML = try readOptionalText(
                rawInputExpectedHTMLURL,
                label: "raw-input expected HTML",
                fixtureName: name
            )
            let legacyExpectedHTML = try readOptionalText(
                expectedHTMLURL,
                label: "expected HTML",
                fixtureName: name
            )
            if rawInputExpectedHTML != nil, legacyExpectedHTML == nil {
                throw FixtureLoadingError(
                    message: "Raw-input expected HTML for fixture \(name) requires a legacy expected.html"
                )
            }
            if rawInputExpectedHTML != nil, manifest.extensionProfiles?[name] != nil {
                throw FixtureLoadingError(
                    message: "Raw-input Mozilla expected HTML is invalid for extension fixture \(name)"
                )
            }
            let expectedHTML = rawInputExpectedHTML ?? legacyExpectedHTML
            let expectedHTMLSource: Fixture.ExpectedHTMLSource? = if rawInputExpectedHTML != nil {
                .rawInputOracleOverlay
            } else if legacyExpectedHTML != nil {
                .legacyFixtureSnapshot
            } else {
                nil
            }
            let expectedMetadata = try readExpectedMetadata(
                directory.appendingPathComponent("expected-metadata.json"),
                fixtureName: name
            )

            fixtures.append(
                Fixture(
                    name: name,
                    url: baseURL,
                    source: source,
                    expectedHTML: expectedHTML,
                    expectedHTMLSource: expectedHTMLSource,
                    expectedMetadata: expectedMetadata,
                    assertions: manifest.assertions?[name],
                    extensionProfile: manifest.extensionProfiles?[name]
                )
            )
        }

        guard !fixtures.isEmpty else {
            throw FixtureLoadingError(message: "Fixture selection matched zero runnable Swift fixtures")
        }
        return fixtures
    }

    func load(named name: String) throws -> Fixture {
        let selection = FixtureSelection(names: [name], regexPattern: nil, includeKnownFailures: true)
        guard let fixture = try load(selection: selection).first else {
            throw FixtureLoadingError(message: "Fixture \(name) was not loaded")
        }
        return fixture
    }

    private func loadManifest() throws -> FixtureSuiteManifest {
        let manifestURL = rootURL.appendingPathComponent("readability-suite.json")
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw FixtureLoadingError(message: "Unable to read fixture manifest at \(manifestURL.path): \(error)")
        }

        do {
            return try JSONDecoder().decode(FixtureSuiteManifest.self, from: data)
        } catch {
            throw FixtureLoadingError(message: "Malformed fixture manifest at \(manifestURL.path): \(error)")
        }
    }

    private func readRequiredText(_ url: URL, label: String, fixtureName: String) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FixtureLoadingError(message: "Unable to read \(label) for fixture \(fixtureName): \(error)")
        }
        // Foundation's String(contentsOf:encoding:) consumes a leading UTF-8
        // BOM, while Node's readFileSync(..., "utf8") preserves U+FEFF. Decode
        // without transport normalization and reject malformed UTF-8 by proving
        // a byte-for-byte round trip.
        let value = String(decoding: data, as: UTF8.self)
        guard Data(value.utf8) == data else {
            throw FixtureLoadingError(message: "Unable to decode \(label) for fixture \(fixtureName) as valid UTF-8")
        }
        return value
    }

    private func readOptionalText(_ url: URL, label: String, fixtureName: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try readRequiredText(url, label: label, fixtureName: fixtureName)
    }

    private func readExpectedMetadata(_ url: URL, fixtureName: String) throws -> ReadabilityTests.ExpectedMetadata? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FixtureLoadingError(message: "Unable to read expected metadata for fixture \(fixtureName): \(error)")
        }

        do {
            return try JSONDecoder().decode(ReadabilityTests.ExpectedMetadata.self, from: data)
        } catch {
            throw FixtureLoadingError(message: "Malformed expected metadata for fixture \(fixtureName): \(error)")
        }
    }
}

enum FixtureTestCase: Sendable, CustomStringConvertible {
    case fixture(Fixture)
    case loadingFailure(String)

    var description: String {
        switch self {
        case .fixture(let fixture): fixture.description
        case .loadingFailure(let message): "FixtureLoadingFailure(\(message))"
        }
    }

    func requireFixture() throws -> Fixture {
        switch self {
        case .fixture(let fixture):
            return fixture
        case .loadingFailure(let message):
            throw FixtureLoadingError(message: message)
        }
    }
}

func fixtureTestCases() -> [FixtureTestCase] {
    do {
        return try FixtureRepository.packageResources
            .load(selection: .environment())
            .map(FixtureTestCase.fixture)
    } catch {
        return [.loadingFailure(String(describing: error))]
    }
}
