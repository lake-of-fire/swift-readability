import Foundation
import SwiftReadabilityFixtureSupport
import Testing

struct FixtureSupportTests {
    @Test func packageCorpusHasExpectedIntegrity() throws {
        let fixtures = try FixtureRepository.packageResources.load(selection: .all)

        #expect(fixtures.count == 136)
        #expect(fixtures.filter { $0.expectedHTML != nil }.count == 131)
        #expect(fixtures.filter { $0.expectedMetadata != nil }.count == 133)
        #expect(fixtures.filter { $0.expectedHTMLSource == .rawInputOracleOverlay }.count == 33)
        #expect(fixtures.filter { $0.expectedHTMLSource == .legacyFixtureSnapshot }.count == 98)
        #expect(
            fixtures
                .filter { $0.expectedHTMLSource == .rawInputOracleOverlay }
                .allSatisfy { $0.extensionProfile == nil }
        )
        #expect(Set(fixtures.map(\.name)).count == fixtures.count)
    }

    @Test func rawInputOverlayIsPreferredWithoutChangingFixtureBytes() throws {
        let repository = try temporaryRepository()
        let directory = try createFixtureDirectory(named: "raw-overlay", in: repository.rootURL)
        let source = "\u{FEFF}<article>Exact source</article>\r\n\u{200B}"
        let rawExpected = "<div><!-- retained --><p>Raw input</p></div>\n"
        try Data(source.utf8).write(to: directory.appendingPathComponent("source.html"))
        try "<div><p>Legacy</p></div>\n".write(
            to: directory.appendingPathComponent("expected.html"),
            atomically: true,
            encoding: .utf8
        )
        try Data(rawExpected.utf8).write(
            to: directory.appendingPathComponent("expected-raw-input.html")
        )

        let fixture = try repository.load(selection: .all).first

        #expect(Data(fixture?.source.utf8 ?? "".utf8) == Data(source.utf8))
        #expect(Data(fixture?.expectedHTML?.utf8 ?? "".utf8) == Data(rawExpected.utf8))
        #expect(fixture?.expectedHTMLSource == .rawInputOracleOverlay)
    }

    @Test func rawInputOverlayRequiresLegacySnapshot() throws {
        let repository = try temporaryRepository()
        let directory = try createFixtureDirectory(named: "orphan-overlay", in: repository.rootURL)
        try "<article>Source</article>".write(
            to: directory.appendingPathComponent("source.html"),
            atomically: true,
            encoding: .utf8
        )
        try "<div><!-- retained --><p>Raw input</p></div>".write(
            to: directory.appendingPathComponent("expected-raw-input.html"),
            atomically: true,
            encoding: .utf8
        )

        let message = capturedError {
            try repository.load(selection: .all)
        }

        #expect(message == "Raw-input expected HTML for fixture orphan-overlay requires a legacy expected.html")
    }

    @Test func rawInputOverlayCannotDescribeAnExtensionProfile() throws {
        let repository = try temporaryRepository(
            manifest: #"{"baseURL":"https://example.com/article","extensionProfiles":{"extension-overlay":"publisherAdaptations"},"knownFailures":[]}"#
        )
        let directory = try createFixtureDirectory(named: "extension-overlay", in: repository.rootURL)
        for (name, value) in [
            ("source.html", "<article>Source</article>"),
            ("expected.html", "<div><p>Legacy</p></div>"),
            ("expected-raw-input.html", "<div><!-- retained --><p>Raw input</p></div>"),
        ] {
            try value.write(
                to: directory.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        let message = capturedError {
            try repository.load(selection: .all)
        }

        #expect(message == "Raw-input Mozilla expected HTML is invalid for extension fixture extension-overlay")
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

    // The benchmark/contract fixture loader and the JavaScript differential
    // oracle must parse identical source bytes. In particular, neither side
    // may trim source text or treat an initial U+FEFF as a transport BOM.
    @Test func contractFixtureCorpusPreservesSourceUTF8Bytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "swift-readability-contract-fixture-\(UUID().uuidString)",
                isDirectory: true
            )
        let pages = root.appendingPathComponent("test-pages", isDirectory: true)
        let fixtureDirectory = pages.appendingPathComponent("byte-preservation", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = #"{"baseURL":"https://example.com/article"}"#
        try Data(manifest.utf8).write(to: root.appendingPathComponent("readability-suite.json"))

        let source =
            "\u{FEFF}\u{0085}\u{200B}<html><body><article>Exact source</article></body></html>\r\n\u{200B}\u{0085}\u{FEFF}"
        let sourceBytes = Data(source.utf8)
        try sourceBytes.write(to: fixtureDirectory.appendingPathComponent("source.html"))

        let fixtures = try FixtureCorpus.load(pagesURL: pages)

        #expect(fixtures.count == 1)
        #expect(Data(fixtures[0].html.utf8) == sourceBytes)
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
