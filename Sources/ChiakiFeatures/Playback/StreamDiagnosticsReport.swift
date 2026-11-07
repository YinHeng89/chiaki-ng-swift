import ChiakiModels
import Foundation

/// Formats stream telemetry and its recent history into the chips, pipeline stages, sections and labels the
/// diagnostics overlay and panel display.
struct StreamDiagnosticsReport: Equatable {
    /// The connection route the statistics report, numbered as the player reports it.
    enum Route: Int {
        /// The route is not known yet.
        case unknown = 0
        /// A console on the local network.
        case local = 1
        /// A console over the internet.
        case internet = 2
        /// A PS Now cloud stream.
        case psNow = 3
        /// A PS5 cloud stream.
        case psCloud = 4
    }

    /// The console a console route reaches, numbered as the player reports it.
    enum RouteConsole: Int {
        /// The console is not known yet.
        case unknown = 0
        /// A PS4.
        case ps4 = 4
        /// A PS5.
        case ps5 = 5
    }

    /// Health rating for a value, ordered from neutral through good and warning to bad so the worst can be
    /// found with `max()`.
    enum Tone: Equatable, Comparable {
        /// Informational value with no judgement.
        case neutral
        /// Value is within a healthy range.
        case good
        /// Value suggests degraded streaming.
        case warning
        /// Value indicates a serious problem.
        case bad
    }

    /// A labelled value with a health rating, shown as one line of diagnostics.
    struct Row: Equatable {
        /// Name of the measurement.
        let label: LocalizedStringResource
        /// Formatted value.
        let value: LocalizedStringResource
        /// Health rating used to colour the value.
        let tone: Tone

        /// Creates a row.
        ///
        /// - Parameters:
        ///   - label: Name of the measurement.
        ///   - value: Formatted value.
        ///   - tone: Health rating, neutral by default.
        init(_ label: LocalizedStringResource, _ value: LocalizedStringResource, _ tone: Tone = .neutral) {
            self.label = label
            self.value = value
            self.tone = tone
        }
    }

    /// Step of the streaming pipeline that a diagnostics stage summarises.
    enum StageKind: CaseIterable {
        /// Packets arriving from the console.
        case network
        /// Packets assembled into frames.
        case assembly
        /// Frames decoded into images.
        case decode
        /// Frames rendered on the GPU.
        case render
        /// Frames presented to the display.
        case display

        /// The stage's title, shown on its card and in the compact alert.
        var title: LocalizedStringResource {
            switch self {
            case .network:
                .playbackDiagnosticsStageNetwork
            case .assembly:
                .playbackDiagnosticsStageAssembly
            case .decode:
                .playbackDiagnosticsStageDecode
            case .render:
                .playbackDiagnosticsStageRender
            case .display:
                .playbackDiagnosticsStageDisplay
            }
        }
    }

    /// Summary of one pipeline step: a headline figure, its graph history and supporting rows.
    struct Stage: Equatable, Identifiable {
        /// Pipeline step this stage summarises.
        let kind: StageKind
        /// Main figure shown for the stage.
        let headline: String
        /// Unit text shown after the headline.
        let unit: LocalizedStringResource
        /// Health rating used to colour the value.
        let tone: Tone
        /// Graph values from the diagnostics history, oldest first.
        let series: [Double]
        /// Supporting measurements shown under the headline.
        let rows: [Row]

        /// Identifies the stage by its pipeline step.
        var id: StageKind {
            kind
        }
    }

    /// Titled group of rows in the full diagnostics listing.
    struct Section: Equatable, Identifiable {
        /// Heading shown above the rows.
        let title: LocalizedStringResource
        /// Supporting measurements shown under the headline.
        let rows: [Row]

        /// Identifies the section by its title's catalog key.
        var id: String {
            title.key
        }
    }

    /// Header badge made of text segments laid out side by side, with a health rating.
    struct Chip: Equatable {
        /// Text pieces shown in order within the chip.
        let segments: [LocalizedStringResource]
        /// Health rating used to colour the chip.
        var tone = Tone.neutral

        /// Creates a chip.
        ///
        /// - Parameters:
        ///   - segments: Text pieces shown in order.
        ///   - tone: Health rating, neutral by default.
        init(_ segments: [LocalizedStringResource], tone: Tone = .neutral) {
            self.segments = segments
            self.tone = tone
        }
    }

    /// Placeholder shown when a value is not available.
    static let unavailable = "–"
    /// Brightness of SDR reference white in nits, used to express content peaks as EDR headroom.
    static let referenceWhiteNits = 203.0
    /// Fraction of the display's EDR headroom content may use before highlights are compressed.
    static let headroomTarget = 0.95

    /// Latest telemetry the report describes.
    let telemetry: StreamTelemetry
    /// Recent intervals used for graphs and recent totals.
    let history: StreamDiagnosticsHistory
    /// Cloud datacenter the session runs in, if any, shown in the route chip.
    let datacenter: CloudDatacenterSelection?

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - telemetry: Latest telemetry.
    ///   - history: Recent intervals, empty by default.
    ///   - datacenter: Cloud datacenter for the session, if any.
    init(
        telemetry: StreamTelemetry,
        history: StreamDiagnosticsHistory = .init(),
        datacenter: CloudDatacenterSelection? = nil
    ) {
        self.telemetry = telemetry
        self.history = history
        self.datacenter = datacenter
    }
}

extension StreamDiagnosticsReport {
    /// Header badges for route, protocol version, codec, requested format, granted format and upscaler,
    /// including only those that are known.
    var headerChips: [Chip] {
        var chips = [Chip]()
        if let route = routeChip {
            chips.append(route)
        }
        if stats.takionVersionKnown {
            chips.append(Chip([.playbackDiagnosticsTakionVersion(version: String(stats.takionVersion))]))
        }
        chips.append(Chip([codecDescription]))
        if let format = requestedFormat {
            chips.append(Chip([format]))
        }
        if let granted = grantedChip {
            chips.append(granted)
        }
        if let upscaler {
            chips.append(Chip([upscaler]))
        }
        return chips
    }

    /// Badge naming the connection route with its console or datacenter details, or `nil` when there is
    /// nothing to show.
    var routeChip: Chip? {
        let route = Route(rawValue: stats.route) ?? .unknown
        var segments = [LocalizedStringResource]()
        switch route {
        case .psCloud:
            segments = [.verbatim("PS Cloud")] + datacenterSegments
        case .psNow:
            segments = [.verbatim("PS Now")] + datacenterSegments
        case .local:
            segments = consoleSegments + [.playbackDiagnosticsRouteLan]
        case .internet:
            segments = consoleSegments + [.playbackDiagnosticsRouteInternet]
        default:
            segments = datacenterSegments
        }
        guard !segments.isEmpty else {
            return nil
        }
        return Chip(segments)
    }

    /// Console model for a local or internet route, or empty when unknown.
    var consoleSegments: [LocalizedStringResource] {
        switch RouteConsole(rawValue: stats.routeConsole) ?? .unknown {
        case .ps4:
            return [.verbatim("PS4")]
        case .ps5:
            return [.verbatim("PS5")]
        default:
            return []
        }
    }

    /// Datacenter name, followed by its measured latency when the datacenter was chosen automatically or at
    /// launch.
    var datacenterSegments: [LocalizedStringResource] {
        guard let datacenter else {
            return []
        }
        guard let rttMs = datacenter.rttMs, datacenter.automatic || datacenter.atLaunch else {
            return [.verbatim(datacenter.name)]
        }
        return [.verbatim(datacenter.name), .playbackDiagnosticsMilliseconds(value: String(rttMs))]
    }

    /// Requested codec with its bit depth once the source resolution is known.
    var codecDescription: LocalizedStringResource {
        guard stats.sourceWidth > 0 else {
            return .verbatim(requestedCodec)
        }
        if stats.tenBit {
            return .playbackDiagnosticsCodecTenBit(codec: requestedCodec)
        }
        return .playbackDiagnosticsCodecEightBit(codec: requestedCodec)
    }

    /// Codec the session asked for: HEVC HDR, HEVC or H.264.
    var requestedCodec: String {
        if stats.requestedHDR {
            return "HEVC HDR"
        }
        if stats.requestedHEVC {
            return "HEVC"
        }
        return "H.264"
    }

    /// Requested resolution and frame rate, plus the presentation rate when it differs, or `nil` when no
    /// height was requested.
    var requestedFormat: LocalizedStringResource? {
        let height = String(stats.requestedHeight)
        guard stats.requestedHeight > 0 else {
            return nil
        }
        let fps = stats.requestedFPS
        let presentation = stats.presentationFrameRate
        let presented = presentation > 0 && presentation != fps
        switch (fps > 0, presented) {
        case (true, true):
            return .playbackDiagnosticsFormatHeightRatePresented(
                height: height,
                fps: String(fps),
                rate: String(presentation)
            )
        case (true, false):
            return .playbackDiagnosticsFormatHeightRate(height: height, fps: String(fps))
        case (false, true):
            return .playbackDiagnosticsFormatHeightPresented(height: height, rate: String(presentation))
        case (false, false):
            return .playbackDiagnosticsFormatHeight(height: height)
        }
    }

    /// Badge describing the resolution, frame rate and bitrate the console granted, rated as a warning when
    /// any falls short of the request.
    var grantedChip: Chip? {
        guard stats.grantedPresent else {
            return nil
        }
        let height = stats.grantedHeight
        let fps = stats.grantedFPS
        let granted = Double(stats.grantedBitrate) / 1000
        let requested = Double(stats.requestedBitrate) / 1000
        let text: LocalizedStringResource
        if granted <= 0 {
            text = .playbackDiagnosticsGranted(height: String(height), fps: String(fps))
        } else if requested > 0 && abs(granted - requested) >= 0.05 {
            text = .playbackDiagnosticsGrantedBitrateShort(
                height: String(height),
                fps: String(fps),
                granted: oneDecimal(granted),
                requested: oneDecimal(requested)
            )
        } else {
            text = .playbackDiagnosticsGrantedBitrate(
                height: String(height),
                fps: String(fps),
                granted: oneDecimal(granted)
            )
        }
        let short = height < stats.requestedHeight
            || fps < stats.requestedFPS
            || requested > 0 && granted > 0 && granted < requested - 0.05
        return Chip(
            [text],
            tone: short
                ? .warning
                : .neutral
        )
    }

    /// Bitrate target in megabits per second, using the granted bitrate when present and the requested one
    /// otherwise.
    var targetBitrateMbps: Double {
        if stats.grantedPresent, stats.grantedBitrate > 0 {
            return Double(stats.grantedBitrate) / 1000
        }
        return Double(stats.requestedBitrate) / 1000
    }

    /// Name of the active upscaler, or `nil` when spatial upscaling is off.
    var upscaler: LocalizedStringResource? {
        if stats.advancedSpatial {
            return .verbatim("FSRCNNX")
        }
        if stats.spatialUpscaling {
            return .verbatim("MetalFX")
        }
        return nil
    }

    /// Stream duration formatted as minutes and seconds.
    var uptime: String {
        let seconds = max(0, Int(stats.streamSeconds))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

extension StreamDiagnosticsReport {
    /// Pipeline stages in order from network to display.
    var stages: [Stage] {
        [networkStage, assemblyStage, decodeStage, renderStage, displayStage]
    }

    /// Worst health rating across all stages.
    var overallTone: Tone {
        stages.map(\.tone).max() ?? .neutral
    }

    /// First stage with the worst rating, or `nil` when no stage is at warning or worse.
    var worstStage: Stage? {
        let stages = stages
        guard let worst = stages.map(\.tone).max(), worst >= .warning else {
            return nil
        }
        return stages.first { $0.tone == worst }
    }

    /// Stages shown in the compact overlay, which omits the display stage.
    var compactStages: [Stage] {
        stages.filter { $0.kind != .display }
    }

    /// Worst health rating across the compact stages.
    var compactTone: Tone {
        compactStages.map(\.tone).max() ?? .neutral
    }

    /// Short alert describing the worst compact stage at warning or worse, built from its worst row or its
    /// headline, or `nil` when everything is healthy.
    var compactAlert: Row? {
        let stages = compactStages
        guard let worst = stages.map(\.tone).max(), worst >= .warning,
              let stage = stages.first(where: { $0.tone == worst }) else {
            return nil
        }
        if let row = stage.rows.first(where: { $0.tone == worst }) {
            return Row(
                stage.kind.title,
                .playbackDiagnosticsAlertRow(
                    stage: String(localized: stage.kind.title),
                    measurement: String(localized: row.label).localizedLowercase,
                    value: String(localized: row.value)
                ),
                worst
            )
        }
        guard stage.kind != .network else {
            return nil
        }
        return Row(
            stage.kind.title,
            .playbackDiagnosticsAlertHeadline(
                stage: String(localized: stage.kind.title),
                headline: stage.headline,
                unit: String(localized: stage.unit)
            ),
            worst
        )
    }

    /// Whether no interval has elapsed and no frames have been seen yet, so rates cannot be judged.
    var measuring: Bool {
        telemetry.interval.seconds <= 0 && telemetry.sourceFPS == 0 && telemetry.presentedFPS == 0
    }

    /// Network stage showing bitrate, round-trip time with its recent worst and stream 99th percentile, and
    /// packet loss, rated by loss.
    var networkStage: Stage {
        var rows = [Row]()
        if stats.rttPresent {
            rows.append(Row(.playbackDiagnosticsRowRtt, rttValue))
            if stats.rttSamples > 0 {
                let spikes = stats.rttRecentMaxMicroseconds > 0
                    ? millisecondsValue(stats.rttRecentMaxMicroseconds / 1000)
                    : .verbatim(Self.unavailable)
                rows.append(Row(.playbackDiagnosticsRowRttSpikes, spikes))
                rows.append(Row(
                    .playbackDiagnosticsRowRttP99,
                    millisecondsValue(stats.rttP99Microseconds / 1000)
                ))
            }
        } else {
            rows.append(Row(.playbackDiagnosticsRowRtt, .verbatim(Self.unavailable)))
        }
        rows.append(Row(
            .playbackDiagnosticsRowLoss,
            .verbatim(percent(packetLossPercent)),
            lossTone(packetLossPercent)
        ))
        return Stage(
            kind: .network,
            headline: oneDecimal(telemetry.bitrateMbps),
            unit: .playbackDiagnosticsUnitMbps,
            tone: lossTone(packetLossPercent),
            series: history.series(\.bitrateMbps),
            rows: rows
        )
    }

    /// Assembly stage showing frames lost over the recent window, with keyframe requests and waits.
    var assemblyStage: Stage {
        let lost = history.recent(\.framesLost)
        /// Health rating used to colour the value.
        let tone: Tone
        if lost == 0 {
            tone = .good
        } else if lost < 10 {
            tone = .warning
        } else {
            tone = .bad
        }
        let requests = history.recent(\.keyframeRequests)
        let waits = history.recent(\.keyframeWaits)
        return Stage(
            kind: .assembly,
            headline: String(lost),
            unit: .playbackDiagnosticsUnitLostRecently,
            tone: tone,
            series: history.series(\.framesLost),
            rows: [
                Row(.playbackDiagnosticsRowKeyframesAsked, .verbatim(String(requests)), countTone(requests)),
                Row(.playbackDiagnosticsRowKeyframeWaits, .verbatim(String(waits)), countTone(waits))
            ]
        )
    }

    /// Decode stage showing decoded frame rate and recent decode errors.
    var decodeStage: Stage {
        let errors = history.recent(\.decodeErrors)
        let tone = max(sourceFPSTone, countTone(errors, bad: true))
        return Stage(
            kind: .decode,
            headline: oneDecimal(telemetry.sourceFPS),
            unit: .playbackDiagnosticsUnitFps,
            tone: tone,
            series: history.series(\.decodedFPS),
            rows: [
                Row(.playbackDiagnosticsRowErrors, .verbatim(String(errors)), countTone(errors, bad: true)),
                Row(.playbackDiagnosticsRowTime, .verbatim(Self.unavailable))
            ]
        )
    }

    /// Render stage showing GPU time per frame against the frame budget, and the upscaler state.
    var renderStage: Stage {
        var upscalerTone = Tone.neutral
        if stats.advancedBudgetFallback {
            upscalerTone = .warning
        }
        return Stage(
            kind: .render,
            headline: millisecondsNumber(stats.gpuMilliseconds),
            unit: .playbackDiagnosticsUnitGpuMilliseconds,
            tone: gpuTone,
            series: history.series(\.gpuMilliseconds),
            rows: [
                Row(.playbackDiagnosticsRowBudget, millisecondsValue(telemetry.frameBudgetMilliseconds)),
                Row(.playbackDiagnosticsRowUpscaler, upscalerState, upscalerTone)
            ]
        )
    }

    /// Display stage showing the presentation rate with missed refreshes, idle ticks and replaced frames per
    /// second.
    var displayStage: Stage {
        let misses = history.recentRate(\.refreshMisses)
        return Stage(
            kind: .display,
            headline: presentationRate,
            unit: .playbackDiagnosticsUnitHertz,
            tone: .neutral,
            series: history.series(\.missRate),
            rows: [
                Row(.playbackDiagnosticsRowMissed, .verbatim("\(oneDecimal(misses))/s")),
                Row(
                    .playbackDiagnosticsRowIdleTicks,
                    .verbatim("\(oneDecimal(history.recentRate(\.idleTicks)))/s")
                ),
                Row(
                    .playbackDiagnosticsRowReplaced,
                    .verbatim("\(oneDecimal(history.recentRate(\.replacedFrames)))/s")
                )
            ]
        )
    }

    /// Presentation frame rate, falling back to the requested rate, or the unavailable placeholder.
    var presentationRate: String {
        var rate = stats.presentationFrameRate
        if rate <= 0 {
            rate = stats.requestedFPS
        }
        guard rate > 0 else {
            return Self.unavailable
        }
        return String(rate)
    }

    /// Upscaler name, `Off`, or `Over budget` when the advanced upscaler fell back for exceeding its budget.
    var upscalerState: LocalizedStringResource {
        guard let upscaler else {
            return .commonOff
        }
        if stats.advancedBudgetFallback {
            return .playbackDiagnosticsUpscalerOverBudget
        }
        return upscaler
    }
}

extension StreamDiagnosticsReport {
    /// One-line audio description with channel layout, sample rate and buffer depth, or a waiting message
    /// before audio arrives.
    var audioSummary: LocalizedStringResource {
        let channels = stats.audioReceivedChannels
        guard channels > 0 else {
            return .playbackDiagnosticsAudioWaiting
        }
        let rate = Double(stats.audioReceivedSampleRate) / 1000
        let kilohertz = rate == rate.rounded()
            ? String(Int(rate))
            : oneDecimal(rate)
        return .playbackDiagnosticsAudioSummary(
            layout: String(localized: channelLayout(channels)),
            rate: kilohertz,
            buffer: String(localized: audioBuffer)
        )
    }

    /// Row counting recent audio underruns, or reporting audio unavailable when the output device failed.
    var audioUnderrunsSummary: Row {
        let underruns = history.recent(\.audioUnderruns)
        if stats.audioDeviceFailures > 0 {
            return Row(.playbackDiagnosticsRowAudio, .playbackDiagnosticsAudioUnavailable, .bad)
        }
        return Row(
            .playbackDiagnosticsRowAudio,
            .playbackDiagnosticsUnderruns(count: Int(underruns)),
            countTone(underruns)
        )
    }

    /// Names a channel layout.
    ///
    /// - Parameter channels: Number of audio channels.
    /// - Returns: Mono, Stereo, 5.1, 7.1 or a channel count.
    func channelLayout(_ channels: Int) -> LocalizedStringResource {
        switch channels {
        case 1:
            .playbackDiagnosticsLayoutMono
        case 2:
            .playbackDiagnosticsLayoutStereo
        case 6:
            .verbatim("5.1")
        case 8:
            .verbatim("7.1")
        default:
            .playbackDiagnosticsLayoutChannels(count: channels)
        }
    }

    /// Audio playback state: unavailable, waiting, priming or playing.
    var audioStatus: LocalizedStringResource {
        if stats.audioDeviceFailures > 0 {
            return .playbackDiagnosticsAudioUnavailable
        }
        switch stats.audioState {
        case 2:
            return .playbackDiagnosticsAudioPriming
        case 3:
            return .playbackDiagnosticsAudioPlaying
        default:
            return .playbackDiagnosticsAudioWaitingShort
        }
    }

    /// Channel count received from the console, noting how many are active when fewer than all.
    var receivedAudioChannels: LocalizedStringResource {
        let channels = stats.audioReceivedChannels
        let active = stats.audioReceivedActiveChannels
        guard channels > 0, active > 0, active < channels else {
            return audioChannels(channels)
        }
        return .playbackDiagnosticsReceivedChannelsActive(channels: channels, active: active)
    }

    /// Channel count fed into audio playback.
    var playbackAudioChannels: LocalizedStringResource {
        audioChannels(stats.audioChannels)
    }

    /// Sample rate received from the console in hertz, or waiting before audio arrives.
    var receivedAudioRate: LocalizedStringResource {
        guard stats.audioReceivedChannels > 0 else {
            return .playbackDiagnosticsAudioWaitingShort
        }
        return .playbackDiagnosticsHertz(value: String(stats.audioReceivedSampleRate))
    }

    /// Buffered audio in milliseconds.
    var audioBuffer: LocalizedStringResource {
        let sampleRate = max(1, stats.audioSampleRate)
        let milliseconds = Double(stats.audioBufferedFrames) / Double(sampleRate) * 1000
        return .playbackDiagnosticsMilliseconds(value: String(Int(milliseconds.rounded())))
    }

    /// Audio health: bad after a device failure, warning after any underrun or overflow, good otherwise.
    var audioTone: Tone {
        if stats.audioDeviceFailures > 0 {
            return .bad
        }
        if stats.audioUnderruns > 0 || stats.audioOverflows > 0 {
            return .warning
        }
        return .good
    }

    /// Describes an audio channel count.
    ///
    /// - Parameter count: The channels.
    /// - Returns: The count with its unit, or that audio is still awaited.
    func audioChannels(_ count: Int) -> LocalizedStringResource {
        guard count > 0 else {
            return .playbackDiagnosticsAudioWaitingShort
        }
        return .playbackDiagnosticsChannels(count: count)
    }
}

extension StreamDiagnosticsReport {
    /// Sections of the full diagnostics listing: network, frames, presentation and audio.
    var fullSections: [Section] {
        var sections = [networkSection, framesSection, presentationSection, audioSection]
        if lightMeasured {
            sections.insert(lightSection, at: 3)
        }
        if serverMeasured {
            sections.insert(serverSection, at: 1)
        }
        return sections
    }

    /// Network section with bitrate, throughput, jitter, packet counters, drops, errors and traffic marking
    /// where available.
    var networkSection: Section {
        var rows = [bitrateRow]
        if stats.videoMetricsPresent {
            rows.append(Row(
                .playbackDiagnosticsRowOnWire,
                .playbackDiagnosticsMegabits(value: oneDecimal(stats.videoThroughputBPS / 1_000_000))
            ))
            rows.append(Row(
                .playbackDiagnosticsRowFrameTransfer,
                millisecondsValue(stats.videoTransferTimeMicroseconds / 1000)
            ))
        }
        if stats.extensionPresent {
            rows.append(Row(
                .playbackDiagnosticsRowJitter,
                millisecondsValue(stats.extensionJitterMicroseconds / 1000)
            ))
            rows.append(Row(.playbackDiagnosticsRowPacketsReceived, counter(stats.corePacketsReceived)))
            rows.append(Row(.playbackDiagnosticsRowPacketsLost, counter(stats.extensionLost)))
        }
        rows.append(Row(.playbackDiagnosticsRowRejected, counter(stats.coreRejectedPackets)))
        rows.append(Row(.playbackDiagnosticsRowCryptoRejects, counter(stats.coreCryptoRejections)))
        rows.append(Row(.playbackDiagnosticsRowReordered, counter(stats.coreReorderSkipped)))
        rows.append(Row(.playbackDiagnosticsRowReorderDrops, counter(stats.coreReorderDropped)))
        let internalDrops = stats.coreDroppedPosts + stats.coreSendDropped
        rows.append(Row(
            .playbackDiagnosticsRowInternalDrops,
            .verbatim(String(internalDrops)),
            countTone(UInt64(max(0, internalDrops)))
        ))
        if stats.coreLoopErrors > 0 {
            rows.append(Row(.playbackDiagnosticsRowSessionErrors, counter(stats.coreLoopErrors), .bad))
        }
        if stats.tosPresent, stats.tosLastPresent {
            rows.append(Row(.playbackDiagnosticsRowMarking, marking))
        }
        return Section(title: .playbackDiagnosticsSectionNetwork, rows: rows)
    }

    /// Frames section with cumulative receive, loss, reference patch, FEC repair, keyframe, assembly and decode
    /// counters.
    var framesSection: Section {
        Section(title: .playbackDiagnosticsSectionFrames, rows: [
            Row(.playbackDiagnosticsRowReceived, counter(stats.received)),
            Row(.playbackDiagnosticsRowLost, counter(stats.lost)),
            Row(.playbackDiagnosticsRowPatchedReferences, counter(stats.recovered)),
            Row(.playbackDiagnosticsRowRepairedByFec, counter(stats.coreFecRepaired)),
            Row(.playbackDiagnosticsRowKeyframeRequests, counter(stats.keyframeRequests)),
            Row(.playbackDiagnosticsRowKeyframeWaits, counter(stats.coreDependencyRejections)),
            Row(.playbackDiagnosticsRowUnassembled, counter(stats.coreAssemblyRejections)),
            Row(.playbackDiagnosticsRowDuplicates, counter(stats.coreVideoDuplicate)),
            Row(.playbackDiagnosticsRowStale, counter(stats.coreVideoStale)),
            Row(
                .playbackDiagnosticsRowDecodeErrors,
                counter(stats.decoderFailures),
                countTone(UInt64(stats.decoderFailures), bad: true)
            )
        ])
    }

    /// Presentation section with resolutions, refresh and frame rates, presentation counters, EDR headroom
    /// and zero-copy state.
    var presentationSection: Section {
        var rows = [
            Row(.playbackDiagnosticsRowSource, resolution(stats.sourceWidth, stats.sourceHeight)),
            Row(.playbackDiagnosticsRowCanvas, resolution(stats.outputWidth, stats.outputHeight)),
            Row(
                .playbackDiagnosticsRowDisplay,
                .playbackDiagnosticsHertz(value: String(stats.displayMaximumFPS))
            ),
            Row(
                .playbackDiagnosticsRowRendered,
                .playbackDiagnosticsFramesPerSecond(value: oneDecimal(telemetry.presentedFPS))
            ),
            Row(.playbackDiagnosticsRowSubmitted, counter(stats.submitted)),
            Row(.playbackDiagnosticsRowMissedRefresh, counter(stats.deadlineMisses)),
            Row(.playbackDiagnosticsRowNoDrawable, counter(stats.noDrawable)),
            Row(.playbackDiagnosticsRowReplacedFrames, counter(stats.replacedFrames)),
            Row(.playbackDiagnosticsRowIdleTicks, counter(stats.idleTicks)),
            Row(.playbackDiagnosticsRowEdrHeadroom, headroomValue, edrTone),
            Row(.playbackDiagnosticsRowZeroCopy, zeroCopyLabel, zeroCopyTone)
        ]
        if telemetry.generatedFPS > 0 {
            rows.insert(Row(
                .playbackDiagnosticsRowGenerated,
                .playbackDiagnosticsFramesPerSecond(value: oneDecimal(telemetry.generatedFPS))
            ), at: 3)
            rows.append(Row(.playbackDiagnosticsRowGeneratedDrops, counter(stats.generatedDrops)))
        }
        if stats.gpuError != 0 {
            rows.append(Row(.playbackDiagnosticsRowGpuError, .verbatim(String(stats.gpuError)), .bad))
        }
        return Section(title: .playbackDiagnosticsSectionPresentation, rows: rows)
    }

    /// Audio section with playback state, channels, rate, buffer and audio counters.
    var audioSection: Section {
        Section(title: .playbackDiagnosticsSectionAudio, rows: [
            Row(.playbackDiagnosticsRowState, audioStatus, audioTone),
            Row(.playbackDiagnosticsRowReceived, receivedAudioChannels),
            Row(.playbackDiagnosticsRowPlaybackInput, playbackAudioChannels),
            Row(.playbackDiagnosticsRowSourceRate, receivedAudioRate),
            Row(.playbackDiagnosticsRowBuffer, audioBuffer),
            Row(.playbackDiagnosticsRowUnderruns, counter(stats.audioUnderruns), audioTone),
            Row(.playbackDiagnosticsRowOverflows, counter(stats.audioOverflows), audioTone),
            Row(.playbackDiagnosticsRowDropped, counter(stats.audioDroppedFrames), audioTone),
            Row(.playbackDiagnosticsRowConcealed, counter(stats.audioConcealmentFrames))
        ])
    }

    /// Row showing the received bitrate, against the target when one is known.
    var bitrateRow: Row {
        let target = targetBitrateMbps
        guard target > 0 else {
            return Row(
                .playbackDiagnosticsRowBitrate,
                .playbackDiagnosticsMegabits(value: oneDecimal(telemetry.bitrateMbps))
            )
        }
        return Row(
            .playbackDiagnosticsRowBitrate,
            .playbackDiagnosticsMegabitsOf(
                value: oneDecimal(telemetry.bitrateMbps),
                total: oneDecimal(target)
            )
        )
    }

    /// Last observed DSCP class of the stream's packets, followed by its ECN codepoint when one was set.
    var marking: LocalizedStringResource {
        let dscp = dscpName(stats.tosLastDSCP)
        guard let ecn = ecnMarking(stats.tosLastECN) else {
            return dscp
        }
        return .playbackDiagnosticsMarkingWithEcn(dscp: String(localized: dscp), ecn: ecn)
    }

    /// Frames rejected for reasons other than a missing drawable, counted as zero-copy failures.
    var zeroCopyFailures: Int {
        max(0, stats.rejected - stats.noDrawable)
    }

    /// Zero-copy state: active, or the number of rejected frames.
    var zeroCopyLabel: LocalizedStringResource {
        if zeroCopyFailures == 0 {
            return .playbackDiagnosticsZeroCopyActive
        }
        return .playbackDiagnosticsZeroCopyRejected(count: zeroCopyFailures)
    }

    /// Good while zero-copy has no failures, bad otherwise.
    var zeroCopyTone: Tone {
        if zeroCopyFailures == 0 {
            return .good
        }
        return .bad
    }

    /// Names a DSCP value.
    ///
    /// - Parameter value: The DSCP codepoint.
    /// - Returns: Best effort, a class selector, an assured forwarding class, Expedited, or the raw value.
    func dscpName(_ value: Int) -> LocalizedStringResource {
        switch value {
        case 0:
            return .playbackDiagnosticsDscpBestEffort
        case 8, 16, 24, 32, 40, 48, 56:
            return .verbatim("CS\(value / 8)")
        case 10, 12, 14, 18, 20, 22, 26, 28, 30, 34, 36, 38:
            return .verbatim("AF\(value / 8)\((value % 8) / 2)")
        case 46:
            return .playbackDiagnosticsDscpExpedited
        default:
            return .verbatim("DSCP \(value)")
        }
    }

    /// Names an ECN codepoint when one was set.
    ///
    /// - Parameter value: The ECN codepoint.
    /// - Returns: The name, or `nil` for Not-ECT.
    func ecnMarking(_ value: Int) -> String? {
        guard value != 0 else {
            return nil
        }
        return ecnName(value)
    }

    /// Names an ECN codepoint.
    ///
    /// - Parameter value: The ECN codepoint.
    /// - Returns: Not-ECT, ECT(1), ECT(0), CE or the raw value.
    func ecnName(_ value: Int) -> String {
        switch value {
        case 0:
            return "Not-ECT"
        case 1:
            return "ECT(1)"
        case 2:
            return "ECT(0)"
        case 3:
            return "CE"
        default:
            return "ECN \(value)"
        }
    }
}

extension StreamDiagnosticsReport {
    /// Short dynamic range label: EDR when HDR output is active, PQ when PQ input is not shown as HDR, SDR
    /// otherwise.
    var hdrShortLabel: LocalizedStringResource {
        if hdrOutputActive, !sendsSDRBrightness {
            return .playbackDiagnosticsHdrShortEdr
        }
        if stats.perceptualQuantizer {
            return .playbackDiagnosticsHdrShortPq
        }
        return .playbackDiagnosticsHdrShortSdr
    }

    /// Sentence explaining the HDR pipeline state, including why HDR is inactive or how the content peak is
    /// tone mapped.
    var hdrLongLabel: LocalizedStringResource {
        if !stats.perceptualQuantizer {
            if stats.requestedHDR {
                return requestedHDRSentSDR
            }
            return .playbackDiagnosticsHdrNotRequested
        }
        if !stats.layerHDR {
            return .playbackDiagnosticsHdrLayerInactive
        }
        if stats.displayPotentialEDR > 0, stats.displayPotentialEDR <= 1 {
            return .playbackDiagnosticsHdrScreenCannot
        }
        if stats.displayMaximumEDR <= 1 {
            return .playbackDiagnosticsHdrNoHeadroom
        }
        if sendsSDRBrightness {
            return sdrBrightnessLabel
        }
        guard stats.toneMapSource > 0, stats.contentPeakNits > 0 else {
            return .playbackDiagnosticsHdrActive
        }
        let peak = String(Int(stats.contentPeakNits.rounded()))
        let streamPeak = stats.toneMapSource == 1
        switch (compressesHighlights, streamPeak) {
        case (false, true):
            return .playbackDiagnosticsHdrStreamPeakFits(peak: peak)
        case (false, false):
            return .playbackDiagnosticsHdrDefaultPeakFits(peak: peak)
        case (true, true):
            return .playbackDiagnosticsHdrStreamPeakCompressed(peak: peak)
        case (true, false):
            return .playbackDiagnosticsHdrDefaultPeakCompressed(peak: peak)
        }
    }

    /// Whether the content peak exceeds the usable EDR headroom, so highlights are compressed.
    var compressesHighlights: Bool {
        stats.contentPeakNits / Self.referenceWhiteNits
            > stats.displayMaximumEDR * Self.headroomTarget
    }

    /// Bit depth and colour gamut of the video.
    var colourDescription: LocalizedStringResource {
        if stats.tenBit {
            return .playbackDiagnosticsColourTenBit(gamut: gamutDescription)
        }
        return .playbackDiagnosticsColourEightBit(gamut: gamutDescription)
    }

    /// Colour gamut of the video: BT.2020 or BT.709.
    var gamutDescription: String {
        if stats.bt2020 {
            return "BT.2020"
        }
        return "BT.709"
    }

    /// Good when HDR output is active, warning otherwise.
    var hdrTone: Tone {
        if hdrOutputActive, !sendsSDRBrightness {
            return .good
        }
        return .warning
    }

    /// EDR headroom rating, neutral for SDR input and the HDR rating for PQ input.
    var edrTone: Tone {
        guard stats.perceptualQuantizer else {
            return .neutral
        }
        return hdrTone
    }

    /// Whether PQ video is being shown on an HDR layer on a display with EDR headroom.
    var hdrOutputActive: Bool {
        stats.perceptualQuantizer
            && stats.layerHDR
            && stats.displayMaximumEDR > 1
    }
}

extension StreamDiagnosticsReport {
    /// Packet loss percentage from the telemetry.
    var packetLossPercent: Double {
        telemetry.packetLossPercent
    }

    /// Smoothed round-trip time, with its variation when that is at least one millisecond.
    var rttValue: LocalizedStringResource {
        let smoothed = stats.rttSmoothedMicroseconds / 1000
        let variation = stats.rttVariationMicroseconds / 1000
        guard variation >= 1 else {
            return millisecondsValue(smoothed)
        }
        return .playbackDiagnosticsMillisecondsVariation(
            value: millisecondsNumber(smoothed),
            variation: millisecondsNumber(variation)
        )
    }

    /// Decoded frame rate rated against the requested rate, neutral while measuring.
    var sourceFPSTone: Tone {
        guard !measuring else {
            return .neutral
        }
        return ratioTone(telemetry.sourceFPS, target: Double(max(1, stats.requestedFPS)))
    }

    /// GPU time rated against the frame budget: good below 60 percent, warning below 90 percent, bad above.
    var gpuTone: Tone {
        let budget = telemetry.frameBudgetMilliseconds
        let gpu = stats.gpuMilliseconds
        if gpu < budget * 0.6 {
            return .good
        }
        if gpu < budget * 0.9 {
            return .warning
        }
        return .bad
    }

    /// Rates a packet loss percentage.
    ///
    /// - Parameter percent: Loss percentage.
    /// - Returns: Good below 0.5, warning below 2, bad otherwise.
    func lossTone(_ percent: Double) -> Tone {
        if percent < 0.5 {
            return .good
        }
        if percent < 2 {
            return .warning
        }
        return .bad
    }

    /// Rates an event count.
    ///
    /// - Parameters:
    ///   - count: Number of events.
    ///   - bad: Whether any event is serious rather than a warning.
    /// - Returns: Good for zero, otherwise warning or bad.
    func countTone(_ count: UInt64, bad: Bool = false) -> Tone {
        guard count > 0 else {
            return .good
        }
        if bad {
            return .bad
        }
        return .warning
    }

    /// Rates a value against its target.
    ///
    /// - Parameters:
    ///   - value: The measured value.
    ///   - target: The expected value.
    /// - Returns: Good at 92 percent or more, warning at 75 percent or more, bad otherwise.
    func ratioTone(_ value: Double, target: Double) -> Tone {
        let ratio = value / target
        if ratio >= 0.92 {
            return .good
        }
        if ratio >= 0.75 {
            return .warning
        }
        return .bad
    }

    /// The latest statistics the report describes.
    var stats: RenderStatistics {
        telemetry.statistics
    }

    /// Formats a counter compactly, in thousands or millions once it grows large.
    ///
    /// - Parameter value: The counter.
    /// - Returns: The formatted counter.
    func counter(_ value: Int) -> LocalizedStringResource {
        if value >= 10_000_000 {
            return .verbatim("\(oneDecimal(Double(value) / 1_000_000))M")
        }
        if value >= 10000 {
            return .verbatim("\(oneDecimal(Double(value) / 1000))k")
        }
        return .verbatim(String(value))
    }

    /// Formats a resolution.
    ///
    /// - Parameters:
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    /// - Returns: The width and height separated by a multiplication sign.
    func resolution(_ width: Int, _ height: Int) -> LocalizedStringResource {
        .verbatim("\(width) × \(height)")
    }

    /// Formats a percentage with one decimal place.
    ///
    /// - Parameter value: The percentage.
    func percent(_ value: Double) -> String {
        "\(oneDecimal(value))%"
    }

    /// Formats a number with one decimal place.
    ///
    /// - Parameter value: The number.
    func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Formats milliseconds, dropping the decimal from 10 upwards.
    ///
    /// - Parameter value: Milliseconds.
    /// - Returns: The number without a unit.
    func millisecondsNumber(_ value: Double) -> String {
        if (value * 10).rounded() >= 100 {
            return String(Int(value.rounded()))
        }
        return oneDecimal(value)
    }

    /// Formats milliseconds with the unit.
    ///
    /// - Parameter value: Milliseconds.
    /// - Returns: The number followed by ms.
    func millisecondsValue(_ value: Double) -> LocalizedStringResource {
        .playbackDiagnosticsMilliseconds(value: millisecondsNumber(value))
    }
}
