import Foundation
import SwiftSoup
import Testing
@testable import SwiftReadability

struct ReadabilityTests {
    struct ExpectedMetadata: Decodable {
        let title: String?
        let byline: String?
        let dir: String?
        let lang: String?
        let excerpt: String?
        let siteName: String?
        let publishedTime: String?
        let readerable: Bool?
    }

    @Test(arguments: loadFixtures())
    func parsesFixture(_ fixture: Fixture) throws {
        let readability = Readability(
            html: fixture.source,
            url: fixture.url,
            options: ReadabilityOptions(classesToPreserve: ["caption"], useXMLSerializer: true)
        )
        guard let result = try readability.parse() else {
            #expect(false, "Expected readability to return a result for \(fixture.name)")
            return
        }

        if let expectedMetadata = fixture.expectedMetadata {
            #expect(result.title == expectedMetadata.title)
            #expect(result.byline == expectedMetadata.byline)
            #expect(result.dir == expectedMetadata.dir)
            #expect(result.lang == expectedMetadata.lang)
            #expect(result.excerpt == expectedMetadata.excerpt)
            #expect(result.siteName == expectedMetadata.siteName)
            #expect(result.publishedTime == expectedMetadata.publishedTime)
            if let readerable = expectedMetadata.readerable {
                #expect(result.readerable == readerable)
            }
        }

        if let expectedHTML = fixture.expectedHTML {
            // Mozilla's test suite runs js-beautify over both actual and expected HTML
            // before parsing and comparing the DOMs. Do the same to avoid false negatives
            // from formatting-only whitespace differences.
            let actualHTML = try MozillaPrettyPrinter.prettyPrint(result.contentHTML)
            let comparison = DOMComparator.compare(
                actualHTML: actualHTML,
                expectedHTML: expectedHTML
            )
            if !comparison.isEqual,
               ProcessInfo.processInfo.environment["SWIFT_READABILITY_DUMP_ACTUAL"] == "1" {
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                    .appendingPathComponent("swift-readability-fixture-dumps", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let actualURL = tempDir.appendingPathComponent("\(fixture.name)-actual.html")
                let expectedURL = tempDir.appendingPathComponent("\(fixture.name)-expected.html")
                try? actualHTML.write(to: actualURL, atomically: true, encoding: .utf8)
                try? expectedHTML.write(to: expectedURL, atomically: true, encoding: .utf8)
            }
            #expect(comparison.isEqual, "\(comparison)")
        }
    }
}

// MARK: - Fixture loading

struct Fixture: Sendable, CustomStringConvertible {
    let name: String
    let url: URL
    let source: String
    let expectedHTML: String?
    let expectedMetadata: ReadabilityTests.ExpectedMetadata?

    var description: String { "Fixture(\(name))" }
}

func loadFixtures() -> [Fixture] {
    let environment = ProcessInfo.processInfo.environment
    let selectedFixtures: Set<String>? = environment["SWIFT_READABILITY_FIXTURES"]
        .map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        .map { Set($0.filter { !$0.isEmpty }) }
    let fixtureRegex: NSRegularExpression? = environment["SWIFT_READABILITY_FIXTURE_REGEX"].flatMap {
        try? NSRegularExpression(pattern: $0, options: [])
    }

    // Resolve fixtures relative to this source file to avoid SwiftPM resource name collisions.
    let thisFile = URL(fileURLWithPath: #filePath)
    let baseURL = thisFile
        .deletingLastPathComponent() // Tests/SwiftReadabilityTests
        .appendingPathComponent("Fixtures/test-pages")

    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: baseURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    let basePageURL = URL(string: "http://fakehost/test/page.html")!
    var fixtures: [Fixture] = []
    for case let folderURL as URL in enumerator {
        let values = try? folderURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { continue }

        let sourceURL = folderURL.appendingPathComponent("source.html")
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else { continue }

        let expectedHTMLURL = folderURL.appendingPathComponent("expected.html")
        let expectedHTML = try? String(contentsOf: expectedHTMLURL, encoding: .utf8)

        let expectedMetadataURL = folderURL.appendingPathComponent("expected-metadata.json")
        let expectedMetadata: ReadabilityTests.ExpectedMetadata?
        if let data = try? Data(contentsOf: expectedMetadataURL) {
            expectedMetadata = try? JSONDecoder().decode(ReadabilityTests.ExpectedMetadata.self, from: data)
        } else {
            expectedMetadata = nil
        }

        fixtures.append(Fixture(
            name: folderURL.lastPathComponent,
            url: basePageURL,
            source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedHTML: expectedHTML?.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedMetadata: expectedMetadata
        ))
    }

    fixtures.sort { $0.name < $1.name }
    if let selectedFixtures, !selectedFixtures.isEmpty {
        fixtures = fixtures.filter { selectedFixtures.contains($0.name) }
    }
    if let fixtureRegex {
        fixtures = fixtures.filter {
            let range = NSRange(location: 0, length: $0.name.utf16.count)
            return fixtureRegex.firstMatch(in: $0.name, options: [], range: range) != nil
        }
    }
    return fixtures
}

// MARK: - Debugging helpers

struct DOMComparison: Sendable, CustomStringConvertible {
    let isEqual: Bool
    let mismatchDescription: String?

    var description: String {
        if isEqual { return "DOMComparison(equal)" }
        return mismatchDescription ?? "DOMComparison(not equal)"
    }
}

enum DOMComparator {
    static func compare(actualHTML: String, expectedHTML: String) -> DOMComparison {
        guard let actualDoc = try? SwiftSoup.parse(actualHTML),
              let expectedDoc = try? SwiftSoup.parse(expectedHTML) else {
            return DOMComparison(isEqual: false, mismatchDescription: "Failed to parse HTML into DOM")
        }

        func startNode(for doc: Document) -> Node? {
            // Match jsdom: start at documentElement (<html>) if present.
            if let html = doc.children().first() { return html }
            return doc.getChildNodes().first
        }

        var actualNode = startNode(for: actualDoc)
        var expectedNode = startNode(for: expectedDoc)

        while actualNode != nil || expectedNode != nil {
            guard let a = actualNode, let e = expectedNode else {
                let aDesc = nodeStr(actualNode)
                let eDesc = nodeStr(expectedNode)
                return DOMComparison(isEqual: false, mismatchDescription: "Node missing. actual=\(aDesc) expected=\(eDesc)")
            }

            let aDesc = nodeStr(a)
            let eDesc = nodeStr(e)
            if aDesc != eDesc {
                return DOMComparison(isEqual: false, mismatchDescription: "Node mismatch. actual=\(aDesc) expected=\(eDesc)")
            }

            if let aText = a as? TextNode, let eText = e as? TextNode {
                let actualText = htmlTransform(aText.getWholeText())
                let expectedText = htmlTransform(eText.getWholeText())
                if actualText != expectedText {
                    return DOMComparison(
                        isEqual: false,
                        mismatchDescription: "Text mismatch. actual=\(actualText.debugDescription) expected=\(expectedText.debugDescription)"
                    )
                }
            } else if let aEl = a as? Element, let eEl = e as? Element {
                let actualAttrs = filteredAttributes(for: aEl)
                let expectedAttrs = filteredAttributes(for: eEl)
                if actualAttrs != expectedAttrs {
                    return DOMComparison(
                        isEqual: false,
                        mismatchDescription: "Attributes mismatch for \(aDesc). actual=\(actualAttrs) expected=\(expectedAttrs)"
                    )
                }
            }

            actualNode = inOrderIgnoreEmptyTextNodes(from: a)
            expectedNode = inOrderIgnoreEmptyTextNodes(from: e)
        }

        return DOMComparison(isEqual: true, mismatchDescription: nil)
    }

    private static func filteredAttributes(for element: Element) -> [String: String] {
        var attrs: [String: String] = [:]
        if let attributes = element.getAttributes() {
            for attribute in attributes {
                let key = attribute.getKey()
                guard isValidXMLName(key) else { continue }
                attrs[key] = attribute.getValue()
            }
        }
        return attrs
    }

    private static func isValidXMLName(_ name: String) -> Bool {
        // Approximation sufficient for Mozilla test fixtures.
        // Allows optional namespace prefix (e.g. "xml:lang").
        let pattern = #"^[A-Za-z_][A-Za-z0-9_.-]*(?::[A-Za-z_][A-Za-z0-9_.-]*)?$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private static func nodeStr(_ node: Node?) -> String {
        guard let node else { return "(no node)" }
        if let text = node as? TextNode {
            return "#text(\(htmlTransform(text.getWholeText())))"
        }
        if let element = node as? Element {
            var result = element.tagName().lowercased()
            let id = element.idSafe()
            if !id.isEmpty { result += "#\(id)" }
            let className = element.attrOrEmpty("class")
            if !className.isEmpty { result += ".(\(className))" }
            return result
        }
        return "some other node type"
    }

    private static func htmlTransform(_ str: String) -> String {
        str.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func inOrderTraverse(from node: Node) -> Node? {
        if let element = node as? Element, let firstChild = element.getChildNodes().first {
            return firstChild
        }
        var current: Node? = node
        while let cur = current, cur.nextSibling() == nil {
            current = cur.parent()
        }
        return current?.nextSibling()
    }

    private static func inOrderIgnoreEmptyTextNodes(from node: Node) -> Node? {
        var current = inOrderTraverse(from: node)
        while let cur = current {
            if let text = cur as? TextNode {
                if text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    current = inOrderTraverse(from: cur)
                    continue
                }
            }
            return cur
        }
        return nil
    }
}

// MARK: - Mozilla fixture formatting

enum MozillaPrettyPrinter {
    static func prettyPrint(_ html: String) throws -> String {
        // Match tmp-readability/test/utils.js prettyPrint() options exactly.
        let script = #"""
const fs = require("fs");
const prettyPrint = require("js-beautify").html;
const input = fs.readFileSync(0, { encoding: "utf-8" });
const output = prettyPrint(input, {
  indent_size: 4,
  indent_char: " ",
  indent_level: 0,
  indent_with_tabs: false,
  preserve_newlines: false,
  break_chained_methods: false,
  eval_code: false,
  unescape_strings: false,
  wrap_line_length: 0,
  wrap_attributes: "auto",
  wrap_attributes_indent_size: 4,
});
process.stdout.write(output);
"""#

        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // Tests/SwiftReadabilityTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let nodeCwd = repoRoot.appendingPathComponent("tmp-readability", isDirectory: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "-e", script]
        process.currentDirectoryURL = nodeCwd

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("swift-readability-js-beautify", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let stdoutURL = tempDir.appendingPathComponent("\(UUID().uuidString)-stdout.txt")
        let stderrURL = tempDir.appendingPathComponent("\(UUID().uuidString)-stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()

        if let data = html.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        try? FileManager.default.removeItem(at: stdoutURL)
        try? FileManager.default.removeItem(at: stderrURL)

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "MozillaPrettyPrinter",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "js-beautify failed (\(process.terminationStatus)): \(stderrText)"]
            )
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
