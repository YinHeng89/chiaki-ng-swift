import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Reads how the core says a stream ended into `StreamEndReport`.
///
/// Every core enum is switched over exhaustively, so a case the core adds fails to compile here instead of
/// being mapped silently.
public enum StreamOutcomeReader {
    /// The report of a finished stream.
    ///
    /// - Parameter outcome: What the core reported.
    /// - Returns: The model report.
    public static func report(of outcome: chiaki_bridge.StreamOutcome) -> StreamEndReport {
        StreamEndReport(
            outcome: Self.outcome(of: outcome),
            launchRefused: outcome.launch_refused().value.map(launchRefused(of:))
        )
    }

    /// How the stream ended.
    ///
    /// - Parameter outcome: What the core reported.
    /// - Returns: The model outcome; `StreamOutcome.unrecorded` when the core recorded no ending.
    public static func outcome(of outcome: chiaki_bridge.StreamOutcome) -> StreamOutcome {
        switch outcome.kind() {
        case .ended:
            return ended(outcome.ending())
        case .start_refused:
            let refused = outcome.start_refusal()
            return .startRefused(startRefusal(of: refused.kind, unreachable: refused.unreachable.value))
        case .refused:
            return .startRefused(startRefusal(of: outcome.refusal()))
        case .unrecorded:
            return .unrecorded
        }
    }

    /// How a stream that started ended.
    ///
    /// - Parameter end: What the core reported.
    /// - Returns: The model outcome.
    static func ended(_ end: chiaki_bridge.StreamEndFacts) -> StreamOutcome {
        let cause = end.cause.value.map(Self.cause(of:))
        switch end.ending {
        case .finished:
            return .finished
        case .left:
            return .left
        case .not_started:
            return .notStarted(cause)
        case .start_failed:
            return .startFailed(cause)
        case .session_failed:
            return .sessionFailed(cause)
        case .shutdown_failed:
            return .shutdownFailed(cause)
        case .media_failed:
            return .mediaFailed(end.media_failure.value.map(mediaFailure(of:)))
        case .console_quit:
            return .consoleQuit(end.quit.value.map(quitReason(of:)))
        }
    }

    /// The model refusal of a core start refusal.
    ///
    /// - Parameters:
    ///   - kind: The core's refusal.
    ///   - unreachable: Why the console could not be reached, for a console the core could not reach.
    /// - Returns: The model refusal.
    public static func startRefusal(
        of kind: libchiaking.play.StartRefusal.Kind,
        unreachable: libchiaking.consoles.Unreachable? = nil
    ) -> StreamOutcome.StartRefusal {
        switch kind {
        case .busy:
            .busy
        case .not_paired:
            .notPaired
        case .console_unreachable:
            unreachable == .network
                ? .networkUnreachable
                : .consoleUnreachable
        case .remote_play_disabled:
            .remotePlayDisabled
        case .sign_in_expired:
            .signInExpired
        case .needs_psn_sign_in:
            .needsPSNSignIn
        case .invalid_preferences:
            .invalidPreferences
        case .launch_refused:
            .launchRefused
        case .host_refused:
            .hostRefused
        case .cancelled:
            .cancelled
        }
    }

    /// The model refusal of a refusal the bridge made before the core was asked.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The model refusal.
    public static func startRefusal(of refusal: chiaki_bridge.StreamRefusal) -> StreamOutcome.StartRefusal {
        switch refusal {
        case .core_closed:
            .coreClosed
        case .unknown_user:
            .unknownUser
        case .unknown_console:
            .unknownConsole
        case .invalid_title:
            .invalidTitle
        case .no_decoder:
            .noDecoder
        }
    }

    /// The model cause of a core end cause.
    ///
    /// - Parameter value: The core's cause.
    /// - Returns: The model cause.
    public static func cause(of value: libchiaking.play.EndReason.Cause) -> StreamOutcome.Cause {
        switch value {
        case .invalid_state:
            .invalidState
        case .invalid_preferences:
            .invalidPreferences
        case .provider_unavailable:
            .providerUnavailable
        case .control_failed:
            .controlFailed
        case .route_failed:
            .routeFailed
        case .pipeline_failed:
            .pipelineFailed
        case .controller_rejected:
            .controllerRejected
        case .login_pin_rejected:
            .loginPINRejected
        case .shutdown_failed:
            .shutdownFailed
        case .control_network_failure:
            .controlNetworkFailure
        case .control_timeout:
            .controlTimeout
        case .control_truncated:
            .controlTruncated
        case .control_invalid_response:
            .controlInvalidResponse
        case .control_too_large:
            .controlTooLarge
        case .control_refused:
            .controlRefused
        case .control_handoff_failure:
            .controlHandoffFailure
        case .invalid_argument:
            .invalidArgument
        case .session_request_connection_refused:
            .sessionRequestConnectionRefused
        case .control_connection_refused:
            .controlConnectionRefused
        case .resource_exhausted:
            .resourceExhausted
        case .pairing_rejected:
            .pairingRejected
        case .unpaired_console:
            .unpairedConsole
        case .connection_lost:
            .connectionLost
        case .session_request_truncated, .session_request_network_failure, .session_request_timeout,
             .session_request_invalid_response, .session_request_too_large, .session_request_refused,
             .session_request_version_mismatch, .session_request_in_use:
            requestCause(value)
        }
    }

    private static func requestCause(_ value: libchiaking.play.EndReason.Cause) -> StreamOutcome.Cause {
        switch value {
        case .session_request_truncated:
            .sessionRequestTruncated
        case .session_request_network_failure:
            .sessionRequestNetworkFailure
        case .session_request_timeout:
            .sessionRequestTimeout
        case .session_request_invalid_response:
            .sessionRequestInvalidResponse
        case .session_request_too_large:
            .sessionRequestTooLarge
        case .session_request_refused:
            .sessionRequestRefused
        case .session_request_version_mismatch:
            .sessionRequestVersionMismatch
        case .session_request_in_use:
            .sessionRequestInUse
        case .invalid_state, .invalid_preferences, .provider_unavailable, .control_failed, .route_failed,
             .pipeline_failed, .controller_rejected, .login_pin_rejected, .shutdown_failed,
             .control_network_failure, .control_timeout, .control_truncated, .control_invalid_response,
             .control_too_large, .control_refused, .control_handoff_failure, .invalid_argument,
             .session_request_connection_refused, .control_connection_refused, .resource_exhausted,
             .pairing_rejected, .unpaired_console, .connection_lost:
            .invalidState
        }
    }

    /// The model reason of a core console quit reason.
    ///
    /// - Parameter value: The core's reason.
    /// - Returns: The model reason.
    public static func quitReason(of value: libchiaking.play.ConsoleQuit.Reason) -> StreamOutcome.QuitReason {
        switch value {
        case .stopped:
            .stopped
        case .session_request_unknown:
            .sessionRequestUnknown
        case .session_request_connection_refused:
            .sessionRequestConnectionRefused
        case .console_in_use:
            .consoleInUse
        case .remote_play_crashed:
            .remotePlayCrashed
        case .remote_play_version_mismatch:
            .remotePlayVersionMismatch
        case .control_unknown:
            .controlUnknown
        case .control_connect_failed:
            .controlConnectFailed
        case .control_connection_refused:
            .controlConnectionRefused
        case .stream_unknown:
            .streamUnknown
        case .console_disconnected:
            .consoleDisconnected
        case .console_shut_down:
            .consoleShutDown
        case .time_limit_reached:
            .timeLimitReached
        case .trial_ended:
            .trialEnded
        case .internet_pairing_failed:
            .internetPairingFailed
        }
    }

    /// The model failure of a core media failure.
    ///
    /// - Parameter value: The core's failure.
    /// - Returns: The model failure.
    public static func mediaFailure(of value: libchiaking.media.MediaFailure) -> StreamOutcome.MediaFailure {
        switch value {
        case .profile_validation:
            .profileValidation
        case .frame_validation:
            .frameValidation
        case .decoder_submission:
            .decoderSubmission
        case .recovery_request:
            .recoveryRequest
        case .decoder_output:
            .decoderOutput
        case .audio_output:
            .audioOutput
        }
    }

    /// The model refusal of a cloud launch PlayStation refused.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The model refusal.
    public static func launchRefused(of facts: chiaki_bridge.LaunchRefusalFacts) -> CloudLaunchRefused {
        switch facts.kind {
        case .not_cleared:
            .notCleared(clearance(of: facts))
        case .privacy_settings:
            .privacySettings
        case .licence_not_free:
            .licenceNotFree(price: String(facts.display_price))
        case .membership_rejected:
            .membershipRejected
        case .title_not_found:
            .titleNotFound
        case .refused_by_service:
            .refusedByStreamService
        case .no_reachable_datacenter:
            .noReachableDatacenter
        case .datacenter_unavailable:
            .datacenterUnavailable(String(facts.datacenter))
        case .no_server:
            .noServer
        case .sign_in_expired:
            .signInExpired
        case .unavailable:
            .unavailable
        case .outside_streaming_plan:
            .outsideStreamingPlan
        case .store_region:
            .storeRegion
        }
    }

    private static func clearance(of facts: chiaki_bridge.LaunchRefusalFacts) -> CloudClearanceRefusal {
        guard let cleared = facts.clearance.value else {
            return CloudClearanceRefusal(refusal: .checkUnavailable, price: String(facts.display_price))
        }
        return CloudClearanceRefusal(
            refusal: TitleChecksBridge.refusal(of: cleared.kind),
            notice: String(cleared.notice),
            time: cleared.time_ms.value.map(Timestamp.date(milliseconds:)),
            needsSignIn: cleared.needs_sign_in,
            price: String(facts.display_price)
        )
    }
}

/// Reads why the console refused a couch seat into `CouchFailure`.
public enum SeatRefusalReader {
    /// The pad the refusal is about.
    ///
    /// - Parameter refusal: What the core reported.
    /// - Returns: The pad, or `nil` when the refusal names no seat.
    public static func pad(of refusal: libchiaking.play.SeatRefusal) -> UInt8? {
        refusal.seat().value.map { $0.index() }
    }

    /// The failure a seat refusal stands for.
    ///
    /// - Parameter refusal: What the core reported.
    /// - Returns: The failure, or `nil` when the refusal is not a join failure.
    public static func failure(of refusal: libchiaking.play.SeatRefusal) -> CouchFailure? {
        switch refusal.kind() {
        case .not_sent:
            .notSent(refusal.cause().value.map(StreamOutcomeReader.cause(of:)))
        case .refused_by_console:
            .refused(refusal.console_status().value.map { Int($0) } ?? -1)
        case .passcode_attempts_used:
            .passcodeAttempts
        case .timed_out:
            .timedOut
        case .account_not_on_console:
            .accountUnresolvable
        case .no_free_seat:
            nil
        }
    }
}
