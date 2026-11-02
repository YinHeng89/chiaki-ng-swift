import ChiakiClients
import ChiakiModels
import ChiakiTestSupport
import Foundation
import SwiftUI
import Testing
@testable import ChiakiFeatures

@Test func diagnosticsSeparateUnrequestedHDRFromConsoleSDR() {
    func report(_ raw: [String: NSNumber]) -> StreamDiagnosticsReport {
        StreamDiagnosticsReport(telemetry: StreamTelemetry(statistics: RenderStatistics(fixture: raw)))
    }
    let unrequested = report(["requestedHEVC": true])
    #expect(unrequested.hdrLongLabel == "SDR transfer detected, HDR not requested")
    #expect(unrequested.requestedCodec == "HEVC")
    let requested = report(["requestedHEVC": true, "requestedHDR": true])
    #expect(requested.hdrLongLabel == "SDR transfer detected; check console HDR")
    #expect(requested.requestedCodec == "HEVC HDR")
    let received = report(["requestedHEVC": true, "requestedHDR": true, "pq": true, "layerHDR": true,
                           "displayMaximumEDR": 4])
    #expect(received.hdrLongLabel == "PQ input with EDR active")
    var mapped: [String: NSNumber] = [
        "pq": true,
        "layerHDR": true,
        "displayMaximumEDR": 8,
        "toneMapSource": 1,
        "contentPeakNits": 1000
    ]
    #expect(report(mapped)
        .hdrLongLabel == "PQ input with EDR active, the stream's 1000 nit peak fits the screen")
    mapped["displayMaximumEDR"] = 3.2
    mapped["toneMapSource"] = 2
    #expect(report(mapped).hdrLongLabel
        == "PQ input with EDR active, compressing highlights above the screen for a default 1000 nit peak")
}

func diagnosticsReport(
    _ raw: [String: NSNumber],
    sourceFPS: Double = 0,
    presentedFPS: Double = 0,
    generatedFPS: Double = 0,
    bitrateMbps: Double = 0,
    lossPercent: Double = 0,
    history: StreamDiagnosticsHistory = .init(),
    datacenter: CloudDatacenterSelection? = nil
) -> StreamDiagnosticsReport {
    StreamDiagnosticsReport(
        telemetry: StreamTelemetry(
            statistics: RenderStatistics(fixture: raw),
            sourceFPS: sourceFPS,
            presentedFPS: presentedFPS,
            generatedFPS: generatedFPS,
            bitrateMbps: bitrateMbps,
            lossPercent: lossPercent
        ),
        history: history,
        datacenter: datacenter
    )
}

func diagnosticsSample() -> [String: NSNumber] {
    [
        "route": 4,
        "takionVersionKnown": true, "takionVersion": 23,
        "requestedHEVC": true, "requestedHeight": 1080, "requestedFPS": 60, "requestedBitrate": 35000,
        "presentationFrameRate": 120, "tenBit": true, "spatialUpscaling": true,
        "sourceWidth": 1920, "sourceHeight": 1080, "outputWidth": 3840, "outputHeight": 2160,
        "displayMaximumFPS": 240, "displayMaximumEDR": 1.2, "gpuMilliseconds": 2.8,
        "rttPresent": true, "rttSmoothedMicroseconds": 13000, "rttVariationMicroseconds": 0,
        "extensionPresent": true, "extensionJitterMicroseconds": 100, "extensionLossRatio": 0,
        "extensionLost": 7,
        "videoMetricsPresent": true, "videoThroughputBPS": 9_000_000, "videoTransferTimeMicroseconds": 7900,
        "videoReportsPresent": true, "videoReportsSent": 4762,
        "tosPresent": true, "tosLastPresent": true, "tosLastDSCP": 0, "tosLastECN": 0, "tosPackets": 95661,
        "audioReceivedChannels": 6, "audioReceivedSampleRate": 48000, "audioChannels": 6,
        "audioState": 3, "audioSampleRate": 48000, "audioBufferedFrames": 4478,
        "audioUnderruns": 1, "audioOverflows": 6, "audioDroppedFrames": 1408,
        "received": 4687, "lost": 0, "deadlineMisses": 3, "generatedDrops": 0, "decoderFailures": 0,
        "recovered": 0, "streamSeconds": 154, "submitted": 4680, "noDrawable": 2, "rejected": 2
    ]
}

func sampleDiagnosticsReport() -> StreamDiagnosticsReport {
    diagnosticsReport(
        diagnosticsSample(),
        sourceFPS: 59.7,
        presentedFPS: 119.4,
        bitrateMbps: 6.2,
        datacenter: CloudDatacenterSelection(name: "fraa", rttMs: 1, automatic: false, atLaunch: true)
    )
}

private func pairs(_ rows: [StreamDiagnosticsReport.Row]) -> [String] {
    rows.map { "\($0.label)=\($0.value)" }
}

@Test func diagnosticsHeaderChipsComposeRouteTakionCodecFormatAndUpscaler() {
    #expect(sampleDiagnosticsReport().headerChips.map(\.segments) == [
        ["PS Cloud", "fraa", "1 ms"], ["Takion v23"], ["HEVC 10-bit"], ["1080p60 to 120 Hz"], ["MetalFX"]
    ])
}

@Test func diagnosticsHeaderChipsDropUnknownFacts() {
    let report = diagnosticsReport([
        "requestedHeight": 720, "requestedFPS": 60, "presentationFrameRate": 60, "advancedSpatial": true
    ])
    #expect(report.headerChips.map(\.segments) == [["H.264"], ["720p60"], ["FSRCNNX"]])
    let guest = diagnosticsReport(["sourceWidth": 1280, "takionVersionKnown": false, "takionVersion": 12])
    #expect(guest.headerChips.map(\.segments) == [["H.264 8-bit"]])
}

@Test func diagnosticsRouteChipNamesEveryRoute() {
    let automatic = CloudDatacenterSelection(name: "fraa", rttMs: 14, automatic: true)
    let chosen = CloudDatacenterSelection(name: "lona", rttMs: 30, automatic: false)
    let unmeasured = CloudDatacenterSelection(name: "ams", rttMs: nil, automatic: true)
    func route(_ raw: [String: NSNumber], _ datacenter: CloudDatacenterSelection? = nil) -> [String]? {
        diagnosticsReport(raw, datacenter: datacenter).routeChip?.segments
    }
    #expect(route(["route": 4], automatic) == ["PS Cloud", "fraa", "14 ms"])
    #expect(route(["route": 4], chosen) == ["PS Cloud", "lona"])
    #expect(route(["route": 4]) == ["PS Cloud"])
    #expect(route(["route": 3], automatic) == ["PS Now", "fraa", "14 ms"])
    #expect(route(["route": 3], unmeasured) == ["PS Now", "ams"])
    #expect(route(["route": 3]) == ["PS Now"])
    #expect(route(["route": 1, "routeConsole": 5]) == ["PS5", "LAN"])
    #expect(route(["route": 1, "routeConsole": 4]) == ["PS4", "LAN"])
    #expect(route(["route": 2, "routeConsole": 5]) == ["PS5", "Internet"])
    #expect(route(["route": 2, "routeConsole": 4]) == ["PS4", "Internet"])
    #expect(route(["route": 1]) == ["LAN"])
    #expect(route(["route": 2]) == ["Internet"])
    #expect(route([:]) == nil)
    #expect(route([:], automatic) == ["fraa", "14 ms"])
}

@Test func diagnosticsStagesFollowTheFramePipeline() {
    let report = sampleDiagnosticsReport()
    #expect(report.stages.map(\.kind) == [.network, .assembly, .decode, .render, .display])
    #expect(report.stages.map { "\($0.headline) \($0.unit)" } == [
        "6.2 Mbps", "0 lost in 10 s", "59.7 fps", "2.8 ms GPU", "120 Hz"
    ])
    #expect(pairs(report.networkStage.rows) == ["RTT=13 ms", "Loss=0.0%"])
    #expect(pairs(report.assemblyStage.rows) == ["Keyframes asked=0", "Keyframe waits=0"])
    #expect(pairs(report.decodeStage.rows) == ["Errors=0", "Time=–"])
    #expect(pairs(report.renderStage.rows) == ["Budget=8.3 ms", "Upscaler=MetalFX"])
    #expect(pairs(report.displayStage.rows) == ["Missed=0.0/s", "Idle ticks=0.0/s", "Replaced=0.0/s"])
}

@Test func diagnosticsFullSectionsNameWhatEachCounterMeasures() {
    let report = sampleDiagnosticsReport()
    #expect(report.fullSections.map(\.title) == ["Network", "Frames", "Presentation", "Audio"])
    #expect(pairs(report.networkSection.rows) == [
        "Bitrate=6.2 of 35.0 Mbps", "On wire=9.0 Mbps", "Frame transfer=7.9 ms", "Jitter=0.1 ms",
        "Packets received=0", "Packets lost=7", "Rejected=0", "Crypto rejects=0", "Reordered=0",
        "Reorder drops=0", "Internal drops=0", "Marking=Best effort"
    ])
    #expect(pairs(report.framesSection.rows) == [
        "Received=4687", "Lost=0", "Patched references=0", "Repaired by FEC=0", "Keyframe requests=0",
        "Keyframe waits=0",
        "Unassembled=0", "Duplicates=0", "Stale=0", "Decode errors=0"
    ])
    #expect(pairs(report.presentationSection.rows) == [
        "Source=1920 × 1080", "Canvas=3840 × 2160", "Display=240 Hz", "Rendered=119.4 fps",
        "Submitted=4680",
        "Missed refresh=3", "No drawable=2", "Replaced frames=0", "Idle ticks=0", "EDR headroom=1.2×",
        "Zero copy=Active"
    ])
    #expect(pairs(report.audioSection.rows) == [
        "State=Playing", "Received=6 channels", "Playback input=6 channels", "Source rate=48000 Hz",
        "Buffer=93 ms", "Underruns=1", "Overflows=6", "Dropped=1408", "Concealed=0"
    ])
}

@Test func diagnosticsZeroCopyIgnoresFramesWithoutADrawable() {
    #expect(diagnosticsReport(["rejected": 4, "noDrawable": 4]).zeroCopyLabel == "Active")
    let rejected = diagnosticsReport(["rejected": 6, "noDrawable": 4])
    #expect(rejected.zeroCopyLabel == "2 rejected")
    #expect(rejected.zeroCopyTone == .bad)
}

@Test func diagnosticsRowsStayHiddenUntilTheirPresentFlagIsSet() {
    let silent = diagnosticsReport([
        "takionVersion": 23, "rttSmoothedMicroseconds": 9000, "extensionJitterMicroseconds": 100,
        "videoThroughputBPS": 1_000_000, "tosLastDSCP": 46
    ])
    #expect(silent.networkSection.rows.map(\.label) == [
        "Bitrate", "Rejected", "Crypto rejects", "Reordered", "Reorder drops", "Internal drops"
    ])
    #expect(silent.networkStage.rows.first?.value == "–")
    let tosWithoutLast = diagnosticsReport(["tosPresent": true, "tosPackets": 12])
    #expect(!tosWithoutLast.networkSection.rows.map(\.label).contains("Marking"))
    let generating = diagnosticsReport(["requestedFPS": 60, "presentationFrameRate": 120], generatedFPS: 59.8)
    #expect(generating.presentationSection.rows.first { $0.label == "Generated" }?.value == "59.8 fps")
    #expect(generating.presentationSection.rows.map(\.label).contains("Generated drops"))
}

@Test func diagnosticsPacketLossPrefersExtensionThenVideoThenFrames() {
    func loss(_ report: StreamDiagnosticsReport) -> StreamDiagnosticsReport.Row? {
        report.networkStage.rows.first { $0.label == "Loss" }
    }
    let all = diagnosticsReport([
        "extensionPresent": true, "extensionLossRatio": 0.0153,
        "videoMetricsPresent": true, "videoLossRatio": 0.002
    ], lossPercent: 4)
    #expect(loss(all)?.value == "1.5%")
    #expect(loss(all)?.tone == .warning)
    let video = diagnosticsReport(["videoMetricsPresent": true, "videoLossRatio": 0.002], lossPercent: 4)
    #expect(loss(video)?.value == "0.2%")
    let frames = diagnosticsReport([:], lossPercent: 4)
    #expect(loss(frames)?.value == "4.0%")
    #expect(loss(frames)?.tone == .bad)
    #expect(frames.networkStage.tone == .bad)
}

@Test func diagnosticsRTTShowsVariationOnlyFromOneMillisecond() {
    func rtt(_ smoothed: Int, _ variation: Int) -> String {
        diagnosticsReport([
            "rttPresent": true,
            "rttSmoothedMicroseconds": NSNumber(value: smoothed),
            "rttVariationMicroseconds": NSNumber(value: variation)
        ]).rttValue
    }
    #expect(rtt(13000, 0) == "13 ms")
    #expect(rtt(13000, 999) == "13 ms")
    #expect(rtt(7940, 1260) == "7.9 ± 1.3 ms")
    #expect(rtt(25000, 12000) == "25 ± 12 ms")
    #expect(rtt(9960, 0) == "10 ms")
}

@Test func diagnosticsNetworkShowsRTTSpikesAndP99OnceSampled() {
    let report = diagnosticsReport([
        "rttPresent": true, "rttSmoothedMicroseconds": 5000, "rttSamples": 300,
        "rttRecentMaxMicroseconds": 148_400, "rttP99Microseconds": 36_000
    ])
    #expect(pairs(report.networkStage.rows) == [
        "RTT=5.0 ms",
        "RTT spikes=148 ms",
        "RTT p99=36 ms",
        "Loss=0.0%"
    ])
    let quiet = diagnosticsReport([
        "rttPresent": true, "rttSmoothedMicroseconds": 5000, "rttSamples": 300, "rttP99Microseconds": 36_000
    ])
    #expect(pairs(quiet.networkStage.rows)[1] == "RTT spikes=\(StreamDiagnosticsReport.unavailable)")
}

@Test func diagnosticsMarkingNamesDSCPAndAppendsOnlyRealECN() {
    let report = diagnosticsReport([:])
    let names = [0, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 46, 48, 56, 5]
        .map(report.dscpName)
    #expect(names == [
        "Best effort", "CS1", "AF11", "AF12", "AF13", "CS2", "AF21", "AF22", "AF23", "CS3", "AF31", "AF32",
        "AF33", "CS4", "AF41", "AF42", "AF43", "CS5", "Expedited", "CS6", "CS7", "DSCP 5"
    ])
    #expect([0, 1, 2, 3].map(report.ecnMarking) == [nil, "ECT(1)", "ECT(0)", "CE"])
    let marked = diagnosticsReport([
        "tosPresent": true, "tosLastPresent": true, "tosLastDSCP": 46, "tosLastECN": 3
    ])
    #expect(pairs(marked.networkSection.rows).last == "Marking=Expedited CE")
}

@Test func diagnosticsBitrateComparesGoodputWithTheGrantOrRequest() {
    #expect(diagnosticsReport(["requestedBitrate": 35000], bitrateMbps: 6.2).bitrateRow.value
        == "6.2 of 35.0 Mbps")
    #expect(diagnosticsReport(
        ["requestedBitrate": 15000, "grantedPresent": true, "grantedBitrate": 10000],
        bitrateMbps: 6.2
    ).bitrateRow.value == "6.2 of 10.0 Mbps")
    #expect(diagnosticsReport([:], bitrateMbps: 6.2).bitrateRow.value == "6.2 Mbps")
}

@Test func diagnosticsGrantedChipWarnsWhenTheConsoleGaveLess() {
    let requested: [String: NSNumber] = [
        "requestedHeight": 1080,
        "requestedFPS": 60,
        "requestedBitrate": 15000
    ]
    func granted(_ height: Int, _ fps: Int, _ kbps: Int) -> StreamDiagnosticsReport.Chip? {
        var raw = requested
        raw["grantedPresent"] = true
        raw["grantedHeight"] = NSNumber(value: height)
        raw["grantedFPS"] = NSNumber(value: fps)
        raw["grantedBitrate"] = NSNumber(value: kbps)
        return diagnosticsReport(raw).grantedChip
    }
    #expect(diagnosticsReport(requested).grantedChip == nil)
    #expect(granted(1080, 60, 15000) == StreamDiagnosticsReport.Chip(["Granted 1080p60, 15.0 Mbps"]))
    #expect(granted(1080, 60, 10000)
        == StreamDiagnosticsReport.Chip(["Granted 1080p60, 10.0 of 15.0 Mbps"], tone: .warning))
    #expect(granted(720, 60, 15000)?.tone == .warning)
}

@Test func diagnosticsDisplayReportsPresentationWithoutRaisingAnAlarm() {
    let raw: [String: NSNumber] = ["requestedFPS": 60, "presentationFrameRate": 60]
    let uneven = diagnosticsReport(raw, sourceFPS: 59.7, presentedFPS: 38)
    #expect(uneven.displayStage.tone == .neutral)
    #expect(uneven.worstStage == nil)
    #expect(uneven.displayStage.headline == "60")
    #expect(diagnosticsReport([:]).displayStage.headline == "–")
    var sampler = StreamTelemetrySampler()
    var history = StreamDiagnosticsHistory()
    func counters(_ step: Int) -> StreamStatisticsSample {
        StreamStatisticsSample(
            statistics: RenderStatistics(fixture: [
                "deadlineMisses": NSNumber(value: step * 5),
                "idleTicks": NSNumber(value: step * 10),
                "replacedFrames": NSNumber(value: step * 4)
            ]),
            uptime: Double(step)
        )
    }
    _ = sampler.update(counters(0))
    for step in 1...3 {
        history.append(sampler.update(counters(step)))
    }
    let late = diagnosticsReport(raw, sourceFPS: 59.7, presentedFPS: 38, history: history)
    #expect(late.displayStage.tone == .neutral)
    #expect(late.displayStage.rows.allSatisfy { $0.tone == .neutral })
    #expect(late.worstStage == nil)
    #expect(late.displayStage.rows.map { "\($0.label)=\($0.value)" } == [
        "Missed=5.0/s", "Idle ticks=10.0/s", "Replaced=4.0/s"
    ])
}

@Test func diagnosticsRenderStageFlagsAGPUOverItsFrameBudget() {
    let over = diagnosticsReport(["presentationFrameRate": 120, "gpuMilliseconds": 11])
    #expect(over.renderStage.tone == .bad)
    #expect(over.worstStage?.kind == .render)
    let fine = diagnosticsReport(["presentationFrameRate": 60, "gpuMilliseconds": 4])
    #expect(fine.renderStage.tone == .good)
}

@Test func diagnosticsCountersAbbreviateLargeValues() {
    let report = diagnosticsReport([
        "received": 9999, "lost": 10000, "recovered": 12_345_678, "coreFecRepaired": 4321
    ])
    let values = Dictionary(uniqueKeysWithValues: report.framesSection.rows.map { ($0.label, $0.value) })
    #expect(values["Received"] == "9999")
    #expect(values["Lost"] == "10.0k")
    #expect(values["Patched references"] == "12.3M")
    #expect(values["Repaired by FEC"] == "4321")
}

@Test func diagnosticsAudioSummaryNamesTheLayout() {
    #expect(sampleDiagnosticsReport().audioSummary == "5.1 at 48 kHz, 93 ms")
    #expect(diagnosticsReport([:]).audioSummary == "Waiting for audio")
}

@MainActor @Test func diagnosticsOverlayRendersEveryLevelOffscreen() throws {
    guard let directory = ProcessInfo.processInfo.environment["CHIAKI_DIAGNOSTICS_PNG_DIR"] else {
        return
    }
    let looks: [(String, StreamDiagnosticsAppearance)] = StreamDiagnosticsAppearance.Level.allCases
        .filter(\.visible)
        .map { ("\($0)", StreamDiagnosticsAppearance(level: $0, glass: .solid)) }
        + [("floating", StreamDiagnosticsAppearance(level: .full, glass: .solid, layout: .floating))]
    for (name, appearance) in looks {
        let root = ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [.orange, .red, Color(white: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            StreamDiagnosticsOverlay(
                report: sampleDiagnosticsReport(),
                appearance: appearance,
                analysisMode: .off
            )
        }
        .frame(width: 900, height: 760)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("diagnostics-\(name).png"))
    }
}

@Test func diagnosticsStayNeutralUntilTheFirstRatesArrive() {
    let waiting = diagnosticsReport(["requestedFPS": 60, "presentationFrameRate": 60])
    #expect(waiting.decodeStage.tone == .good)
    #expect(waiting.displayStage.tone == .neutral)
    #expect(waiting.worstStage == nil)
}

@Test func diagnosticsCompactPillLeavesDisplayOutAndSaysWhatIsWrong() {
    let slowRender = diagnosticsReport(["presentationFrameRate": 120, "gpuMilliseconds": 11])
    #expect(slowRender.compactAlert?.value == "Render 11 ms GPU")
    let lowFrameRate = diagnosticsReport(
        ["requestedFPS": 60, "presentationFrameRate": 60],
        sourceFPS: 59.8,
        presentedFPS: 30
    )
    #expect(lowFrameRate.worstStage == nil)
    #expect(lowFrameRate.compactAlert == nil)
    #expect(lowFrameRate.compactTone == .good)
    #expect(sampleDiagnosticsReport().presentationSection.rows.first { $0.label == "EDR headroom" }?.tone
        == .neutral)
}

@Test func diagnosticsExplainWhyHDRIsNotShowing() {
    func label(_ raw: [String: NSNumber]) -> String {
        diagnosticsReport(raw).hdrLongLabel
    }
    #expect(label(["route": 4, "requestedHDR": true, "sourceHeight": 1080])
        == "SDR transfer detected; PS5 cloud sends HDR only at 1440p and 4K")
    #expect(label(["route": 1, "requestedHDR": true, "sourceHeight": 1080])
        == "SDR transfer detected; check console HDR")
    var received: [String: NSNumber] = [
        "pq": true, "layerHDR": true, "displayMaximumEDR": 1, "displayPotentialEDR": 1
    ]
    #expect(label(received) == "PQ input, but this screen cannot show HDR")
    received["displayPotentialEDR"] = 16
    #expect(label(received) == "PQ input, but macOS is not giving this screen HDR headroom right now")
    received["displayMaximumEDR"] = 4
    #expect(label(received) == "PQ input with EDR active")
    #expect(diagnosticsReport(received).headroomValue == "4.0× of 16.0×")
    received["displayMaximumEDR"] = 16
    #expect(diagnosticsReport(received).headroomValue == "16.0×")
}

@Test func diagnosticsCallOutBrightAreasThatStopAtSDRWhite() {
    var raw: [String: NSNumber] = [
        "route": 1, "routeConsole": 5, "pq": true, "layerHDR": true, "displayMaximumEDR": 9,
        "displayPotentialEDR": 16, "lightMeasurements": 200, "lightSeconds": 30, "sessionAbovePercent": 0,
        "sessionNearWhitePercent": 6, "lightPeakNits": 198.4, "lightAverageNits": 41.6, "maxCLL": 203,
        "maxFALL": 60, "lightAbovePercent": 0
    ]
    let console = diagnosticsReport(raw)
    #expect(console.hdrLongLabel == "PQ input, but bright areas stop at SDR white; the PS5's TV may be off "
        + "or in SDR, or the game may not use HDR")
    #expect(console.hdrShortLabel == "PQ")
    #expect(console.lightSection.rows.map(\.value) == ["198 nits", "42 nits", "203 nits", "60 nits", "0.0%"])
    #expect(console.fullSections.map(\.title) == ["Network", "Frames", "Presentation", "HDR light", "Audio"])
    raw["route"] = 4
    #expect(diagnosticsReport(raw).hdrLongLabel
        == "PQ input, but bright areas stop at SDR white; the game may not use HDR")
    raw["sessionNearWhitePercent"] = 0.2
    #expect(diagnosticsReport(raw).hdrLongLabel == "PQ input with EDR active")
    raw["sessionNearWhitePercent"] = 6
    raw["sessionAbovePercent"] = 4.2
    #expect(diagnosticsReport(raw).hdrLongLabel == "PQ input with EDR active")
    #expect(diagnosticsReport(raw).hdrShortLabel == "EDR")
    raw["sessionAbovePercent"] = 0
    raw["lightSeconds"] = 5
    #expect(diagnosticsReport(raw).hdrLongLabel == "PQ input with EDR active")
}

@Test func theHeatmapMarkerSaysWhetherItFollowsThePointer() {
    #expect(diagnosticsReport(["markerFollowsPointer": true]).markerTitle == "At the pointer")
    #expect(diagnosticsReport(["markerFollowsPointer": true, "markerVisible": true]).markerHint == nil)
    #expect(diagnosticsReport(["markerVisible": true]).markerVisible)
    #expect(diagnosticsReport([:]).markerTitle == "At the marker")
    #expect(diagnosticsReport([:]).markerHint == StreamDiagnosticsReport.markerHint)
    #expect(!diagnosticsReport([:]).markerVisible)
}

@Test func theHeatmapLegendReadsSDRStreamsAndSaysHowToGetHDR() {
    let sdr = diagnosticsReport(["lightMeasurements": 12, "markerNits": 87, "lightPeakNits": 100])
    #expect(sdr.lightReadings)
    #expect(!sdr.lightMeasured)
    #expect(sdr.nits(sdr.light.markerNits) == "87 nits")
    #expect(sdr.sdrLegendNote == "This stream is SDR, so nothing goes above SDR white. Choose HEVC HDR "
        + "in the Stream panel for an HDR stream.")
    #expect(diagnosticsReport(["lightMeasurements": 12, "requestedHDR": true]).sdrLegendNote
        == "This stream arrived in SDR, so nothing goes above SDR white.")
    #expect(diagnosticsReport(["lightMeasurements": 12, "pq": true]).sdrLegendNote == nil)
    #expect(!diagnosticsReport([:]).lightReadings)
}

@Test func cloudServerFiguresGetTheirOwnSectionOnlyOnceTheServerSendsThem() {
    let quiet =
        StreamDiagnosticsReport(telemetry: StreamTelemetry(statistics: RenderStatistics(fixture: [:])))
    #expect(!quiet.fullSections.map(\.title).contains("Cloud server"))
    let measured = StreamDiagnosticsReport(telemetry: StreamTelemetry(statistics: RenderStatistics(fixture: [
        "serverPresent": true, "serverUsedDownKbps": 15200, "serverAvailableDownKbps": 48000,
        "serverUsedUpKbps": 310, "serverRoundTripMilliseconds": 24, "serverLossPercent": 0.5,
        "serverUpstreamLossPercent": 0, "serverWidth": 1920, "serverHeight": 1080,
        "serverAudioChannels": 2, "serverCorruptFrames": 1
    ])))
    #expect(measured.fullSections.map(\.title) == [
        "Network",
        "Cloud server",
        "Frames",
        "Presentation",
        "Audio"
    ])
    #expect(pairs(measured.serverSection.rows) == [
        "Bandwidth=15.2 of 48.0 Mbps", "Upload=0.3 Mbps", "Round trip=24 ms", "Loss=0.5% down, 0.0% up",
        "Picture sent=1920 × 1080", "Audio channels=2", "Corrupt frames=1"
    ])
    #expect(measured.serverSection.rows.last?.tone == .warning)
}

@MainActor @Test func theFullStatisticsFitANarrowScreenByStackingCards() {
    let telemetry = StreamTelemetry(statistics: RenderStatistics(fixture: [
        "serverPresent": true, "serverUsedDownKbps": 15200, "serverAvailableDownKbps": 48000
    ]))
    func width(columns: Int) -> CGFloat {
        let panel = StreamDiagnosticsPanel(
            report: StreamDiagnosticsReport(telemetry: telemetry),
            level: .full,
            floating: nil,
            controls: StreamDiagnosticsControls(
                appearance: StreamDiagnosticsAppearance(level: .full),
                selectLevel: { _ in },
                selectGlass: { _ in },
                selectLayout: { _ in }
            ),
            columns: columns
        )
        return ImageRenderer(content: panel).uiOrNSImageWidth
    }
    let wide = width(columns: 5)
    let narrow = width(columns: 1)
    #expect(wide >= StreamDiagnosticsPanel.fullCardWidth * 5)
    #expect(narrow <= 420)
}

private extension ImageRenderer {
    @MainActor var uiOrNSImageWidth: CGFloat {
        cgImage.map { CGFloat($0.width) / scale } ?? 0
    }
}
