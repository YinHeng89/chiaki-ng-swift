import Foundation

/// Rolling record of the most recent telemetry intervals, used to draw diagnostics graphs and to total recent
/// counters.
public struct StreamDiagnosticsHistory: Equatable {
    /// Creates a stream diagnostics history.
    public init() {
    }

    /// Problem that can be flagged on an interval and marked on the diagnostics graphs.
    public enum Event: CaseIterable, Equatable {
        /// Video frames were lost on the network.
        case networkLoss
        /// The audio buffer ran dry.
        case audioUnderrun
        /// GPU time reached the frame budget.
        case renderOverBudget
        /// The decoder reported a failure.
        case decodeError
    }

    /// Values captured from one telemetry interval for graphing.
    public struct Frame: Equatable {
        /// Received bitrate in megabits per second.
        public let bitrateMbps: Double
        /// Smoothed round-trip time in milliseconds.
        public let rttMilliseconds: Double
        /// Packet loss percentage.
        public let packetLossPercent: Double
        /// Frames per second arriving from the console.
        public let decodedFPS: Double
        /// Missed display refreshes per second.
        public let missRate: Double
        /// GPU time per frame in milliseconds.
        public let gpuMilliseconds: Double
        /// Counter increases recorded in this interval.
        public let interval: StreamTelemetry.Interval
        /// Problems detected in this interval.
        public let events: Set<Event>

        /// Frames lost in this interval, as a graphable value.
        public var framesLost: Double {
            Double(interval.framesLost)
        }

        /// Captures graph values and detected problems from telemetry.
        ///
        /// - Parameter telemetry: The interval to capture.
        public init(_ telemetry: StreamTelemetry) {
            bitrateMbps = telemetry.bitrateMbps
            rttMilliseconds = telemetry.statistics.rttSmoothedMicroseconds / 1000
            packetLossPercent = telemetry.packetLossPercent
            decodedFPS = telemetry.sourceFPS
            missRate = telemetry.interval.seconds > 0
                ? Double(telemetry.interval.refreshMisses) / telemetry.interval.seconds
                : 0
            gpuMilliseconds = telemetry.statistics.gpuMilliseconds
            interval = telemetry.interval
            var events = Set<Event>()
            if telemetry.interval.framesLost > 0 {
                events.insert(.networkLoss)
            }
            if telemetry.interval.audioUnderruns > 0 {
                events.insert(.audioUnderrun)
            }
            if telemetry.interval.decodeErrors > 0 {
                events.insert(.decodeError)
            }
            if telemetry.renderOverBudget, telemetry.statistics.gpuMilliseconds > 0 {
                events.insert(.renderOverBudget)
            }
            self.events = events
        }
    }

    /// Maximum number of intervals kept; older ones are discarded.
    public static let capacity = 120
    /// Number of most recent intervals that recent totals and rates cover.
    public static let window = 20

    /// Retained intervals, oldest first.
    public private(set) var frames = [Frame]()

    /// Appends an interval, dropping the oldest once the history is full.
    ///
    /// Telemetry without an elapsed interval, such as the first sample, is ignored.
    ///
    /// - Parameter telemetry: The interval to record.
    public mutating func append(_ telemetry: StreamTelemetry) {
        guard telemetry.interval.seconds > 0 else {
            return
        }
        frames.append(Frame(telemetry))
        if frames.count > Self.capacity {
            frames.removeFirst(frames.count - Self.capacity)
        }
    }

    /// Discards every recorded interval.
    public mutating func reset() {
        frames.removeAll()
    }

    /// Extracts one value from every retained interval, oldest first.
    ///
    /// - Parameter value: The frame value to extract.
    /// - Returns: The values in recording order.
    public func series(_ value: KeyPath<Frame, Double>) -> [Double] {
        frames.map { $0[keyPath: value] }
    }

    /// Totals a counter over the most recent window of intervals.
    ///
    /// - Parameter value: The interval counter to total.
    /// - Returns: The sum across the window.
    public func recent(_ value: KeyPath<StreamTelemetry.Interval, UInt64>) -> UInt64 {
        frames.suffix(Self.window).reduce(0) { $0 + $1.interval[keyPath: value] }
    }

    /// Averages a counter per second over the most recent window of intervals.
    ///
    /// - Parameter value: The interval counter to average.
    /// - Returns: Events per second, or zero when the window covers no time.
    public func recentRate(_ value: KeyPath<StreamTelemetry.Interval, UInt64>) -> Double {
        let window = frames.suffix(Self.window)
        let seconds = window.reduce(0) { $0 + $1.interval.seconds }
        guard seconds > 0 else {
            return 0
        }
        return Double(window.reduce(0) { $0 + $1.interval[keyPath: value] }) / seconds
    }

    /// Finds where an event occurred, as graph positions aligned so the newest interval sits at the right
    /// edge of a full-capacity graph.
    ///
    /// - Parameter event: The problem to locate.
    /// - Returns: Positions from zero to one less than `capacity`.
    public func marks(_ event: Event) -> [Int] {
        let offset = Self.capacity - frames.count
        return frames.indices.filter { frames[$0].events.contains(event) }.map { $0 + offset }
    }
}
