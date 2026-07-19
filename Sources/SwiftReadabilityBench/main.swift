import Foundation
@_spi(Bench) import SwiftReadability
import SwiftReadabilityFixtureSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private let usage = """
Usage: swift run SwiftReadabilityBench [options]

Options:
  --fixtures PATH     Mozilla-format test-pages directory
  --manifest PATH     Fixture manifest (defaults beside test-pages)
  --filter TEXT       Run fixtures whose names contain TEXT
  --iterations N      Measured runs per fixture (default: 5)
  --warmup N          Unmeasured runs per fixture (default: 1)
  --xml               Use the XML serializer compatibility mode
  --timings           Collect and summarize internal pipeline timing labels
  --summary-only      Suppress per-fixture distributions
  --help              Show this help
"""

private struct BenchmarkOptions {
    var pagesPath = "Tests/SwiftReadabilityTests/Fixtures/test-pages"
    var manifestPath: String?
    var iterations = 5
    var warmup = 1
    var filter: String?
    var useXMLSerializer = false
    var collectTimings = false
    var summaryOnly = false
    var showHelp = false
}

private struct ExtractionSample {
    let elapsedMilliseconds: Double
    let timingMilliseconds: [String: Double]
    let checksum: UInt64
}

/// A deterministic FNV-1a checksum keeps every observable parse result live.
private struct StableChecksum {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func append(_ byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 0x0100_0000_01b3
    }

    mutating func append(_ integer: UInt64) {
        var littleEndian = integer.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            for byte in bytes {
                append(byte)
            }
        }
    }

    mutating func append(_ string: String?) {
        guard let string else {
            append(UInt8(0))
            return
        }

        append(UInt8(1))
        let bytes = Array(string.utf8)
        append(UInt64(bytes.count))
        for byte in bytes {
            append(byte)
        }
    }
}

private func parseArguments(_ values: [String]) throws -> BenchmarkOptions {
    var options = BenchmarkOptions()
    var index = 1

    func value(after option: String, at index: Int) throws -> String {
        guard index + 1 < values.count else {
            throw CorpusError("\(option) requires a value")
        }
        return values[index + 1]
    }

    while index < values.count {
        let argument = values[index]
        switch argument {
        case "--fixtures":
            options.pagesPath = try value(after: argument, at: index)
            index += 2
        case "--manifest":
            options.manifestPath = try value(after: argument, at: index)
            index += 2
        case "--filter":
            let filter = try value(after: argument, at: index)
            guard !filter.isEmpty else {
                throw CorpusError("--filter requires a non-empty value")
            }
            options.filter = filter
            index += 2
        case "--iterations":
            let rawValue = try value(after: argument, at: index)
            guard let iterations = Int(rawValue), iterations > 0 else {
                throw CorpusError("--iterations must be a positive integer")
            }
            options.iterations = iterations
            index += 2
        case "--warmup":
            let rawValue = try value(after: argument, at: index)
            guard let warmup = Int(rawValue), warmup >= 0 else {
                throw CorpusError("--warmup must be a non-negative integer")
            }
            options.warmup = warmup
            index += 2
        case "--xml":
            options.useXMLSerializer = true
            index += 1
        case "--timings":
            options.collectTimings = true
            index += 1
        case "--summary-only":
            options.summaryOnly = true
            index += 1
        case "--help", "-h":
            options.showHelp = true
            index += 1
        default:
            throw CorpusError("Unknown argument: \(argument)")
        }
    }

    return options
}

private func checksum(of result: ReadabilityResult) -> UInt64 {
    var checksum = StableChecksum()
    checksum.append(result.title)
    checksum.append(result.byline)
    checksum.append(result.dir)
    checksum.append(result.lang)
    checksum.append(result.excerpt)
    checksum.append(result.siteName)
    checksum.append(result.publishedTime)
    checksum.append(result.content)
    checksum.append(result.textContent)
    checksum.append(UInt64(result.length))
    checksum.append(result.readerable ? UInt8(1) : UInt8(0))
    return checksum.value
}

private func extract(
    fixture: ReadabilityFixture,
    options: ReadabilityOptions,
    collectTimings: Bool
) throws -> ExtractionSample {
    // Start before construction so the benchmark covers a complete isolated extraction.
    let start = DispatchTime.now().uptimeNanoseconds
    let reader = Readability(html: fixture.html, url: fixture.url, options: options)
    let result: ReadabilityResult?
    let timingMilliseconds: [String: Double]

    if collectTimings {
        let parsed = try reader.parseWithTimings()
        result = parsed.0
        timingMilliseconds = parsed.1.milliseconds
    } else {
        result = try reader.parse()
        timingMilliseconds = [:]
    }
    let end = DispatchTime.now().uptimeNanoseconds

    guard let result else {
        throw CorpusError("Fixture \(fixture.name) produced no article")
    }
    guard !result.content.isEmpty else {
        throw CorpusError("Fixture \(fixture.name) produced empty article HTML")
    }
    guard result.length == result.textContent.utf16.count else {
        throw CorpusError(
            "Fixture \(fixture.name) reported length \(result.length), "
                + "but its text has \(result.textContent.utf16.count) UTF-16 code units"
        )
    }

    let resultChecksum = checksum(of: result)
    guard resultChecksum != 0 else {
        throw CorpusError("Fixture \(fixture.name) produced an invalid zero checksum")
    }

    return ExtractionSample(
        elapsedMilliseconds: Double(end - start) / 1_000_000,
        timingMilliseconds: timingMilliseconds,
        checksum: resultChecksum
    )
}

private func milliseconds(_ value: Double) -> String {
    String(format: "%.2f ms", value)
}

private func printDistribution(_ name: String, _ distribution: SampleDistribution) {
    print(
        "\(name): n=\(distribution.count) "
            + "p50=\(milliseconds(distribution.p50)) "
            + "p95=\(milliseconds(distribution.p95)) "
            + "mean=\(milliseconds(distribution.mean))"
    )
}

private func run() throws {
    let arguments = try parseArguments(CommandLine.arguments)
    if arguments.showHelp {
        print(usage)
        return
    }

    let pagesURL = URL(fileURLWithPath: arguments.pagesPath, isDirectory: true)
    let manifestURL = arguments.manifestPath.map { URL(fileURLWithPath: $0) }
    let fixtures = try FixtureCorpus.load(
        pagesURL: pagesURL,
        manifestURL: manifestURL,
        nameFilter: arguments.filter
    )

    let extractionOptions = ReadabilityOptions(useXMLSerializer: arguments.useXMLSerializer)
    let measuredRunCount = fixtures.count * arguments.iterations

    print("SwiftReadability benchmark")
    print("Corpus: \(pagesURL.path)")
    print("Fixtures: \(fixtures.count)")
    print(
        "Runs: \(measuredRunCount) measured, "
            + "\(fixtures.count * arguments.warmup) warmup"
    )
    print("Serializer: \(arguments.useXMLSerializer ? "XML" : "HTML")")
    print("Internal timings: \(arguments.collectTimings ? "enabled" : "disabled")")

    var allElapsedMilliseconds: [Double] = []
    allElapsedMilliseconds.reserveCapacity(measuredRunCount)
    var internalTimings: [String: [Double]] = [:]
    var measuredInputBytes: UInt64 = 0
    var aggregateChecksum = StableChecksum()

    for fixture in fixtures {
        var expectedChecksum: UInt64?

        for _ in 0..<arguments.warmup {
            let sample = try extract(
                fixture: fixture,
                options: extractionOptions,
                collectTimings: arguments.collectTimings
            )
            if let expectedChecksum, sample.checksum != expectedChecksum {
                throw CorpusError("Fixture \(fixture.name) changed output during warmup")
            }
            expectedChecksum = sample.checksum
        }

        var fixtureElapsedMilliseconds: [Double] = []
        fixtureElapsedMilliseconds.reserveCapacity(arguments.iterations)

        for _ in 0..<arguments.iterations {
            let sample = try extract(
                fixture: fixture,
                options: extractionOptions,
                collectTimings: arguments.collectTimings
            )
            if let expectedChecksum, sample.checksum != expectedChecksum {
                throw CorpusError("Fixture \(fixture.name) produced nondeterministic output")
            }
            expectedChecksum = sample.checksum

            fixtureElapsedMilliseconds.append(sample.elapsedMilliseconds)
            allElapsedMilliseconds.append(sample.elapsedMilliseconds)
            measuredInputBytes += UInt64(fixture.html.utf8.count)
            aggregateChecksum.append(sample.checksum)

            for (label, value) in sample.timingMilliseconds {
                guard value.isFinite, value >= 0 else {
                    throw CorpusError(
                        "Fixture \(fixture.name) reported an invalid \(label) timing"
                    )
                }
                internalTimings[label, default: []].append(value)
            }
        }

        if !arguments.summaryOnly {
            let distribution = try SampleDistribution(samples: fixtureElapsedMilliseconds)
            printDistribution(fixture.name, distribution)
        }
    }

    let overall = try SampleDistribution(samples: allElapsedMilliseconds)
    let measuredSeconds = allElapsedMilliseconds.reduce(0, +) / 1_000
    guard measuredSeconds > 0 else {
        throw CorpusError("Measured duration was zero")
    }

    print("\nAggregate")
    printDistribution("Article latency", overall)
    print(
        String(
            format: "Throughput: %.2f articles/s",
            Double(measuredRunCount) / measuredSeconds
        )
    )
    print(
        String(
            format: "Input throughput: %.2f MiB/s",
            (Double(measuredInputBytes) / 1_048_576) / measuredSeconds
        )
    )
    print(String(format: "Result checksum: 0x%016llx", aggregateChecksum.value))

    if arguments.collectTimings {
        guard !internalTimings.isEmpty else {
            throw CorpusError(
                "Internal timings were requested but no timing labels were reported"
            )
        }
        print("\nInternal pipeline timing labels")
        for label in internalTimings.keys.sorted() {
            guard let samples = internalTimings[label] else { continue }
            printDistribution("  \(label)", try SampleDistribution(samples: samples))
        }
    }
}

do {
    try run()
} catch {
    let message = "SwiftReadabilityBench: \(error)\n\n\(usage)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
