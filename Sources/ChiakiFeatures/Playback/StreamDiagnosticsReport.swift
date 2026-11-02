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
        let label: String
        /// Formatted value.
        let value: String
        /// Health rating used to colour the value.
        let tone: Tone

        /// Creates a row.
        ///
        /// - Parameters:
        ///   - label: Name of the measurement.
        ///   - value: Formatted value.
        ///   - tone: Health rating, neutral by default.
        init(_ label: String, _ value: String, _ tone: Tone = .neutral) {
            self.label = label
            self.value = value
            self.tone = tone
        }
    }

    /// Step of the streaming pipeline that a diagnostics stage summarises, with its display title as the raw
    /// value.
    enum StageKind: String, CaseIterable {
        /// Packets arriving from the console.
        case network = "Network"
        /// Packets assembled into frames.
        case assembly = "Assembly"
        /// Frames decoded into images.
        case decode = "Decode"
        /// Frames rendered on the GPU.
        case render = "Render"
        /// Frames presented to the display.
        case display = "Display"
    }

    /// Summary of one pipeline step: a headline figure, its graph history and supporting rows.
    struct Stage: Equatable, Identifiable {
        /// Pipeline step this stage summarises.
        let kind: StageKind
        /// Main figure shown for the stage.
        let headline: String
        /// Unit text shown after the headline.
        let unit: String
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
        let title: String
        /// Supporting measurements shown under the headline.
        let rows: [Row]

        /// Identifies the section by its title.
        var id: String {
            title
        }
    }

    /// Header badge made of text segments laid out side by side, with a health rating.
    struct Chip: Equatable {
        /// Text pieces shown in order within the chip.
        let segments: [String]
        /// Health rating used to colour the chip.
        var tone = Tone.neutral

        /// Creates a chip.
        ///
        /// - Parameters:
        ///   - segments: Text pieces shown in order.
        ///   - tone: Health rating, neutral by default.
        init(_ segments: [String], tone: Tone = .neutral) {
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
            chips.append(Chip(["Takion v\(stats.takionVersion)"]))
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
        var segments = [String]()
        switch route {
        case .psCloud:
            segments = ["PS Cloud"] + datacenterSegments
        case .psNow:
            segments = ["PS Now"] + datacenterSegments
        case .local:
            segments = consoleSegments + ["LAN"]
        case .internet:
            segments = consoleSegments + ["Internet"]
        default:
            segments = datacenterSegments
        }
        guard !segments.isEmpty else {
            return nil
        }
        return Chip(segments)
    }

    /// Console model for a local or internet route, or empty when unknown.
    var consoleSegments: [String] {
        switch RouteConsole(rawValue: stats.routeConsole) ?? .unknown {
        case .ps4:
            return ["PS4"]
        case .ps5:
            return ["PS5"]
        default:
            return []
        }
    }

    /// Datacenter name, followed by its measured latency when the datacenter was chosen automatically or at
    /// launch.
    var datacenterSegments: [String] {
        guard let datacenter else {
            return []
        }
        guard let rttMs = datacenter.rttMs, datacenter.automatic || datacenter.atLaunch else {
            return [datacenter.name]
        }
        return [datacenter.name, "\(rttMs) ms"]
    }

    /// Requested codec with its bit depth once the source resolution is known.
    var codecDescription: String {
        guard stats.sourceWidth > 0 else {
            return requestedCodec
        }
        if stats.tenBit {
            return "\(requestedCodec) 10-bit"
        }
        return "\(requestedCodec) 8-bit"
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
    var requestedFormat: String? {
        let height = stats.requestedHeight
        guard height > 0 else {
            return nil
        }
        let fps = stats.requestedFPS
        var format = "\(height)p"
        if fps > 0 {
            format += "\(fps)"
        }
        let presentation = stats.presentationFrameRate
        if presentation > 0, presentation != fps {
            format += " to \(presentation) Hz"
        }
        return format
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
        var text = "Granted \(height)p\(fps)"
        if granted > 0 {
            text += requested > 0 && abs(granted - requested) >= 0.05
                ? ", \(oneDecimal(granted)) of \(oneDecimal(requested)) Mbps"
                : ", \(oneDecimal(granted)) Mbps"
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
    var upscaler: String? {
        if stats.advancedSpatial {
            return "FSRCNNX"
        }
        if stats.spatialUpscaling {
            return "MetalFX"
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
                stage.kind.rawValue,
                "\(stage.kind.rawValue) \(row.label.lowercased()) \(row.value)",
                worst
            )
        }
        guard stage.kind != .network else {
            return nil
        }
        return Row(stage.kind.rawValue, "\(stage.kind.rawValue) \(stage.headline) \(stage.unit)", worst)
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
            rows.append(Row("RTT", rttValue))
            if stats.rttSamples > 0 {
                let spikes = stats.rttRecentMaxMicroseconds > 0
                    ? millisecondsValue(stats.rttRecentMaxMicroseconds / 1000)
                    : Self.unavailable
                rows.append(Row("RTT spikes", spikes))
                rows.append(Row("RTT p99", millisecondsValue(stats.rttP99Microseconds / 1000)))
            }
        } else {
            rows.append(Row("RTT", Self.unavailable))
        }
        rows.append(Row("Loss", percent(packetLossPercent), lossTone(packetLossPercent)))
        return Stage(
            kind: .network,
            headline: oneDecimal(telemetry.bitrateMbps),
            unit: "Mbps",
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
            unit: "lost in 10 s",
            tone: tone,
            series: history.series(\.framesLost),
            rows: [
                Row("Keyframes asked", String(requests), countTone(requests)),
                Row("Keyframe waits", String(waits), countTone(waits))
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
            unit: "fps",
            tone: tone,
            series: history.series(\.decodedFPS),
            rows: [
                Row("Errors", String(errors), countTone(errors, bad: true)),
                Row("Time", Self.unavailable)
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
            unit: "ms GPU",
            tone: gpuTone,
            series: history.series(\.gpuMilliseconds),
            rows: [
                Row("Budget", millisecondsValue(telemetry.frameBudgetMilliseconds)),
                Row("Upscaler", upscalerState, upscalerTone)
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
            unit: "Hz",
            tone: .neutral,
            series: history.series(\.missRate),
            rows: [
                Row("Missed", "\(oneDecimal(misses))/s"),
                Row("Idle ticks", "\(oneDecimal(history.recentRate(\.idleTicks)))/s"),
                Row("Replaced", "\(oneDecimal(history.recentRate(\.replacedFrames)))/s")
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
    var upscalerState: String {
        guard let upscaler else {
            return "Off"
        }
        if stats.advancedBudgetFallback {
            return "Over budget"
        }
        return upscaler
    }
}

extension StreamDiagnosticsReport {
    /// One-line audio description with channel layout, sample rate and buffer depth, or a waiting message
    /// before audio arrives.
    var audioSummary: String {
        let channels = stats.audioReceivedChannels
        guard channels > 0 else {
            return "Waiting for audio"
        }
        let rate = Double(stats.audioReceivedSampleRate) / 1000
        let kilohertz = rate == rate.rounded()
            ? String(Int(rate))
            : oneDecimal(rate)
        return "\(channelLayout(channels)) at \(kilohertz) kHz, \(audioBuffer)"
    }

    /// Row counting recent audio underruns, or reporting audio unavailable when the output device failed.
    var audioUnderrunsSummary: Row {
        let underruns = history.recent(\.audioUnderruns)
        if stats.audioDeviceFailures > 0 {
            return Row("Audio", "Unavailable", .bad)
        }
        let label = underruns == 1
            ? "underrun"
            : "underruns"
        return Row("Audio", "\(underruns) \(label)", countTone(underruns))
    }

    /// Names a channel layout.
    ///
    /// - Parameter channels: Number of audio channels.
    /// - Returns: Mono, Stereo, 5.1, 7.1 or a channel count.
    func channelLayout(_ channels: Int) -> String {
        switch channels {
        case 1:
            "Mono"
        case 2:
            "Stereo"
        case 6:
            "5.1"
        case 8:
            "7.1"
        default:
            "\(channels) channels"
        }
    }

    /// Audio playback state: unavailable, waiting, priming or playing.
    var audioStatus: String {
        if stats.audioDeviceFailures > 0 {
            return "Unavailable"
        }
        switch stats.audioState {
        case 2:
            return "Priming"
        case 3:
            return "Playing"
        default:
            return "Waiting"
        }
    }

    /// Channel count received from the console, noting how many are active when fewer than all.
    var receivedAudioChannels: String {
        let description = audioChannels(stats.audioReceivedChannels)
        let active = stats.audioReceivedActiveChannels
        guard active > 0, active < stats.audioReceivedChannels else {
            return description
        }
        return "\(description), \(active) active"
    }

    /// Channel count fed into audio playback.
    var playbackAudioChannels: String {
        audioChannels(stats.audioChannels)
    }

    /// Sample rate received from the console in hertz, or waiting before audio arrives.
    var receivedAudioRate: String {
        guard stats.audioReceivedChannels > 0 else {
            return "Waiting"
        }
        return "\(stats.audioReceivedSampleRate) Hz"
    }

    /// Buffered audio in milliseconds.
    var audioBuffer: String {
        let sampleRate = max(1, stats.audioSampleRate)
        let milliseconds = Double(stats.audioBufferedFrames) / Double(sampleRate) * 1000
        return "\(Int(milliseconds.rounded())) ms"
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
    func audioChannels(_ count: Int) -> String {
        guard count > 0 else {
            return "Waiting"
        }
        let label = count == 1
            ? "channel"
            : "channels"
        return "\(count) \(label)"
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
                "On wire",
                "\(oneDecimal(stats.videoThroughputBPS / 1_000_000)) Mbps"
            ))
            rows.append(Row(
                "Frame transfer",
                millisecondsValue(stats.videoTransferTimeMicroseconds / 1000)
            ))
        }
        if stats.extensionPresent {
            rows.append(Row(
                "Jitter",
                millisecondsValue(stats.extensionJitterMicroseconds / 1000)
            ))
            rows.append(Row("Packets received", counter(stats.corePacketsReceived)))
            rows.append(Row("Packets lost", counter(stats.extensionLost)))
        }
        rows.append(Row("Rejected", counter(stats.coreRejectedPackets)))
        rows.append(Row("Crypto rejects", counter(stats.coreCryptoRejections)))
        rows.append(Row("Reordered", counter(stats.coreReorderSkipped)))
        rows.append(Row("Reorder drops", counter(stats.coreReorderDropped)))
        let internalDrops = stats.coreDroppedPosts + stats.coreSendDropped
        rows.append(Row("Internal drops", String(internalDrops), countTone(UInt64(max(0, internalDrops)))))
        if stats.coreLoopErrors > 0 {
            rows.append(Row("Session errors", counter(stats.coreLoopErrors), .bad))
        }
        if stats.tosPresent, stats.tosLastPresent {
            rows.append(Row("Marking", marking))
        }
        return Section(title: "Network", rows: rows)
    }

    /// Frames section with cumulative receive, loss, reference patch, FEC repair, keyframe, assembly and decode
    /// counters.
    var framesSection: Section {
        Section(title: "Frames", rows: [
            Row("Received", counter(stats.received)),
            Row("Lost", counter(stats.lost)),
            Row("Patched references", counter(stats.recovered)),
            Row("Repaired by FEC", counter(stats.coreFecRepaired)),
            Row("Keyframe requests", counter(stats.keyframeRequests)),
            Row("Keyframe waits", counter(stats.coreDependencyRejections)),
            Row("Unassembled", counter(stats.coreAssemblyRejections)),
            Row("Duplicates", counter(stats.coreVideoDuplicate)),
            Row("Stale", counter(stats.coreVideoStale)),
            Row(
                "Decode errors",
                counter(stats.decoderFailures),
                countTone(UInt64(stats.decoderFailures), bad: true)
            )
        ])
    }

    /// Presentation section with resolutions, refresh and frame rates, presentation counters, EDR headroom
    /// and zero-copy state.
    var presentationSection: Section {
        var rows = [
            Row("Source", resolution(stats.sourceWidth, stats.sourceHeight)),
            Row("Canvas", resolution(stats.outputWidth, stats.outputHeight)),
            Row("Display", "\(stats.displayMaximumFPS) Hz"),
            Row("Rendered", "\(oneDecimal(telemetry.presentedFPS)) fps"),
            Row("Submitted", counter(stats.submitted)),
            Row("Missed refresh", counter(stats.deadlineMisses)),
            Row("No drawable", counter(stats.noDrawable)),
            Row("Replaced frames", counter(stats.replacedFrames)),
            Row("Idle ticks", counter(stats.idleTicks)),
            Row("EDR headroom", headroomValue, edrTone),
            Row("Zero copy", zeroCopyLabel, zeroCopyTone)
        ]
        if telemetry.generatedFPS > 0 {
            rows.insert(Row("Generated", "\(oneDecimal(telemetry.generatedFPS)) fps"), at: 3)
            rows.append(Row("Generated drops", counter(stats.generatedDrops)))
        }
        if stats.gpuError != 0 {
            rows.append(Row("GPU error", String(stats.gpuError), .bad))
        }
        return Section(title: "Presentation", rows: rows)
    }

    /// Audio section with playback state, channels, rate, buffer and audio counters.
    var audioSection: Section {
        Section(title: "Audio", rows: [
            Row("State", audioStatus, audioTone),
            Row("Received", receivedAudioChannels),
            Row("Playback input", playbackAudioChannels),
            Row("Source rate", receivedAudioRate),
            Row("Buffer", audioBuffer),
            Row("Underruns", counter(stats.audioUnderruns), audioTone),
            Row("Overflows", counter(stats.audioOverflows), audioTone),
            Row("Dropped", counter(stats.audioDroppedFrames), audioTone),
            Row("Concealed", counter(stats.audioConcealmentFrames))
        ])
    }

    /// Row showing the received bitrate, against the target when one is known.
    var bitrateRow: Row {
        let target = targetBitrateMbps
        guard target > 0 else {
            return Row("Bitrate", "\(oneDecimal(telemetry.bitrateMbps)) Mbps")
        }
        return Row("Bitrate", "\(oneDecimal(telemetry.bitrateMbps)) of \(oneDecimal(target)) Mbps")
    }

    /// Last observed DSCP class of the stream's packets, followed by its ECN codepoint when one was set.
    var marking: String {
        let dscp = dscpName(stats.tosLastDSCP)
        guard let ecn = ecnMarking(stats.tosLastECN) else {
            return dscp
        }
        return "\(dscp) \(ecn)"
    }

    /// Frames rejected for reasons other than a missing drawable, counted as zero-copy failures.
    var zeroCopyFailures: Int {
        max(0, stats.rejected - stats.noDrawable)
    }

    /// Zero-copy state: active, or the number of rejected frames.
    var zeroCopyLabel: String {
        if zeroCopyFailures == 0 {
            return "Active"
        }
        return "\(zeroCopyFailures) rejected"
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
    func dscpName(_ value: Int) -> String {
        switch value {
        case 0:
            return "Best effort"
        case 8, 16, 24, 32, 40, 48, 56:
            return "CS\(value / 8)"
        case 10, 12, 14, 18, 20, 22, 26, 28, 30, 34, 36, 38:
            return "AF\(value / 8)\((value % 8) / 2)"
        case 46:
            return "Expedited"
        default:
            return "DSCP \(value)"
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
    var hdrShortLabel: String {
        if hdrOutputActive, !sendsSDRBrightness {
            return "EDR"
        }
        if stats.perceptualQuantizer {
            return "PQ"
        }
        return "SDR"
    }

    /// Sentence explaining the HDR pipeline state, including why HDR is inactive or how the content peak is
    /// tone mapped.
    var hdrLongLabel: String {
        if !stats.perceptualQuantizer {
            if stats.requestedHDR {
                return requestedHDRSentSDR
            }
            return "SDR transfer detected, HDR not requested"
        }
        if !stats.layerHDR {
            return "PQ input with EDR inactive"
        }
        if stats.displayPotentialEDR > 0, stats.displayPotentialEDR <= 1 {
            return "PQ input, but this screen cannot show HDR"
        }
        if stats.displayMaximumEDR <= 1 {
            return "PQ input, but macOS is not giving this screen HDR headroom right now"
        }
        if sendsSDRBrightness {
            return sdrBrightnessLabel
        }
        guard stats.toneMapSource > 0, stats.contentPeakNits > 0 else {
            return "PQ input with EDR active"
        }
        let peak = Int(stats.contentPeakNits.rounded())
        let source = stats.toneMapSource == 1
            ? "the stream's"
            : "a default"
        guard compressesHighlights else {
            return "PQ input with EDR active, \(source) \(peak) nit peak fits the screen"
        }
        return "PQ input with EDR active, compressing highlights above the screen for \(source) \(peak) nit peak"
    }

    /// Whether the content peak exceeds the usable EDR headroom, so highlights are compressed.
    var compressesHighlights: Bool {
        stats.contentPeakNits / Self.referenceWhiteNits
            > stats.displayMaximumEDR * Self.headroomTarget
    }

    /// Bit depth and colour gamut of the video.
    var colourDescription: String {
        var depth = "8-bit"
        if stats.tenBit {
            depth = "10-bit"
        }
        return "\(depth)  \(gamutDescription)"
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
    var rttValue: String {
        let smoothed = stats.rttSmoothedMicroseconds / 1000
        let variation = stats.rttVariationMicroseconds / 1000
        guard variation >= 1 else {
            return millisecondsValue(smoothed)
        }
        return "\(millisecondsNumber(smoothed)) ± \(millisecondsNumber(variation)) ms"
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
    func counter(_ value: Int) -> String {
        if value >= 10_000_000 {
            return "\(oneDecimal(Double(value) / 1_000_000))M"
        }
        if value >= 10000 {
            return "\(oneDecimal(Double(value) / 1000))k"
        }
        return String(value)
    }

    /// Formats a resolution.
    ///
    /// - Parameters:
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    /// - Returns: The width and height separated by a multiplication sign.
    func resolution(_ width: Int, _ height: Int) -> String {
        "\(width) × \(height)"
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
    func millisecondsValue(_ value: Double) -> String {
        "\(millisecondsNumber(value)) ms"
    }
}
