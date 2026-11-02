import ChiakiClients
import ChiakiModels
import Testing
@testable import ChiakiFeatures

@Suite struct StreamTelemetrySamplerTests {
    private func sample(_ statistics: RenderStatistics?, at uptime: Double) -> StreamStatisticsSample {
        StreamStatisticsSample(statistics: statistics, uptime: uptime)
    }

    @Test func ratesComeFromTheChangeBetweenReadings() {
        var sampler = StreamTelemetrySampler()
        var first = RenderStatistics()
        first.surfaces = 60
        first.bytes = 1_000_000
        let initial = sampler.update(sample(first, at: 0))
        #expect(initial.sourceFPS == 0)
        #expect(initial.statistics.surfaces == 60)
        var second = first
        second.surfaces = 120
        second.lost = 6
        second.bytes = 2_000_000
        let telemetry = sampler.update(sample(second, at: 1))
        #expect(telemetry.sourceFPS == 60)
        #expect(telemetry.bitrateMbps == 8)
        #expect(telemetry.interval.framesLost == 6)
        #expect(abs(telemetry.lossPercent - 6.0 / 66.0 * 100) < 0.0001)
    }

    @Test func readingsWithoutAPlayerOrFrameGenerationYieldNoSpike() {
        var sampler = StreamTelemetrySampler()
        _ = sampler.update(sample(nil, at: 0))
        var running = RenderStatistics()
        running.surfaces = 5000
        let started = sampler.update(sample(running, at: 1))
        #expect(started.sourceFPS == 0)
        running.frameGenerationGenerated = 9000
        let generating = sampler.update(sample(running, at: 2))
        #expect(generating.generatedFPS == 0)
        running.frameGenerationGenerated = 9060
        let steady = sampler.update(sample(running, at: 3))
        #expect(steady.generatedFPS == 60)
        let stopped = sampler.update(sample(nil, at: 4))
        #expect(stopped.sourceFPS == 0)
        #expect(stopped.statistics == RenderStatistics())
    }
}
