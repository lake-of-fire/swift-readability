import Foundation
import Testing

struct FixtureSupportTests {
    @Test func packageCorpusHasExpectedIntegrity() throws {
        let fixtures = try FixtureRepository.packageResources.load(selection: .all)

        #expect(fixtures.count == 136)
        #expect(fixtures.filter { $0.expectedHTML != nil }.count == 131)
        #expect(fixtures.filter { $0.expectedMetadata != nil }.count == 133)
        #expect(Set(fixtures.map(\.name)).count == fixtures.count)
    }

    @Test func exactSelectionRejectsUnknownFixtureNames() {
        let selection = FixtureSelection(
            names: ["does-not-exist"],
            regexPattern: nil,
            includeKnownFailures: true
        )

        let message = capturedError {
            try FixtureRepository.packageResources.load(selection: selection)
        }

        #expect(message?.contains("Unknown fixture selection: does-not-exist") == true)
    }

    @Test func invalidRegularExpressionIsAnInfrastructureFailure() {
        let selection = FixtureSelection(
            names: nil,
            regexPattern: "[",
            includeKnownFailures: true
        )

        let message = capturedError {
            try FixtureRepository.packageResources.load(selection: selection)
        }

        #expect(message?.contains("Invalid SWIFT_READABILITY_FIXTURE_REGEX") == true)
    }

    @Test func regularExpressionMatchingNoFixturesIsAnInfrastructureFailure() {
        let selection = FixtureSelection(
            names: nil,
            regexPattern: "^does-not-exist$",
            includeKnownFailures: true
        )

        let message = capturedError {
            try FixtureRepository.packageResources.load(selection: selection)
        }

        #expect(message == "Fixture selection matched zero runnable Swift fixtures")
    }

    @Test func malformedManifestIsRejected() throws {
        let repository = try temporaryRepository(manifest: "not json")

        let message = capturedError {
            try repository.load(selection: .all)
        }

        #expect(message?.contains("Malformed fixture manifest") == true)
    }

    @Test func missingFixtureSourceIsRejected() throws {
        let repository = try temporaryRepository()
        try createFixtureDirectory(named: "missing-source", in: repository.rootURL)

        let message = capturedError {
            try repository.load(selection: .all)
        }

        #expect(message?.contains("Unable to read source for fixture missing-source") == true)
    }

    @Test func malformedExpectedMetadataIsRejected() throws {
        let repository = try temporaryRepository()
        let directory = try createFixtureDirectory(named: "bad-metadata", in: repository.rootURL)
        try "<article><p>Readable text.</p></article>".write(
            to: directory.appendingPathComponent("source.html"),
            atomically: true,
            encoding: .utf8
        )
        try "{".write(
            to: directory.appendingPathComponent("expected-metadata.json"),
            atomically: true,
            encoding: .utf8
        )

        let message = capturedError {
            try repository.load(selection: .all)
        }

        #expect(message?.contains("Malformed expected metadata for fixture bad-metadata") == true)
    }

    @Test func fixtureEnvironmentSelectionTrimsAndDeduplicatesNames() {
        let selection = FixtureSelection.environment([
            "SWIFT_READABILITY_FIXTURES": " qq,nytimes-3,qq ",
            "SWIFT_READABILITY_FIXTURE_REGEX": "^(qq|nytimes-3)$",
            "SWIFT_READABILITY_INCLUDE_KNOWN_FAILURES": "1",
        ])

        #expect(selection.names == ["qq", "nytimes-3"])
        #expect(selection.regexPattern == "^(qq|nytimes-3)$")
        #expect(selection.includeKnownFailures)
    }

    private func temporaryRepository(
        manifest: String = #"{"baseURL":"https://example.com/article","knownFailures":[]}"#
    ) throws -> FixtureRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-readability-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("test-pages", isDirectory: true),
            withIntermediateDirectories: true
        )
        try manifest.write(
            to: root.appendingPathComponent("readability-suite.json"),
            atomically: true,
            encoding: .utf8
        )
        return FixtureRepository(rootURL: root)
    }

    @discardableResult
    private func createFixtureDirectory(named name: String, in root: URL) throws -> URL {
        let directory = root
            .appendingPathComponent("test-pages", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func capturedError<T>(_ operation: () throws -> T) -> String? {
        do {
            _ = try operation()
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
