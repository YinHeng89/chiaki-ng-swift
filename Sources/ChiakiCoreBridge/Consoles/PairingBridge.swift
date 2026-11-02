import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// Pairs consoles through the open core.
///
/// A pairing blocks a core thread for seconds, so it runs on a dispatch queue while the calling task waits;
/// cancelling the task cancels the core request. Progress reports are delivered on the core's thread as they
/// happen. The request, and with it the PIN, is wiped when the attempt ends.
public struct PairingBridge: Sendable {
    private final class Attempt: @unchecked Sendable {
        let request: PairingRequest
        let progress: @Sendable (PairingProgress) -> Void

        init(request: consuming PairingRequest, progress: @escaping @Sendable (PairingProgress) -> Void) {
            self.request = request
            self.progress = progress
        }
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// Pairs one console and saves the pairing through the console store.
    ///
    /// - Parameters:
    ///   - request: The validated request. It is consumed, and its PIN wiped, when the attempt ends.
    ///   - progress: Receives each step the core reports, on the core's thread.
    /// - Returns: The console that was paired.
    /// - Throws: The `ChiakiModels/PairingFailure` that ended the attempt, `ChiakiModels/PairingFailure/cancelled`
    ///   when the task was cancelled.
    public func pair(
        _ request: consuming PairingRequest,
        progress: @escaping @Sendable (PairingProgress) -> Void
    ) async throws(PairingFailure) -> PairedConsole {
        let attempt = Attempt(request: request, progress: progress)
        let result = await CoreCancellation.run { handle in
            Self.run(attempt, handle: handle)
        }
        return try result.get()
    }

    private static func run(_ attempt: Attempt,
                            handle: chiaki_bridge.Request) -> Result<PairedConsole, PairingFailure> {
        let context = Unmanaged.passUnretained(attempt).toOpaque()
        let watcher: chiaki_bridge.PairingProgressWatcher = { report, context in
            guard let report, let context else {
                return
            }
            let attempt = Unmanaged<Attempt>.fromOpaque(context).takeUnretainedValue()
            attempt.progress(PairingBridge.progress(of: report.pointee))
        }
        let account = chiaki_bridge.Bytes(attempt.request.account.bytes)
        let outcome = withExtendedLifetime(attempt) {
            switch attempt.request.target {
            case .atHome(let address, let kind):
                return pin(of: attempt) { pin in
                    chiaki_bridge.PairingBridge.pair_at_home(
                        handle, account, std.string(address),
                        ConsoleFactsReader.generation(of: kind), pin, watcher, context
                    )
                }
            case .overInternet(let console):
                return chiaki_bridge.PairingBridge.pair_over_internet(
                    handle, account, chiaki_bridge.Bytes(console.deviceUID.bytes),
                    std.string(console.name), ConsoleFactsReader.generation(of: console.kind), watcher,
                    context
                )
            }
        }
        return result(of: outcome, overInternet: !attempt.request.target.needsPIN)
    }

    private static func pin(
        of attempt: Attempt,
        _ body: (UnsafePointer<CChar>?) -> chiaki_bridge.PairingOutcome
    ) -> chiaki_bridge.PairingOutcome {
        switch attempt.request.pin {
        case .some(let pin):
            pin.withUnsafeCString { body($0) }
        case .none:
            body(nil)
        }
    }

    /// The model result of a core pairing outcome.
    ///
    /// - Parameters:
    ///   - outcome: What the core returned.
    ///   - overInternet: Whether the attempt paired over the internet, whose failures carry their stage.
    /// - Returns: The paired console or the failure.
    static func result(
        of outcome: chiaki_bridge.PairingOutcome,
        overInternet: Bool
    ) -> Result<PairedConsole, PairingFailure> {
        switch outcome.kind() {
        case .paired:
            guard let console = ConsoleFactsReader.paired(outcome.console()) else {
                return .failure(.rejected)
            }
            return .success(console)
        case .refused:
            return .failure(failure(of: outcome.refusal()))
        case .failed:
            let failed = outcome.failure()
            let code = failed.ps_reason.value.map(Int.init) ?? failed.http_status.value.map(Int.init)
            let stage = failed.internet_stage.value.map(stage(of:)) ?? .starting
            return .failure(failure(of: failed.reason, overInternet: overInternet, stage: stage, code: code))
        }
    }

    /// The model failure of a refusal the bridge made before the core ran.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The failure the app shows for it.
    static func failure(of refusal: chiaki_bridge.PairingRefusal) -> PairingFailure {
        switch refusal {
        case .core_closed:
            .unavailable
        case .unknown_user, .invalid_address, .invalid_pin:
            .invalidInput
        case .unknown_console:
            .rejected
        }
    }

    /// The model failure of a core pairing failure.
    ///
    /// - Parameters:
    ///   - reason: The core's reason.
    ///   - overInternet: Whether the attempt paired over the internet.
    ///   - stage: How far internet pairing had got.
    ///   - code: The console's reason code or HTTP status, when it gave one.
    /// - Returns: The failure the app shows for it.
    static func failure(
        of reason: libchiaking.consoles.PairingFailure.Reason,
        overInternet: Bool,
        stage: InternetPairingStage,
        code: Int?
    ) -> PairingFailure {
        switch reason {
        case .cancelled:
            return .cancelled
        case .address_not_for_generation:
            return .invalidInput
        case .not_saved:
            return .notSaved
        case .session_playing:
            return .sessionPlaying
        case .not_available, .internet_pairing_missing:
            return .unavailable
        case .unreachable, .timed_out, .refused, .unreadable_reply, .malformed, .busy, .remote_play_disabled,
             .unanswered, .needs_online_id:
            break
        }
        if overInternet {
            return .overInternet(stage, code: code)
        }
        switch reason {
        case .unreachable, .timed_out:
            return .unreachable
        default:
            return .rejected
        }
    }

    /// The model stage of a core internet pairing stage.
    ///
    /// - Parameter stage: The core's stage.
    /// - Returns: The model stage.
    static func stage(of stage: libchiaking.consoles.InternetPairingStage) -> InternetPairingStage {
        switch stage {
        case .starting:
            .starting
        case .opening_session:
            .openingSession
        case .waking_console:
            .wakingConsole
        case .connecting:
            .connecting
        case .pairing:
            .pairing
        }
    }

    /// The model progress of a core progress report.
    ///
    /// - Parameter report: The core's report.
    /// - Returns: The model report.
    static func progress(of report: libchiaking.consoles.PairingProgress) -> PairingProgress {
        PairingProgress(
            step: step(of: report.step),
            attempt: Int(report.attempt),
            elapsed: .microseconds(report.elapsed.count()),
            wait: report.wait.value.map {
                ProgressWait(
                    reason: waitReason(of: $0.reason),
                    nextTry: $0.next_try_in.value.map { .milliseconds($0.count()) }
                )
            }
        )
    }

    /// The model step of a core pairing step.
    ///
    /// - Parameter step: The core's step.
    /// - Returns: The model step.
    static func step(of step: libchiaking.consoles.PairingStep) -> PairingStep {
        switch step {
        case .starting:
            .starting
        case .opening_account_session:
            .openingAccountSession
        case .waking_console:
            .wakingConsole
        case .reaching_console:
            .reachingConsole
        case .sending_request:
            .sendingRequest
        case .waiting_for_answer:
            .waitingForAnswer
        case .saving:
            .saving
        }
    }

    /// The model wait reason of a core wait reason.
    ///
    /// - Parameter reason: The core's reason.
    /// - Returns: The model reason.
    static func waitReason(of reason: libchiaking.progress.WaitReason) -> ProgressWaitReason {
        switch reason {
        case .previous_session_closing:
            .previousSessionClosing
        case .server_queue:
            .serverQueue
        case .data_migration:
            .dataMigration
        case .datacenter_choice:
            .datacenterChoice
        case .title_not_ready:
            .titleNotReady
        case .network_unreachable:
            .networkUnreachable
        case .console_waking:
            .consoleWaking
        case .console_joining:
            .consoleJoining
        case .console_answering:
            .consoleAnswering
        case .connection_retry:
            .connectionRetry
        case .recent_cloud_session:
            .recentCloudSession
        }
    }
}
