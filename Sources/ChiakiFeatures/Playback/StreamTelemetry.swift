import ChiakiClients
import ChiakiModels
import Foundation

/// The latest statistics together with the rates derived from the previous reading.
public struct StreamTelemetry: Equatable {
    /// Creates a stream telemetry.
    ///
    /// - Parameters:
    ///   - statistics: The latest statistics.
    ///   - sourceFPS: Decoded frames per second.
    ///   - presentedFPS: Rendered frames per second.
    ///   - generatedFPS: Generated frames per second.
    ///   - bitrateMbps: The video bitrate in Mbps.
    ///   - lossPercent: The share of frames lost, in percent.
    ///   - interval: What changed since the previous reading.
    public init(
        statistics: RenderStatistics = RenderStatistics(),
        sourceFPS: Double = 0,
        presentedFPS: Double = 0,
        generatedFPS: Double = 0,
        bitrateMbps: Double = 0,
        lossPercent: Double = 0,
        interval: Interval = Interval()
    ) {
        self.statistics = statistics
        self.sourceFPS = sourceFPS
        self.presentedFPS = presentedFPS
        self.generatedFPS = generatedFPS
        self.bitrateMbps = bitrateMbps
        self.lossPercent = lossPercent
        self.interval = interval
    }

    /// What changed between two readings.
    public struct Interval: Equatable {
        /// Frames lost.
        public var framesLost: UInt64 = 0
        /// Frames that waited for a keyframe.
        public var keyframeWaits: UInt64 = 0
        /// Keyframes requested.
        public var keyframeRequests: UInt64 = 0
        /// Frames the core could not assemble.
        public var assemblyRejections: UInt64 = 0
        /// Frames the decoder failed.
        public var decodeErrors: UInt64 = 0
        /// Presentation deadlines missed.
        public var refreshMisses: UInt64 = 0
        /// Frames replaced before presentation.
        public var replacedFrames: UInt64 = 0
        /// Refreshes with no new frame.
        public var idleTicks: UInt64 = 0
        /// Frames rejected for want of a drawable.
        public var noDrawable: UInt64 = 0
        /// Times audio ran out.
        public var audioUnderruns: UInt64 = 0
        /// Times audio overflowed.
        public var audioOverflows: UInt64 = 0

        /// Creates an interval.
        ///
        /// - Parameters:
        ///   - framesLost: Frames lost.
        ///   - keyframeWaits: Frames that waited for a keyframe.
        ///   - keyframeRequests: Keyframes requested.
        ///   - assemblyRejections: Frames the core could not assemble.
        ///   - decodeErrors: Frames the decoder failed.
        ///   - refreshMisses: Presentation deadlines missed.
        ///   - replacedFrames: Frames replaced before presentation.
        ///   - idleTicks: Refreshes with no new frame.
        ///   - noDrawable: Frames rejected for want of a drawable.
        ///   - audioUnderruns: Times audio ran out.
        ///   - audioOverflows: Times audio overflowed.
        ///   - seconds: The interval's length in seconds.
        public init(
            framesLost: UInt64 = 0,
            keyframeWaits: UInt64 = 0,
            keyframeRequests: UInt64 = 0,
            assemblyRejections: UInt64 = 0,
            decodeErrors: UInt64 = 0,
            refreshMisses: UInt64 = 0,
            replacedFrames: UInt64 = 0,
            idleTicks: UInt64 = 0,
            noDrawable: UInt64 = 0,
            audioUnderruns: UInt64 = 0,
            audioOverflows: UInt64 = 0,
            seconds: Double = 0
        ) {
            self.framesLost = framesLost
            self.keyframeWaits = keyframeWaits
            self.keyframeRequests = keyframeRequests
            self.assemblyRejections = assemblyRejections
            self.decodeErrors = decodeErrors
            self.refreshMisses = refreshMisses
            self.replacedFrames = replacedFrames
            self.idleTicks = idleTicks
            self.noDrawable = noDrawable
            self.audioUnderruns = audioUnderruns
            self.audioOverflows = audioOverflows
            self.seconds = seconds
        }

        /// The interval's length in seconds.
        public var seconds = 0.0
    }

    /// The latest statistics.
    public var statistics = RenderStatistics()
    /// Decoded frames per second.
    public var sourceFPS = 0.0
    /// Rendered frames per second.
    public var presentedFPS = 0.0
    /// Generated frames per second.
    public var generatedFPS = 0.0
    /// The video bitrate in Mbps.
    public var bitrateMbps = 0.0
    /// The share of frames lost, in percent.
    public var lossPercent = 0.0
    /// What changed since the previous reading.
    public var interval = Interval()

    /// The packet loss the console or core measured, falling back to the frame loss.
    public var packetLossPercent: Double {
        if statistics.extensionPresent {
            return statistics.extensionLossRatio * 100
        }
        if statistics.videoMetricsPresent {
            return statistics.videoLossRatio * 100
        }
        return lossPercent
    }

    /// The time one presented frame may take, in milliseconds.
    public var frameBudgetMilliseconds: Double {
        var rate = statistics.presentationFrameRate
        if rate <= 0 {
            rate = statistics.requestedFPS
        }
        return 1000 / Double(max(rate, 30))
    }

    /// Whether the GPU takes close to the whole frame budget.
    public var renderOverBudget: Bool {
        statistics.gpuMilliseconds >= frameBudgetMilliseconds * 0.9
    }
}

/// Turns successive readings into ``StreamTelemetry`` with per-second rates.
public struct StreamTelemetrySampler: Equatable {
    private var previous: StreamStatisticsSample?

    /// Derives telemetry from a new reading and the previous one.
    ///
    /// - Parameter sample: The new reading.
    /// - Returns: The telemetry; the first reading has no rates.
    public mutating func update(_ sample: StreamStatisticsSample) -> StreamTelemetry {
        let current = sample.statistics ?? RenderStatistics()
        guard let previous else {
            self.previous = sample
            return StreamTelemetry(statistics: current)
        }
        let seconds = max(sample.uptime - previous.uptime, 0.001)
        let delta = { (counter: KeyPath<RenderStatistics, Int>) in
            Self.delta(counter, from: previous.statistics, to: sample.statistics)
        }
        let sourceFrames = delta(\.surfaces)
        let lost = delta(\.lost)
        self.previous = sample
        /// Percentage of frames lost in the last interval, used when the stream reports no packet loss ratio.
        var lossPercent = 0.0
        if sourceFrames + lost > 0 {
            lossPercent = Double(lost) / Double(sourceFrames + lost) * 100
        }
        return StreamTelemetry(
            statistics: current,
            sourceFPS: Double(sourceFrames) / seconds,
            presentedFPS: Double(delta(\.completed)) / seconds,
            generatedFPS: Double(Self.delta(
                previous.statistics?.frameGenerationGenerated,
                to: sample.statistics?.frameGenerationGenerated
            )) / seconds,
            bitrateMbps: Double(delta(\.bytes)) * 8 / seconds / 1_000_000,
            lossPercent: lossPercent,
            interval: StreamTelemetry.Interval(
                framesLost: lost,
                keyframeWaits: delta(\.coreDependencyRejections),
                keyframeRequests: delta(\.keyframeRequests),
                assemblyRejections: delta(\.coreAssemblyRejections),
                decodeErrors: delta(\.decoderFailures),
                refreshMisses: delta(\.deadlineMisses),
                replacedFrames: delta(\.replacedFrames),
                idleTicks: delta(\.idleTicks),
                noDrawable: delta(\.noDrawable),
                audioUnderruns: delta(\.audioUnderruns),
                audioOverflows: delta(\.audioOverflows),
                seconds: seconds
            )
        )
    }

    private static func delta(
        _ counter: KeyPath<RenderStatistics, Int>,
        from old: RenderStatistics?,
        to current: RenderStatistics?
    ) -> UInt64 {
        guard let current else {
            return 0
        }
        return delta(old?[keyPath: counter], to: current[keyPath: counter])
    }

    private static func delta(_ old: Int?, to current: Int?) -> UInt64 {
        let value = current ?? 0
        let before = old ?? value
        guard value >= before else {
            return 0
        }
        return UInt64(value - before)
    }
}
