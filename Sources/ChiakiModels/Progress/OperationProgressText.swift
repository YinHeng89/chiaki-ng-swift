import Foundation

/// The player-facing title and detail lines that describe an operation's progress.
public struct OperationProgressText: Equatable, Sendable {
    /// The headline: the current route step when routing, otherwise the operation's step.
    public let title: String
    /// Detail lines such as step position, queue position, waits, attempts and elapsed time, omitting any
    /// that do not apply.
    public let details: [String]

    /// Describes progress as of a report.
    ///
    /// - Parameters:
    ///   - progress: The latest progress report.
    ///   - sinceReport: Time since the report, added to elapsed time and subtracted from retry countdowns.
    public init(_ progress: OperationProgress, sinceReport: Duration = .zero) {
        let since = max(0, Int(sinceReport.components.seconds))
        title = progress.route.map(Self.label) ?? Self.label(progress.step)
        details = [
            progress.position.map { "Step \($0.number) of \($0.total)" },
            progress.measured.map { "Measured \($0.number) of \($0.total) datacenters" },
            progress.route?.candidates.map(Self.label),
            progress.route?.chosen.map(Self.label),
            progress.queuePosition.map { "Position \($0) in the queue" },
            progress.waitTimeEstimateSeconds.map(Self.waitEstimate),
            progress.migrationPercent.map { "\($0)% moved" },
            Self.bandwidth(progress),
            progress.wait.map { Self.label($0, since: since) },
            Self.attempt(progress),
            progress.previousFailure.flatMap(Self.label),
            progress.elapsedMilliseconds.map { "\($0 / 1000 + since) s elapsed" }
        ].compactMap { $0 }
    }

    /// The title followed by the details.
    public var lines: [String] {
        [title] + details
    }
}

extension OperationProgressText {
    /// Describes the stream service's estimate of the server queue wait in whole minutes.
    ///
    /// - Parameter seconds: The estimated wait in seconds.
    /// - Returns: "Estimated wait: under a minute" below a minute, otherwise the minutes rounded down.
    static func waitEstimate(_ seconds: Int) -> String {
        if seconds < 60 {
            return "Estimated wait: under a minute"
        }
        let minutes = seconds / 60
        let unit = minutes == 1
            ? "min"
            : "mins"
        return "Estimated wait: about \(minutes) \(unit)"
    }
}

extension OperationProgressText {
    /// Names the step an operation is on.
    ///
    /// - Parameter step: The launch, connect or pairing step.
    /// - Returns: The label.
    public static func label(_ step: OperationProgress.Step) -> String {
        switch step {
        case .launch(let activity):
            label(activity)
        case .connect(let step):
            label(step)
        case .pairing(let step):
            label(step)
        }
    }

    /// Names a cloud launch activity.
    ///
    /// - Parameter activity: The activity.
    /// - Returns: The label.
    public static func label(_ activity: OperationProgress.LaunchActivity) -> String {
        switch activity {
        case .clearingWithCatalog:
            "Checking the title with the catalog"
        case .checkingDevice:
            "Checking this device"
        case .openingTitleSession:
            "Opening the title session"
        case .resolvingTitle:
            "Finding the title"
        case .takingFreeLicence:
            "Taking the free licence"
        case .openingAccountSession:
            "Opening the account session"
        case .reservingServer:
            "Reserving a server"
        case .measuringDatacenters:
            "Measuring datacenters"
        case .waitingForDatacenterChoice:
            "Choosing a datacenter"
        case .allocatingServer:
            "Allocating a server"
        case .migratingData:
            "Moving your data"
        case .connectingToServer:
            "Connecting to the server"
        case .measuringBandwidth:
            "Measuring your connection"
        case .loadingLibrary:
            "Loading your library"
        case .checkingMembership:
            "Checking your membership"
        case .checkingCloudStreaming:
            "Checking PlayStation Plus Premium"
        case .checkingOwnership:
            "Checking ownership"
        case .checkingEntitlement:
            "Checking your copy of the game"
        case .resolvingCloudGame:
            "Finding the cloud game"
        case .checkingExclusions:
            "Checking PlayStation's restrictions"
        case .checkingRelease:
            "Checking the release date"
        }
    }

    /// Describes the bandwidth measurement, if one is reported.
    ///
    /// - Parameter progress: The progress report.
    /// - Returns: The description, or `nil`.
    static func bandwidth(_ progress: OperationProgress) -> String? {
        progress.bandwidth?.progressDescription
    }

    /// Names a console connection step.
    ///
    /// - Parameter step: The step.
    /// - Returns: The label.
    public static func label(_ step: OperationProgress.ConnectStep) -> String {
        switch step {
        case .findingConsole:
            "Finding the console"
        case .openingAccountSession:
            "Opening the account session"
        case .wakingConsole:
            "Waking the console"
        case .pairing:
            "Pairing with the console"
        case .reachingConsole:
            "Reaching the console"
        case .openingStreamRoute:
            "Opening the stream route"
        case .requestingSession:
            "Requesting the session"
        case .openingControl:
            "Opening the control connection"
        case .measuringConnection:
            "Measuring the connection"
        case .startingStream:
            "Starting the stream"
        }
    }

    /// Names a pairing step.
    ///
    /// - Parameter step: The step.
    /// - Returns: The label.
    public static func label(_ step: OperationProgress.PairingStep) -> String {
        switch step {
        case .starting:
            "Starting"
        case .openingAccountSession:
            "Opening the account session"
        case .wakingConsole:
            "Asking the console to join"
        case .reachingConsole:
            "Reaching the console"
        case .sendingRequest:
            "Sending the pairing request"
        case .waitingForAnswer:
            "Waiting for the console's answer"
        case .saving:
            "Saving the pairing"
        }
    }
}

extension OperationProgressText {
    /// Describes a route negotiation step, naming whether it is the control or stream route.
    ///
    /// - Parameter route: The route progress.
    /// - Returns: The label.
    public static func label(_ route: OperationProgress.Route) -> String {
        let name = label(route.purpose)
        switch route.step {
        case .openingAccountSession:
            return "Opening the account session"
        case .waitingForConsole:
            return "Waiting for the console to join"
        case .gatheringCandidates:
            return "Gathering addresses for the \(name) route"
        case .exchangingOffers:
            return "Exchanging offers for the \(name) route"
        case .testingCandidates:
            return "Testing the \(name) route"
        case .routeChosen:
            return "The \(name) route is chosen"
        case .confirmingRoute:
            return "Confirming the \(name) route"
        case .switchingControl:
            return "Switching control to the stream route"
        }
    }

    /// Names a route's purpose in lowercase, for use inside a sentence.
    ///
    /// - Parameter purpose: The purpose.
    /// - Returns: `control` or `stream`.
    public static func label(_ purpose: OperationProgress.RoutePurpose) -> String {
        switch purpose {
        case .control:
            "control"
        case .stream:
            "stream"
        }
    }

    /// Describes the kind of route that was chosen.
    ///
    /// - Parameter kind: The route kind.
    /// - Returns: The label.
    public static func label(_ kind: OperationProgress.RouteKind) -> String {
        switch kind {
        case .local:
            "Route over the local network"
        case .publicAddress:
            "Route over the public address"
        case .portGuessed:
            "Route over a guessed port"
        case .discovered:
            "Route over an address the console answered from"
        }
    }

    /// Summarises the address candidates gathered for a route, by kind.
    ///
    /// - Parameter candidates: The candidate counts.
    /// - Returns: The summary.
    public static func label(_ candidates: OperationProgress.Candidates) -> String {
        "\(candidates.total) addresses: \(candidates.local) local, \(candidates.publicAddress) public, "
            + "\(candidates.portGuessed) guessed"
    }
}

extension OperationProgressText {
    /// Describes what an operation is waiting for.
    ///
    /// - Parameter reason: The wait reason.
    /// - Returns: The label.
    public static func label(_ reason: OperationProgress.WaitReason) -> String {
        switch reason {
        case .previousSessionClosing:
            "Waiting for your previous session to close"
        case .serverQueue:
            "Waiting in the server queue"
        case .dataMigration:
            "Waiting for your data to move"
        case .datacenterChoice:
            "Waiting for a datacenter choice"
        case .titleNotReady:
            "The title is not ready yet"
        case .networkUnreachable:
            "The network is unreachable"
        case .consoleWaking:
            "Waiting for the console to wake"
        case .consoleJoining:
            "Waiting for the console to join"
        case .consoleAnswering:
            "Waiting for the console to answer"
        case .connectionRetry:
            "Waiting before the next attempt"
        case .recentCloudSession:
            "Waiting since last cloud stream"
        }
    }

    /// Describes a wait with a countdown to the next try.
    ///
    /// - Parameters:
    ///   - wait: The wait.
    ///   - since: Seconds since the report, subtracted from the countdown.
    /// - Returns: The reason, followed by when the next try happens when one is scheduled.
    public static func label(_ wait: OperationProgress.Wait, since: Int) -> String {
        let reason = label(wait.reason)
        guard let next = wait.nextTryMilliseconds, next > 0 else {
            return reason
        }
        let remaining = max(0, (next + 999) / 1000 - since)
        if wait.reason == .recentCloudSession {
            return settling(remaining)
        }
        return remaining == 0
            ? "\(reason), trying again now"
            : "\(reason), trying again in \(remaining) s"
    }

    /// Counts down the settling time after the account's last cloud stream.
    ///
    /// - Parameter seconds: Whole seconds left.
    /// - Returns: "Waiting 20 seconds since last cloud stream", in the singular for one second.
    static func settling(_ seconds: Int) -> String {
        let unit = seconds == 1
            ? "second"
            : "seconds"
        return "Waiting \(seconds) \(unit) since last cloud stream"
    }

    /// Describes the attempt: launches count tries while waiting, and connections and pairings show the
    /// attempt number after the first.
    ///
    /// - Parameter progress: The progress report.
    /// - Returns: The text, or `nil` when there is nothing to show.
    public static func attempt(_ progress: OperationProgress) -> String? {
        switch progress.step {
        case .launch:
            tries(progress)
        case .connect, .pairing:
            progress.attempt > 1
                ? "Attempt \(progress.attempt)"
                : nil
        }
    }

    /// Counts the tries made while an operation waits.
    ///
    /// - Parameter progress: The progress report.
    /// - Returns: The text, or `nil` when not waiting or nothing was tried yet.
    public static func tries(_ progress: OperationProgress) -> String? {
        guard progress.attempt > 0, progress.isWaiting else {
            return nil
        }
        return progress.attempt == 1
            ? "Tried once"
            : "Tried \(progress.attempt) times"
    }

    /// Describes why the previous attempt failed, preferring the console's quit reason.
    ///
    /// - Parameter failure: The previous failure.
    /// - Returns: The text, or `nil` when no reason is known.
    public static func label(_ failure: OperationProgress.Failure) -> String? {
        if let quit = failure.consoleQuit {
            return "The last attempt failed: \(label(quit))"
        }
        return failure.cause.map { "The last attempt failed: \(label($0))" }
    }
}

extension OperationProgressText {
    /// Describes why the console ended a session, in lowercase for use inside a sentence.
    ///
    /// - Parameter quit: The console's quit reason.
    /// - Returns: The description.
    public static func label(_ quit: OperationProgress.ConsoleQuit) -> String {
        switch quit {
        case .stopped:
            "the console stopped the session"
        case .sessionRequestUnknown:
            "the console refused the session request"
        case .sessionRequestConnectionRefused:
            "the console refused the session connection"
        case .consoleInUse:
            "the console is in use"
        case .remotePlayCrashed:
            "Remote Play crashed on the console"
        case .remotePlayVersionMismatch:
            "the console expects another Remote Play version"
        case .controlUnknown:
            "the console closed the control connection"
        case .controlConnectFailed:
            "the console could not open the control connection"
        case .controlConnectionRefused:
            "the console refused the control connection"
        case .streamUnknown:
            "the console closed the stream"
        case .consoleDisconnected:
            "the console disconnected"
        case .consoleShutDown:
            "the console shut down"
        case .timeLimitReached:
            "the streaming time limit was reached"
        case .trialEnded:
            "the game trial ended"
        case .internetPairingFailed:
            "pairing over the internet failed"
        }
    }

    /// Describes the cause of a failure, in lowercase for use inside a sentence.
    ///
    /// - Parameter cause: The failure cause.
    /// - Returns: The description.
    public static func label(_ cause: OperationProgress.FailureCause) -> String {
        switch cause {
        case .invalidState:
            "the session was in the wrong state"
        case .invalidPreferences:
            "the stream settings were rejected"
        case .providerUnavailable:
            "a system service was unavailable"
        case .controlFailed:
            "the control connection failed"
        case .routeFailed:
            "no route to the console worked"
        case .pipelineFailed:
            "the stream could not be set up"
        case .controllerRejected:
            "the controller was rejected"
        case .loginPINRejected:
            "the login PIN was rejected"
        case .shutdownFailed:
            "the session did not close cleanly"
        case .controlNetworkFailure:
            "the control connection was lost"
        case .controlTimeout:
            "the control connection timed out"
        case .controlTruncated:
            "the control answer was cut short"
        case .controlInvalidResponse:
            "the control answer was not understood"
        case .controlTooLarge:
            "the control answer was too large"
        case .controlRefused:
            "the control connection was refused"
        case .controlHandoffFailure:
            "the control connection could not be moved"
        case .invalidArgument:
            "the request was not valid"
        case .sessionRequestConnectionRefused:
            "the session connection was refused"
        case .controlConnectionRefused:
            "the console refused the control connection"
        case .resourceExhausted:
            "this Mac ran out of resources"
        case .pairingRejected:
            "the console no longer accepts this pairing"
        case .unpairedConsole:
            "PSN reached your primary PS4, which is not paired with this app; pair it at home or make the "
                + "intended PS4 your primary one"
        case .connectionLost:
            "the connection was lost"
        case .sessionRequestTruncated, .sessionRequestNetworkFailure, .sessionRequestTimeout,
             .sessionRequestInvalidResponse, .sessionRequestTooLarge, .sessionRequestRefused,
             .sessionRequestVersionMismatch, .sessionRequestInUse:
            sessionRequestLabel(cause)
        }
    }

    private static func sessionRequestLabel(_ cause: OperationProgress.FailureCause) -> String {
        switch cause {
        case .sessionRequestTruncated:
            "the session answer was cut short"
        case .sessionRequestNetworkFailure:
            "the session request was lost"
        case .sessionRequestTimeout:
            "the session request timed out"
        case .sessionRequestInvalidResponse:
            "the session answer was not understood"
        case .sessionRequestTooLarge:
            "the session answer was too large"
        case .sessionRequestRefused:
            "the session request was refused"
        case .sessionRequestVersionMismatch:
            "the console expects another Remote Play version"
        case .sessionRequestInUse:
            "the console is in use"
        case .invalidState, .invalidPreferences, .providerUnavailable, .controlFailed, .routeFailed,
             .pipelineFailed, .controllerRejected, .loginPINRejected, .shutdownFailed, .controlNetworkFailure,
             .controlTimeout, .controlTruncated, .controlInvalidResponse, .controlTooLarge, .controlRefused,
             .controlHandoffFailure, .invalidArgument, .sessionRequestConnectionRefused,
             .controlConnectionRefused, .resourceExhausted, .pairingRejected, .unpairedConsole,
             .connectionLost:
            "the session request failed"
        }
    }
}
