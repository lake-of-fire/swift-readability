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

    @Test(arguments: fixtureTestCases())
    func parsesFixture(_ testCase: FixtureTestCase) throws {
        let fixture = try testCase.requireFixture()
        let readability = Readability(
            html: fixture.source,
            url: fixture.url,
            options: ReadabilityOptions(
                classesToPreserve: ["caption"],
                useXMLSerializer: true,
                extensions: fixture.extensionProfile?.readabilityExtensions ?? []
            )
        )
        guard let result = try readability.parse() else {
            #expect(Bool(false), "Expected readability to return a result for \(fixture.name)")
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
        if let assertions = fixture.assertions {
            for excludedText in assertions.textExcludes ?? [] {
                #expect(!result.textContent.contains(excludedText), "Fixture \(fixture.name) should not include text \(excludedText)")
            }
            for excludedContent in assertions.contentExcludes ?? [] {
                #expect(!result.content.contains(excludedContent), "Fixture \(fixture.name) should not include content \(excludedContent)")
            }
            for includedContent in assertions.contentIncludes ?? [] {
                #expect(result.content.contains(includedContent), "Fixture \(fixture.name) should include content \(includedContent)")
            }
        }

        if ProcessInfo.processInfo.environment["SWIFT_READABILITY_DUMP_RAW"] == "1" {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("swift-readability-fixture-dumps-raw", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let rawURL = tempDir.appendingPathComponent("\(fixture.name)-raw.html")
            try? result.contentHTML.write(to: rawURL, atomically: true, encoding: .utf8)
        }

        if let expectedHTML = fixture.expectedHTML {
            // DOMComparator parses both documents and normalizes text whitespace, so
            // formatting either string with Node's js-beautify is unnecessary. Keeping
            // this path native also makes `swift test` work without Node or npm.
            let actualHTML = result.contentHTML
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
    private static let comparisonLock = NSLock()

    static func compare(actualHTML: String, expectedHTML: String) -> DOMComparison {
        // The parameterized fixture cases intentionally exercise extraction in
        // parallel. SwiftSoup's parser/query caches can, however, make concurrent
        // test-only reparsing nondeterministic. Serialize only this comparison pass;
        // the native extraction work remains concurrent and therefore stress-tested.
        comparisonLock.lock()
        defer { comparisonLock.unlock() }

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
                let actualText = comparableText(aText)
                let expectedText = comparableText(eText)
                if actualText != expectedText {
                    return DOMComparison(
                        isEqual: false,
                        mismatchDescription: "Text mismatch. actual=\(actualText.debugDescription) expected=\(expectedText.debugDescription)"
                    )
                }
            } else if let aComment = a as? SwiftSoup.Comment,
                      let eComment = e as? SwiftSoup.Comment {
                if aComment.getData() != eComment.getData() {
                    return DOMComparison(
                        isEqual: false,
                        mismatchDescription: "Comment mismatch. actual=\(aComment.getData().debugDescription) expected=\(eComment.getData().debugDescription)"
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

    private static func filteredAttributes(for element: Element) -> [String] {
        var attrs: [String] = []
        if let attributes = element.getAttributes() {
            for attribute in attributes {
                let key = attribute.getKey()
                guard isValidXMLName(key) else { continue }
                let value = attribute.getValue()
                attrs.append("\(key)=\(normalizedAttributeValue(key: key, value: value))")
            }
        }
        return attrs
    }

    private static func normalizedAttributeValue(key: String, value: String) -> String {
        if value.isEmpty, ["allowfullscreen", "itemscope"].contains(key.lowercased()) {
            return key
        }
        return value
    }

    private static func isValidXMLName(_ name: String) -> Bool {
        // XML 1.0 (Fifth Edition) NameStartChar/NameChar. This mirrors the
        // JavaScript oracle's xml-name-validator instead of silently dropping
        // valid non-ASCII attribute names from golden comparisons.
        let scalars = name.unicodeScalars
        guard let first = scalars.first, isXMLNameStart(first.value) else { return false }
        return scalars.dropFirst().allSatisfy { isXMLNameCharacter($0.value) }
    }

    private static func isXMLNameStart(_ scalar: UInt32) -> Bool {
        scalar == 0x3A || scalar == 0x5F
            || (0x41...0x5A).contains(scalar)
            || (0x61...0x7A).contains(scalar)
            || (0xC0...0xD6).contains(scalar)
            || (0xD8...0xF6).contains(scalar)
            || (0xF8...0x2FF).contains(scalar)
            || (0x370...0x37D).contains(scalar)
            || (0x37F...0x1FFF).contains(scalar)
            || (0x200C...0x200D).contains(scalar)
            || (0x2070...0x218F).contains(scalar)
            || (0x2C00...0x2FEF).contains(scalar)
            || (0x3001...0xD7FF).contains(scalar)
            || (0xF900...0xFDCF).contains(scalar)
            || (0xFDF0...0xFFFD).contains(scalar)
            || (0x10000...0xEFFFF).contains(scalar)
    }

    private static func isXMLNameCharacter(_ scalar: UInt32) -> Bool {
        isXMLNameStart(scalar)
            || scalar == 0x2D
            || scalar == 0x2E
            || scalar == 0xB7
            || (0x30...0x39).contains(scalar)
            || (0x300...0x36F).contains(scalar)
            || (0x203F...0x2040).contains(scalar)
    }

    private static func nodeStr(_ node: Node?) -> String {
        guard let node else { return "(no node)" }
        if let text = node as? TextNode {
            return "#text(\(comparableText(text)))"
        }
        if let comment = node as? SwiftSoup.Comment {
            return "#comment(\(comment.getData()))"
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
        // Preserve leading/trailing collapsed spaces: spaces at inline element
        // boundaries affect rendered text and are significant to the JS oracle.
        javaScriptCollapseWhitespaceRuns(str)
    }

    private static func comparableText(_ node: TextNode) -> String {
        let transformed = htmlTransform(node.getWholeText())
        guard node.nextSibling() == nil else { return transformed }

        // The JavaScript oracle beautifies both strings before parsing them.
        // That normalizes indentation immediately before a closing tag, so the
        // native comparator ignores only that terminal formatting whitespace.
        return javaScriptTrimEnd(transformed)
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
                if javaScriptIsWhitespaceOnly(text.getWholeText()) {
                    current = inOrderTraverse(from: cur)
                    continue
                }
            }
            return cur
        }
        return nil
    }
}
