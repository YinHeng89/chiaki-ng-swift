import ChiakiModels
import Dependencies
import ChiakiDiagnostics
import Video
import Foundation

/// Forwards diagnostic lines from the streaming core to the logger, optionally holding them until the first
/// video frame so a failed attempt's log stays together.
@MainActor final class CoreDiagnosticRelay {
    /// When core diagnostics are written to the log.
    enum Mode {
        /// `live` logs each line immediately; `untilFirstFrame` buffers up to 4000 lines until the attempt
        /// succeeds or ends.
        case live, untilFirstFrame
    }
    private var buffering: Bool
    private var held: [(severity: Int, message: String)] = []
    /// Creates a relay in the given mode.
    /// - Parameter mode: Whether to log immediately or buffer until the first frame.
    init(_ mode: Mode) {
        buffering = mode == .untilFirstFrame
    }
    /// Formats a core diagnostic line and logs it, or buffers it while waiting for the first frame.
    /// - Parameters:
    ///   - severity: The core's severity level for the line.
    ///   - message: The raw diagnostic text.
    func record(severity: Int, message: String) async {
        let line = CoreDiagnosticLine.format(message)
        guard buffering else {
            @Dependency(\.logger) var logger
            await logger.log(.coreDiagnostic(severity: severity, message: line))
            return
        }
        held.append((severity, line))
        if held.count > 4000 {
            held.removeFirst(held.count - 4000)
        }
    }
    /// Stops buffering and logs every held line once the attempt shows its first frame.
    func attemptSucceeded() async {
        guard buffering else {
            return
        }
        buffering = false
        let lines = held
        held = []
        for line in lines {
            @Dependency(\.logger) var logger
            await logger.log(.coreDiagnostic(severity: line.severity, message: line.message))
        }
    }
    /// Logs and clears any lines still held when the attempt finishes, whether it succeeded or failed.
    func attemptEnded() async {
        let lines = held
        held = []
        for line in lines {
            @Dependency(\.logger) var logger
            await logger.log(.coreDiagnostic(severity: line.severity, message: line.message))
        }
    }
}

/// Wraps a stream attempt with core diagnostic capture, applying log and developer Takion settings to the
/// player and draining its API captures and diagnostic lines every 50 ms until the attempt finishes.
@MainActor enum NativeStreamDiagnostics {
    /// Configures diagnostics on the player, runs the operation while polling the core's logs, then drains
    /// and flushes them.
    /// - Parameters:
    ///   - player: The player whose core diagnostics are collected.
    ///   - relay: Where core diagnostic lines are sent.
    ///   - operation: The stream attempt to run.
    /// - Returns: The operation's result.
    /// - Throws: Any error thrown by the operation, after diagnostics are flushed.
    static func run<Value>(
        player: CNLiveVideoPlayer,
        relay: CoreDiagnosticRelay = CoreDiagnosticRelay(.live),
        operation: @MainActor () async throws -> Value
    ) async rethrows -> Value {
        @Dependency(\.logSettings) var logSettings
        player.captureAPI = (try? await logSettings.load().captureAPI) ?? false
        @Dependency(\.settings) var settings
        let developer = (try? await settings.load(DeveloperSettings.self)) ?? DeveloperSettings()
        player.setTakionVersionsLocalPS4(
            developer.takionLocalPS4, localPS5: developer.takionLocalPS5, psNow: developer.takionPSNow,
            psCloud: developer.takionPSCloud
        )
        player.setTakionNegotiationLocalPS4(
            developer.negotiateLocalPS4, localPS5: developer.negotiateLocalPS5,
            psNow: developer.negotiatePSNow,
            psCloud: developer.negotiatePSCloud
        )
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                await drain(player, relay: relay)
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    break
                }
            }
        }
        do {
            let result = try await operation()
            monitor.cancel()
            await monitor.value
            await drain(player, relay: relay)
            await relay.attemptEnded()
            return result
        } catch {
            monitor.cancel()
            await monitor.value
            await drain(player, relay: relay)
            await relay.attemptEnded()
            throw error
        }
    }
    private static func drain(_ player: CNLiveVideoPlayer, relay: CoreDiagnosticRelay) async {
        @Dependency(\.logger) var logger
        for capture in player.takeAPICaptures() {
            await logger.capture(core: capture)
        }
        for record in player.takeDiagnosticLogs() {
            guard let severity = record["severity"] as? Int,
                  let message = record["message"] as? String else {
                continue
            }
            await relay.record(severity: severity, message: message)
        }
    }
}
