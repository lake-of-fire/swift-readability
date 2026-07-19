import Foundation
import SwiftReadability
import SwiftReadabilityFixtureSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct ContractResult: Encodable {
    let name: String
    let parsed: Bool
    let readerable: Bool
    let title: String?
    let byline: String?
    let direction: String?
    let language: String?
    let excerpt: String?
    let siteName: String?
    let publishedTime: String?
    let content: String?
    let textContent: String?
    let length: Int?
}

private struct Arguments {
    var pagesPath = "Tests/SwiftReadabilityTests/Fixtures/test-pages"
    var filter: String?
}

private func parseArguments(_ values: [String]) throws -> Arguments {
    var arguments = Arguments()
    var index = 1
    while index < values.count {
        switch values[index] {
        case "--fixtures":
            guard index + 1 < values.count else { throw CorpusError("--fixtures requires a path") }
            arguments.pagesPath = values[index + 1]
            index += 2
        case "--filter":
            guard index + 1 < values.count else { throw CorpusError("--filter requires a value") }
            arguments.filter = values[index + 1]
            index += 2
        default:
            throw CorpusError("Unknown argument: \(values[index])")
        }
    }
    return arguments
}

private func run() throws {
    let arguments = try parseArguments(CommandLine.arguments)
    let pagesURL = URL(fileURLWithPath: arguments.pagesPath, isDirectory: true)
    let fixtures = try FixtureCorpus.load(pagesURL: pagesURL, nameFilter: arguments.filter)

    let results = try fixtures.map { fixture in
        let readerable = Readability.isProbablyReaderable(html: fixture.html)
        let result = try Readability(
            html: fixture.html,
            url: fixture.url
        ).parse()
        return ContractResult(
            name: fixture.name,
            parsed: result != nil,
            readerable: readerable,
            title: result?.title,
            byline: result?.byline,
            direction: result?.dir,
            language: result?.lang,
            excerpt: result?.excerpt,
            siteName: result?.siteName,
            publishedTime: result?.publishedTime,
            content: result?.content,
            textContent: result?.textContent,
            length: result?.length
        )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(results))
}

do {
    try run()
} catch {
    let message = "SwiftReadabilityContract: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
