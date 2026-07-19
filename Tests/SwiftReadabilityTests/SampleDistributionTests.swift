import Testing
import SwiftReadabilityFixtureSupport

struct SampleDistributionTests {
    @Test func summarizesOrderedAndUnorderedSamples() throws {
        let distribution = try SampleDistribution(samples: [40, 10, 30, 20])

        #expect(distribution.count == 4)
        #expect(distribution.minimum == 10)
        #expect(distribution.mean == 25)
        #expect(distribution.p50 == 25)
        #expect(distribution.p95 == 38.5)
        #expect(distribution.maximum == 40)
    }

    @Test func oneSampleSuppliesEveryPercentile() throws {
        let distribution = try SampleDistribution(samples: [12.5])

        #expect(distribution.minimum == 12.5)
        #expect(distribution.mean == 12.5)
        #expect(distribution.p50 == 12.5)
        #expect(distribution.p95 == 12.5)
        #expect(distribution.maximum == 12.5)
    }

    @Test(arguments: [
        [Double](),
        [-1],
        [.infinity],
        [.nan],
    ])
    func rejectsInvalidSamples(_ samples: [Double]) {
        #expect(throws: CorpusError.self) {
            try SampleDistribution(samples: samples)
        }
    }
}
