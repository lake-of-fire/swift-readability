import Foundation
import SwiftReadability

struct BenchOptions {
    var fixturesPath: String
    var iterations: Int
    var warmup: Int
    var filter: String?
    var useXMLSerializer: Bool
}

struct Fixture {
    let name: String
    let html: String
    let url: URL
}

func parseArgs() -> BenchOptions {
    var fixturesPath = "Tests/SwiftReadabilityTests/Fixtures/test-pages"
    var iterations = 5
    var warmup = 1
    var filter: String?
    var useXMLSerializer = false

    var i = 1
    while i < CommandLine.arguments.count {
        let arg = CommandLine.arguments[i]
        switch arg {
        case "--fixtures":
            if i + 1 < CommandLine.arguments.count {
                fixturesPath = CommandLine.arguments[i + 1]
                i += 1
            }
        case "--iterations":
            if i + 1 < CommandLine.arguments.count, let value = Int(CommandLine.arguments[i + 1]) {
                iterations = max(1, value)
                i += 1
            }
        case "--warmup":
            if i + 1 < CommandLine.arguments.count, let value = Int(CommandLine.arguments[i + 1]) {
                warmup = max(0, value)
                i += 1
            }
        case "--filter":
            if i + 1 < CommandLine.arguments.count {
                filter = CommandLine.arguments[i + 1]
                i += 1
            }
        case "--xml":
            useXMLSerializer = true
        default:
            break
        }
        i += 1
    }

    return BenchOptions(
        fixturesPath: fixturesPath,
        iterations: iterations,
        warmup: warmup,
        filter: filter,
        useXMLSerializer: useXMLSerializer
    )
}

func loadFixtures(from path: String, filter: String?) -> [Fixture] {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: path)
    guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }

    var fixtures: [Fixture] = []
    fixtures.reserveCapacity(dirs.count)

    for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let name = dir.lastPathComponent
        if let filter, !name.contains(filter) { continue }
        let sourceURL = dir.appendingPathComponent("source.html")
        guard fm.fileExists(atPath: sourceURL.path) else { continue }
        let html = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

        var url = URL(string: "about:blank")!
        let metadataURL = dir.appendingPathComponent("metadata.json")
        if let data = try? Data(contentsOf: metadataURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let urlString = obj["url"] as? String,
           let parsed = URL(string: urlString) {
            url = parsed
        }

        fixtures.append(Fixture(name: name, html: html, url: url))
    }

    return fixtures
}

func formatMillis(_ nanos: UInt64) -> String {
    let ms = Double(nanos) / 1_000_000.0
    return String(format: "%.2fms", ms)
}

func main() {
    let options = parseArgs()
    let fixtures = loadFixtures(from: options.fixturesPath, filter: options.filter)
    if fixtures.isEmpty {
        print("No fixtures found at " + options.fixturesPath)
        return
    }

    print("Fixtures: " + String(fixtures.count))
    print("Iterations: " + String(options.iterations) + ", warmup: " + String(options.warmup))

    var totalNanos: UInt64 = 0
    var totalRuns = 0

    for fixture in fixtures {
        var optionsStruct = ReadabilityOptions()
        optionsStruct.useXMLSerializer = options.useXMLSerializer
        let reader = Readability(html: fixture.html, url: fixture.url, options: optionsStruct)

        for _ in 0..<options.warmup {
            _ = try? reader.parse()
        }

        var elapsed: UInt64 = 0
        for _ in 0..<options.iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            autoreleasepool {
                _ = try? reader.parse()
            }
            let end = DispatchTime.now().uptimeNanoseconds
            elapsed += (end - start)
        }

        let avg = elapsed / UInt64(options.iterations)
        totalNanos += elapsed
        totalRuns += options.iterations
        print(fixture.name + ": " + formatMillis(avg))
    }

    let overallAvg = totalRuns > 0 ? totalNanos / UInt64(totalRuns) : 0
    print("Overall avg: " + formatMillis(overallAvg))
}

main()
