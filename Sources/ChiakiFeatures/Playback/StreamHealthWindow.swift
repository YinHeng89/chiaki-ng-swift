import ChiakiModels
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Accumulates main-thread stalls, rumble updates, controller input delay and audio counter growth over five
/// second windows for the stream health log.
public struct StreamHealthWindow {
    /// Log line produced at the end of a health window.
    public struct Report: Equatable {
        /// Level to log at, raised to info when audio or video problems or a main-thread stall occurred.
        public let level: LogLevel
        /// Summary of the window's stall, audio, rumble, input delay and controller figures.
        public let message: String

        /// Creates a report.
        ///
        /// - Parameters:
        ///   - level: Level to log at, raised to info when audio or video problems or a main-thread stall occurred.
        ///   - message: Summary of the window's stall, audio, rumble, input delay and controller figures.
        public init(level: LogLevel, message: String) {
            self.level = level
            self.message = message
        }
    }

    /// Length of a health window in seconds.
    public static let interval: TimeInterval = 5
    /// Gap between polls, in seconds, that counts as a main-thread stall.
    public static let stallThreshold: TimeInterval = 0.1
    private static var audioProblems: [KeyPath<RenderStatistics, Int>] {
        [\.audioUnderruns, \.audioOverflows, \.audioDroppedFrames, \.audioTrims, \.audioTrimmedFrames]
    }

    private static var audioCounters: [KeyPath<RenderStatistics, Int>] {
        audioProblems + [\.audioPushedFrames]
    }

    private static var videoProblems: [KeyPath<RenderStatistics, Int>] {
        [\.rejected, \.noDrawable, \.deadlineMisses, \.decoderFailures]
    }

    private static var counters: [KeyPath<RenderStatistics, Int>] {
        audioCounters + videoProblems + [
            \.coreAssembledVideo,
            \.submitted,
            \.completed,
            \.replacedFrames,
            \.idleTicks,
            \.deliverySlowVideo,
            \.deliverySlowAudio,
            \.deliveryGaps
        ]
    }

    private var windowStart: TimeInterval?
    private var lastPoll: TimeInterval?
    private var longestGap: TimeInterval = 0
    private var rumbleUpdates = 0
    private var inputBatches = 0
    private var inputDelayTotal: UInt64 = 0
    private var inputDelayWorst: UInt64 = 0
    private var previous: [KeyPath<RenderStatistics, Int>: Int] = [:]

    /// Creates a stream health window.
    public init() {
    }

    /// Records a poll at the given uptime and tracks the longest gap since the previous poll.
    ///
    /// - Parameter now: The current system uptime in seconds.
    /// - Returns: `true` when the current window has lasted at least `interval` and a report is due.
    public mutating func poll(at now: TimeInterval) -> Bool {
        if let lastPoll, now > lastPoll {
            longestGap = max(longestGap, now - lastPoll)
        }
        lastPoll = now
        guard let windowStart else {
            self.windowStart = now
            return false
        }
        return now - windowStart >= Self.interval
    }

    /// Forgets the last poll time so the gap while the application is inactive does not count as a stall.
    public mutating func pause() {
        lastPoll = nil
    }

    /// Counts one rumble update sent to the controller in the current window.
    public mutating func rumbleSent() {
        rumbleUpdates += 1
    }

    /// Records one input batch and the delay from SDL to the stream, ignoring delays of ten seconds or more.
    ///
    /// - Parameter delay: The delay in microseconds.
    public mutating func inputSent(delayMicroseconds delay: UInt64) {
        guard delay < 10_000_000 else {
            return
        }
        inputBatches += 1
        inputDelayTotal += delay
        inputDelayWorst = max(inputDelayWorst, delay)
    }

    private var inputDelaySummary: String {
        guard inputBatches > 0 else {
            return "no controller input sent"
        }
        let average = Double(inputDelayTotal) / Double(inputBatches) / 1000
        let worst = Double(inputDelayWorst) / 1000
        return String(
            format: "input reached the stream %.1f ms after SDL on average, %.1f ms at worst (%d batches)",
            average, worst, inputBatches
        )
    }

    /// Summarises the window and starts the next one.
    ///
    /// - Parameters:
    ///   - stats: The player's statistics now.
    ///   - controller: Describes player one's controller.
    ///   - now: The current system uptime.
    /// - Returns: The report, at info level when audio or video problems grew or the main thread stalled.
    public mutating func report(_ stats: RenderStatistics, controller: String,
                                at now: TimeInterval) -> Report {
        let growth = Dictionary(uniqueKeysWithValues: Self.counters.map { key in
            (key, max(0, stats[keyPath: key] - previous[key, default: stats[keyPath: key]]))
        })
        for key in Self.counters {
            previous[key] = stats[keyPath: key]
        }
        let active = stats.audioReceivedActiveChannels
        let activeChannelsNote = active > 0 && active < stats.audioReceivedChannels
            ? " (\(active) active)"
            : ""
        let gapMilliseconds = Int((longestGap * 1000).rounded())
        let audioGrew = Self.audioProblems.contains { growth[$0, default: 0] > 0 }
        let videoGrew = Self.videoProblems.contains { growth[$0, default: 0] > 0 }
        let stalled = longestGap >= Self.stallThreshold
        var message = "Stream health: longest main-thread gap \(gapMilliseconds) ms; audio underruns "
            + "+\(growth[\.audioUnderruns] ?? 0) (\(stats.audioUnderruns) total), overflows "
            + "+\(growth[\.audioOverflows] ?? 0), dropped frames +\(growth[\.audioDroppedFrames] ?? 0), "
            + "trims +\(growth[\.audioTrims] ?? 0) (\(growth[\.audioTrimmedFrames] ?? 0) frames), "
            + "pushed frames +\(growth[\.audioPushedFrames] ?? 0), "
            + "buffered \(stats.audioBufferedFrames) of at most \(stats.audioMaximumBufferedFrames) "
            + "frames; received audio \(stats.audioReceivedChannels) channels\(activeChannelsNote) at "
            + "\(stats.audioReceivedSampleRate) Hz; playback input \(stats.audioChannels) channels "
            + "at \(stats.audioSampleRate) Hz; video assembled +\(growth[\.coreAssembledVideo] ?? 0), "
            + "submitted +\(growth[\.submitted] ?? 0), completed +\(growth[\.completed] ?? 0), "
            + "replaced +\(growth[\.replacedFrames] ?? 0), rejected +\(growth[\.rejected] ?? 0), "
            + "no drawable +\(growth[\.noDrawable] ?? 0), deadline misses +\(growth[\.deadlineMisses] ?? 0), "
            + "idle refreshes +\(growth[\.idleTicks] ?? 0), decoder failures +\(growth[\.decoderFailures] ?? 0), "
            + "GPU \(String(format: "%.1f", stats.gpuMilliseconds)) ms at \(stats.presentationFrameRate) fps; "
            + "delivery slow video +\(growth[\.deliverySlowVideo] ?? 0), "
            + "slow audio +\(growth[\.deliverySlowAudio] ?? 0), gaps +\(growth[\.deliveryGaps] ?? 0), "
            + "longest video \(stats.deliveryLongestVideoMicroseconds / 1000) ms, "
            + "audio \(stats.deliveryLongestAudioMicroseconds / 1000) ms, "
            + "gap \(stats.deliveryLongestGapMicroseconds / 1000) ms; "
            + "rumble updates \(rumbleUpdates); \(inputDelaySummary); \(controller)"
        if audioGrew || videoGrew || stalled {
            message += "; audio or video problems or a main-thread stall in the last 5 s"
        }
        windowStart = now
        longestGap = 0
        rumbleUpdates = 0
        inputBatches = 0
        inputDelayTotal = 0
        inputDelayWorst = 0
        return Report(
            level: audioGrew || videoGrew || stalled
                ? .info
                : .debug,
            message: message
        )
    }
}
