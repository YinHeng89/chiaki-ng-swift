import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import Testing

@Test func coreStatisticsFillTheCoreFieldsAndLeaveTheRendererAtZero() {
    var core = chiaki_bridge.StreamStatistics()
    core.units = 1200
    core.bytes = 5_000_000_000
    core.lost = 3
    core.surfaces = 1200
    core.protocol_version.value = 12
    var picture = libchiaking.media.GrantedPicture()
    picture.height = 1080
    picture.max_fps = 60
    picture.bitrate_kbps = 15000
    core.granted.value = picture
    core.audio.state = .playing
    core.audio.underruns = 2
    let statistics = StreamStatisticsReader.statistics(of: core)
    #expect(statistics.received == 1200)
    #expect(statistics.bytes == 5_000_000_000)
    #expect(statistics.lost == 3)
    #expect(statistics.surfaces == 1200)
    #expect(statistics.takionVersionKnown)
    #expect(statistics.takionVersion == 12)
    #expect(statistics.grantedPresent)
    #expect(statistics.grantedHeight == 1080)
    #expect(statistics.grantedFPS == 60)
    #expect(statistics.grantedBitrate == 15000)
    #expect(statistics.audioState == 3)
    #expect(statistics.audioUnderruns == 2)
    #expect(!statistics.coreDiagnosticsAvailable)
    #expect(statistics.submitted == 0)
    #expect(statistics.frameGenerationGenerated == nil)
}

@Test func linkFactsMarkWhatTheCoreMeasured() {
    var link = chiaki_bridge.LinkFacts()
    link.video_units = 40
    var roundTrip = chiaki_bridge.RoundTripFacts()
    roundTrip.smoothed_us = 9500
    roundTrip.variation_us = 400
    link.round_trip.value = roundTrip
    var marks = chiaki_bridge.ServiceMarkFacts()
    marks.last_dscp.value = 46
    marks.last_ecn.value = 1
    link.service_marks.value = marks
    var core = chiaki_bridge.StreamStatistics()
    core.link.value = link
    let statistics = StreamStatisticsReader.statistics(of: core)
    #expect(statistics.coreDiagnosticsAvailable)
    #expect(statistics.coreVideoUnits == 40)
    #expect(statistics.rttPresent)
    #expect(statistics.rttSmoothedMicroseconds == 9500)
    #expect(statistics.rttVariationMicroseconds == 400)
    #expect(statistics.tosPresent)
    #expect(statistics.tosLastPresent)
    #expect(statistics.tosLastDSCP == 46)
    #expect(statistics.tosLastECN == 1)
    #expect(!statistics.extensionPresent)
    #expect(!statistics.videoMetricsPresent)
    #expect(statistics.server == nil)
}

@Test func emptyCoreStatisticsReadAsZero() {
    #expect(StreamStatisticsReader.statistics(of: chiaki_bridge.StreamStatistics()) == RenderStatistics())
}
