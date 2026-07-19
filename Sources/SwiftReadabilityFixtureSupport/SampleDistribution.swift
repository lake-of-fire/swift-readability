import Foundation

/// Summary statistics for non-negative benchmark samples.
///
/// Percentiles use linear interpolation between adjacent ordered samples. Keeping
/// this calculation in fixture support makes benchmark output deterministic and
/// independently testable instead of embedding unverified math in an executable.
public struct SampleDistribution: Equatable, Sendable {
    public let count: Int
    public let minimum: Double
    public let mean: Double
    public let p50: Double
    public let p95: Double
    public let maximum: Double

    public init(samples: [Double]) throws {
        guard !samples.isEmpty else {
            throw CorpusError("Cannot summarize an empty benchmark sample set")
        }
        guard samples.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw CorpusError("Benchmark samples must be finite and non-negative")
        }

        let ordered = samples.sorted()
        count = ordered.count
        minimum = ordered[0]
        mean = ordered.reduce(0, +) / Double(ordered.count)
        p50 = Self.percentile(0.50, in: ordered)
        p95 = Self.percentile(0.95, in: ordered)
        maximum = ordered[ordered.count - 1]
    }

    private static func percentile(
        _ percentile: Double,
        in ordered: [Double]
    ) -> Double {
        guard ordered.count > 1 else { return ordered[0] }

        let rank = percentile * Double(ordered.count - 1)
        let lowerIndex = Int(rank.rounded(.down))
        let upperIndex = Int(rank.rounded(.up))
        guard lowerIndex != upperIndex else { return ordered[lowerIndex] }

        let fraction = rank - Double(lowerIndex)
        let delta = ordered[upperIndex] - ordered[lowerIndex]
        return ordered[lowerIndex] + (delta * fraction)
    }
}
