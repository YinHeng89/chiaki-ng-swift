import ChiakiModels
import Dependencies
import ChiakiDiagnostics
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

/// Describes a console stream attempt for diagnostic log lines: its route, the console and where it was
/// reached.
public struct PlaybackAttemptLog: Equatable, Sendable {
    /// Whether the attempt goes over the local network rather than through PSN.
    let local: Bool
    /// The console description, with its model, name and MAC address.
    let console: String
    /// The console's network address, or a placeholder when it is unknown.
    let address: String
    /// A shortened PSN device identifier when the attempt goes over the internet.
    let remoteDevice: String?

    private var routeName: String {
        local
            ? "Local"
            : "Remote"
    }

    /// Returns where the attempt was aimed: the PSN device when remote, otherwise the address, with the port
    /// from the diagnostics when known.
    func target(_ diagnostics: StreamFailureDiagnostics?) -> String {
        if let remoteDevice {
            return "\(console) via PSN device \(remoteDevice)"
        }
        guard let port = diagnostics?.localPort else {
            return "\(console) at \(address)"
        }
        return "\(console) at \(address):\(port)"
    }

    /// Returns the core's failure message flattened to one line, or the player-facing message for the outcome
    /// when the core gave none.
    func cause(of outcome: StreamOutcome, message: String?) -> String {
        let text = message?.replacingOccurrences(of: "\n", with: "; ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            let fallback = PlaybackFailureMessage.text(for: .stream(outcome, overInternet: !local))
            return fallback.english
        }
        return text
    }

    /// A failed attempt's outcome with the core's message and raw diagnostics.
    public struct Report: Equatable {
        /// How the stream ended.
        let outcome: StreamOutcome
        /// The core's failure message, if any.
        let message: String?
        /// The core's raw failure diagnostics, if any.
        let diagnostics: String?

        /// Describes a failed attempt.
        ///
        /// - Parameters:
        ///   - outcome: How the stream ended.
        ///   - message: The core's failure message, if any.
        ///   - diagnostics: The core's raw failure diagnostics, if any.
        public init(outcome: StreamOutcome, message: String?, diagnostics: String?) {
            self.outcome = outcome
            self.message = message
            self.diagnostics = diagnostics
        }
    }

    /// Formats the error log line for a failed attempt with its route, target, elapsed time, stage, cause and
    /// raw diagnostics.
    func failure(report: Report, milliseconds: Int) -> String {
        let diagnostics = StreamFailureDiagnostics(report.diagnostics)
        let stage = diagnostics?.stageName.map {
            " during \($0)"
        } ?? ""
        let quit = diagnostics?.quitName.map {
            " (\($0))"
        } ?? ""
        let raw = ["ending \(report.outcome.name)", diagnostics?.raw].compactMap { $0 }
            .joined(separator: "; ")
        let cause = cause(of: report.outcome, message: report.message)
        return "\(routeName) start to \(target(diagnostics)) failed after \(milliseconds) ms"
            + "\(stage): \(cause)\(quit) [\(raw)]"
    }
}

/// Writes a console stream attempt's route and failure to the diagnostic log.
public struct PlaybackAttempts {
    /// The attempt's description used to format the log lines.
    let log: PlaybackAttemptLog
    /// The route logged for the attempt: the local or the remote core.
    let route: PlaybackLogRoute
    /// The diagnostic log the attempt's lines are written to.
    let logger: LoggerClient

    /// Describes an attempt to stream the target locally or over the internet.
    ///
    /// - Parameters:
    ///   - target: The console the attempt streams from.
    ///   - overInternet: Whether the attempt goes over the internet rather than the local network.
    ///   - logger: The diagnostic log the attempt's lines are written to.
    public init(target: PlayTarget, overInternet: Bool, logger: LoggerClient) {
        self.logger = logger
        route = overInternet
            ? .remoteCore
            : .localCore
        let kind = target.ps5
            ? "PS5"
            : "PS4"
        log = PlaybackAttemptLog(
            local: !overInternet,
            console: "\(kind) \"\(target.name)\" MAC " + LogFormat.mac(target.hardwareID.data),
            address: target.address ?? "an unknown address",
            remoteDevice: overInternet
                ? target.remoteDeviceID.map { LogFormat.hexPrefix($0) }
                : nil
        )
    }

    /// Logs which route the attempt takes and where it is aimed.
    public func logRoute() async {
        await logger.log(.diagnostic(
            .playback, .info,
            "\(route.rawValue) for \(log.target(nil))"
        ))
    }

    /// Logs the attempt's failure as an error line.
    public func failed(_ report: PlaybackAttemptLog.Report, milliseconds: Int) async {
        await logger.log(.diagnostic(
            .playback, .error, log.failure(report: report, milliseconds: milliseconds)
        ))
    }
}

/// A summary of how a cloud stream ended, formatted as one log line.
public struct CloudSessionEnd {
    /// The streamed game's title.
    let title: String
    /// How the stream session ended.
    let outcome: StreamOutcome
    /// Whether the player stopped the stream, which keeps a failing outcome from being logged as a failure.
    let cancelled: Bool
    /// How long the stream ran, in seconds.
    let seconds: Double
    /// The number of video frames decoded.
    let decoded: Int
    /// The number of GPU errors the renderer reported.
    let gpuErrors: Int
    /// The failure text the core reported, preferred over the generic outcome message when present.
    let failureMessage: String?
    /// The core's raw failure diagnostics, parsed for the stage, quit reason and service errors.
    let diagnostics: String?

    /// Summarises how a cloud stream ended.
    ///
    /// - Parameters:
    ///   - title: The streamed game's title.
    ///   - outcome: How the stream session ended.
    ///   - cancelled: Whether the player stopped the stream.
    ///   - seconds: How long the stream ran, in seconds.
    ///   - decoded: The number of video frames decoded.
    ///   - gpuErrors: The number of GPU errors the renderer reported.
    ///   - failureMessage: The failure text the core reported, if any.
    ///   - diagnostics: The core's raw failure diagnostics, if any.
    public init(
        title: String,
        outcome: StreamOutcome,
        cancelled: Bool,
        seconds: Double,
        decoded: Int,
        gpuErrors: Int,
        failureMessage: String?,
        diagnostics: String?
    ) {
        self.title = title
        self.outcome = outcome
        self.cancelled = cancelled
        self.seconds = seconds
        self.decoded = decoded
        self.gpuErrors = gpuErrors
        self.failureMessage = failureMessage
        self.diagnostics = diagnostics
    }

    /// Whether the stream failed rather than ending normally or being stopped by the player.
    var failed: Bool {
        outcome.failed && !cancelled
    }

    /// The level to log at: error for a failure, info otherwise.
    public var level: LogLevel {
        failed
            ? .error
            : .info
    }

    /// The log line naming the title, duration and frame counts, plus the stage, cause and raw diagnostics
    /// when the stream failed.
    public var message: String {
        let duration = String(format: "%.1f s", seconds)
        let frames = "\(decoded) frames decoded, \(gpuErrors) GPU errors"
        guard failed else {
            let how = outcome == .finished && !cancelled
                ? "ended normally"
                : "was stopped by the user"
            return "Cloud stream of \"\(title)\" \(how) after \(duration): \(frames)"
        }
        let parsed = StreamFailureDiagnostics(diagnostics)
        let stage = parsed?.stageName.map {
            " during \($0)"
        } ?? ""
        let cause = failureMessage?.replacingOccurrences(of: "\n", with: "; ")
            ?? CloudPlaybackFailureMessage.text(for: .stream(outcome)).english
        let quit = parsed?.quitName.map {
            " (\($0))"
        } ?? ""
        let service = parsed?.text("error_message").map {
            "; service error \($0)"
        } ?? ""
        let console = parsed?.text("console_reason").map {
            "; server reason \"\($0)\""
        } ?? ""
        let raw = ["ending \(outcome.name)", parsed?.raw].compactMap { $0 }.joined(separator: "; ")
        return "Cloud stream of \"\(title)\" failed after \(duration)\(stage): \(cause)\(quit)\(service)\(console); "
            + "\(frames) [\(raw)]"
    }
}

/// Tracks cloud video counters between samples to tell whether losses or rejections are growing.
public struct CloudHealth {
    private var previous: [KeyPath<RenderStatistics, Int>: Int] = [:]

    /// Creates a tracker that has seen no samples.
    public init() {
    }
    private static var problems: [KeyPath<RenderStatistics, Int>] {
        [
            \.lost, \.decoderFailures, \.rejected, \.gpuError, \.coreRejectedPackets, \.coreCryptoRejections,
            \.coreDependencyRejections, \.coreAssemblyRejections
        ]
    }

    /// Describes the cloud video's health since the last sample.
    ///
    /// - Parameters:
    ///   - stats: The player's statistics now.
    ///   - decoded: Frames the player decoded.
    /// - Returns: The log level, raised when losses or rejections grew, and the message.
    public mutating func sample(_ stats: RenderStatistics,
                                decoded: Int) -> (level: LogLevel, message: String) {
        let worse = Self.problems.contains {
            stats[keyPath: $0] > previous[$0, default: 0]
        }
        for key in Self.problems {
            previous[key] = stats[keyPath: key]
        }
        var message = "Cloud video health: received \(stats.received), lost \(stats.lost), patched references "
            + "\(stats.recovered), decoded \(decoded), GPU completed \(stats.completed), decoder failures "
            + "\(stats.decoderFailures), rejected \(stats.rejected), GPU errors \(stats.gpuError)"
        if stats.coreDiagnosticsAvailable {
            message += "; transport units \(stats.coreVideoUnits), packet rejections "
                + "\(stats.coreRejectedPackets), authentication rejections \(stats.coreCryptoRejections), "
                + "assembled \(stats.coreAssembledVideo), dependency rejections "
                + "\(stats.coreDependencyRejections), assembly rejections \(stats.coreAssemblyRejections) "
                + "(stale \(stats.coreVideoStale), metadata \(stats.coreVideoMetadata), duplicate "
                + "\(stats.coreVideoDuplicate), invalid \(stats.coreVideoInvalid)), repaired by FEC "
                + "\(stats.coreFecRepaired)"
        }
        return (
            worse
                ? .info
                : .debug,
            message + (worse
                ? "; losses or rejections grew in the last 10 s"
                : "")
        )
    }
}
