/// How a stream ended, with the core's recorded reason when there was one.
///
/// The raw values of the nested reasons are the stable names written to logs. Mapping from the native codes
/// lives beside the bridge, not here.
public enum StreamOutcome: Equatable, Sendable {
    /// Why the core refused to start a stream.
    public enum StartRefusal: String, CaseIterable, Sendable {
        /// Another stream is still running.
        case busy

        /// The console is not paired with the account.
        case notPaired = "not_paired"

        /// The console could not be reached.
        case consoleUnreachable = "console_unreachable"

        /// The console could not be reached because the network failed: the search could not be sent, or PSN did
        /// not answer the request for the account's consoles.
        case networkUnreachable = "network_unreachable"

        /// Remote Play is turned off on the console.
        case remotePlayDisabled = "remote_play_disabled"

        /// The account's sign-in expired.
        case signInExpired = "sign_in_expired"

        /// The stream needs a PSN sign-in the account lacks.
        case needsPSNSignIn = "needs_psn_sign_in"

        /// The stream preferences were rejected.
        case invalidPreferences = "invalid_preferences"

        /// The service refused to launch the title.
        case launchRefused = "launch_refused"

        /// The device could not start the stream's session thread.
        case hostRefused = "host_refused"

        /// The core does not know the account.
        case unknownUser = "unknown_user"

        /// The core does not know the console.
        case unknownConsole = "unknown_console"

        /// The title is not valid for the service.
        case invalidTitle = "invalid_title"

        /// The core is closed.
        case coreClosed = "core_closed"

        /// No video decoder is available.
        case noDecoder = "no_decoder"

        /// The start was cancelled.
        case cancelled
    }

    /// The core's cause for a failed start, session or shutdown.
    public enum Cause: String, CaseIterable, Sendable {
        /// The session was in the wrong state.
        case invalidState = "invalid_state"

        /// The stream preferences were rejected.
        case invalidPreferences = "invalid_preferences"

        /// The stream provider was unavailable.
        case providerUnavailable = "provider_unavailable"

        /// The control connection failed.
        case controlFailed = "control_failed"

        /// The network route failed.
        case routeFailed = "route_failed"

        /// The media pipeline failed.
        case pipelineFailed = "pipeline_failed"

        /// The console rejected the controller.
        case controllerRejected = "controller_rejected"

        /// The console rejected the login PIN.
        case loginPINRejected = "login_pin_rejected"

        /// The session did not shut down cleanly.
        case shutdownFailed = "shutdown_failed"

        /// The control connection lost the network.
        case controlNetworkFailure = "control_network_failure"

        /// The control connection timed out.
        case controlTimeout = "control_timeout"

        /// A control message was truncated.
        case controlTruncated = "control_truncated"

        /// A control response was malformed.
        case controlInvalidResponse = "control_invalid_response"

        /// A control message was too large.
        case controlTooLarge = "control_too_large"

        /// The console refused the control request.
        case controlRefused = "control_refused"

        /// Handing the control connection over failed.
        case controlHandoffFailure = "control_handoff_failure"

        /// The session request was truncated.
        case sessionRequestTruncated = "session_request_truncated"

        /// The session request lost the network.
        case sessionRequestNetworkFailure = "session_request_network_failure"

        /// The session request timed out.
        case sessionRequestTimeout = "session_request_timeout"

        /// The session response was malformed.
        case sessionRequestInvalidResponse = "session_request_invalid_response"

        /// The session request was too large.
        case sessionRequestTooLarge = "session_request_too_large"

        /// The console refused the session request.
        case sessionRequestRefused = "session_request_refused"

        /// The console runs a different Remote Play version.
        case sessionRequestVersionMismatch = "session_request_version_mismatch"

        /// Remote Play is already in use on the console.
        case sessionRequestInUse = "session_request_in_use"

        /// An argument was invalid.
        case invalidArgument = "invalid_argument"

        /// The console refused the session connection.
        case sessionRequestConnectionRefused = "session_request_connection_refused"

        /// The console refused the control connection.
        case controlConnectionRefused = "control_connection_refused"

        /// A system resource ran out.
        case resourceExhausted = "resource_exhausted"

        /// The console rejected the pairing.
        case pairingRejected = "pairing_rejected"

        /// Over the internet, PSN reached the account's primary PS4, which this app has not paired with.
        case unpairedConsole = "unpaired_console"

        /// The console or cloud server stopped sending anything for longer than the silence limit.
        case connectionLost = "connection_lost"
    }

    /// Why the console ended a running stream.
    public enum QuitReason: String, CaseIterable, Sendable {
        /// The console stopped the stream normally.
        case stopped

        /// The session request failed for an unknown reason.
        case sessionRequestUnknown = "session_request_unknown"

        /// The console refused the session connection.
        case sessionRequestConnectionRefused = "session_request_connection_refused"

        /// Remote Play is already in use.
        case consoleInUse = "console_in_use"

        /// Remote Play crashed on the console.
        case remotePlayCrashed = "remote_play_crashed"

        /// The Remote Play versions do not match.
        case remotePlayVersionMismatch = "remote_play_version_mismatch"

        /// The control connection failed for an unknown reason.
        case controlUnknown = "control_unknown"

        /// The control connection could not be opened.
        case controlConnectFailed = "control_connect_failed"

        /// The console refused the control connection.
        case controlConnectionRefused = "control_connection_refused"

        /// The stream connection failed for an unknown reason.
        case streamUnknown = "stream_unknown"

        /// The console disconnected the stream.
        case consoleDisconnected = "console_disconnected"

        /// The console shut down.
        case consoleShutDown = "console_shut_down"

        /// The cloud server closed the stream because the streaming time limit, such as a trial's play time,
        /// was reached.
        case timeLimitReached = "time_limit_reached"

        /// The cloud server ended a game trial whose play time ran out, after warning that it was running out.
        case trialEnded = "trial_ended"

        /// Pairing over the internet failed.
        case internetPairingFailed = "internet_pairing_failed"

        /// Whether the server ended the stream because its play time ran out, so trying again cannot help.
        public var endsPlayTime: Bool {
            self == .timeLimitReached || self == .trialEnded
        }
    }

    /// Which stage of media handling failed.
    public enum MediaFailure: String, CaseIterable, Sendable {
        /// The stream's media profile was invalid.
        case profileValidation = "profile_validation"

        /// A frame was invalid.
        case frameValidation = "frame_validation"

        /// The decoder refused a frame.
        case decoderSubmission = "decoder_submission"

        /// A recovery request failed.
        case recoveryRequest = "recovery_request"

        /// The decoder's output failed.
        case decoderOutput = "decoder_output"

        /// Audio output failed.
        case audioOutput = "audio_output"
    }

    /// The stream ended normally.
    case finished

    /// The user left the stream.
    case left

    /// The core recorded no ending.
    case unrecorded

    /// The core refused to start.
    case startRefused(StartRefusal)

    /// The stream never started.
    case notStarted(Cause?)

    /// Starting failed.
    case startFailed(Cause?)

    /// The running session failed.
    case sessionFailed(Cause?)

    /// Shutting down failed.
    case shutdownFailed(Cause?)

    /// Media handling failed.
    case mediaFailed(MediaFailure?)

    /// The console ended the stream.
    case consoleQuit(QuitReason?)

    /// Whether the stream ended for any reason other than finishing or the user leaving.
    public var failed: Bool {
        self != .finished && self != .left
    }

    /// The core's cause, for the endings that carry one.
    public var cause: Cause? {
        switch self {
        case .notStarted(let cause), .startFailed(let cause), .sessionFailed(let cause),
             .shutdownFailed(let cause):
            cause
        case .finished, .left, .unrecorded, .startRefused, .mediaFailed, .consoleQuit:
            nil
        }
    }

    /// The stable dotted name written to logs, such as `session_failed.control_timeout`.
    public var name: String {
        switch self {
        case .finished:
            "finished"
        case .left:
            "left"
        case .unrecorded:
            "unrecorded"
        case .startRefused(let refusal):
            "start_refused.\(refusal.rawValue)"
        case .notStarted(let cause):
            Self.name("not_started", cause?.rawValue)
        case .startFailed(let cause):
            Self.name("start_failed", cause?.rawValue)
        case .sessionFailed(let cause):
            Self.name("session_failed", cause?.rawValue)
        case .shutdownFailed(let cause):
            Self.name("shutdown_failed", cause?.rawValue)
        case .mediaFailed(let failure):
            Self.name("media_failed", failure?.rawValue)
        case .consoleQuit(let reason):
            Self.name("console_quit", reason?.rawValue)
        }
    }

    private static func name(_ ending: String, _ detail: String?) -> String {
        detail.map { "\(ending).\($0)" } ?? ending
    }
}
