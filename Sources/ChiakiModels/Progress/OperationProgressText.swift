import Foundation

/// The player-facing title and detail lines that describe an operation's progress.
public struct OperationProgressText: Equatable, Sendable {
    /// The headline: the current route step when routing, otherwise the operation's step.
    public let title: LocalizedStringResource
    /// Detail lines such as step position, queue position, waits, attempts and elapsed time, omitting any
    /// that do not apply.
    public let details: [LocalizedStringResource]

    /// Describes progress as of a report.
    ///
    /// - Parameters:
    ///   - progress: The latest progress report.
    ///   - sinceReport: Time since the report, added to elapsed time and subtracted from retry countdowns.
    public init(_ progress: OperationProgress, sinceReport: Duration = .zero) {
        let since = max(0, Int(sinceReport.components.seconds))
        title = progress.route.map(Self.label) ?? Self.label(progress.step)
        let lines: [LocalizedStringResource?] = [
            progress.position.map { .progressStep(number: $0.number, total: $0.total) },
            progress.measured.map { .progressMeasured(number: $0.number, total: $0.total) },
            progress.route?.candidates.map(Self.label),
            progress.route?.chosen.map(Self.label),
            progress.queuePosition.map { .progressQueuePosition(position: $0) },
            progress.waitTimeEstimateSeconds.map(Self.waitEstimate),
            progress.migrationPercent.map { .progressMigration(percent: $0) },
            Self.bandwidth(progress),
            progress.wait.map { Self.label($0, since: since) },
            Self.attempt(progress),
            progress.previousFailure.flatMap(Self.label),
            progress.elapsedMilliseconds.map { .progressElapsed(seconds: $0 / 1000 + since) }
        ]
        details = lines.compactMap { $0 }
    }

    /// The title followed by the details.
    public var lines: [LocalizedStringResource] {
        [title] + details
    }
}

extension OperationProgressText {
    /// Describes the stream service's estimate of the server queue wait in whole minutes.
    ///
    /// - Parameter seconds: The estimated wait in seconds.
    /// - Returns: "Estimated wait: under a minute" below a minute, otherwise the minutes rounded down.
    static func waitEstimate(_ seconds: Int) -> LocalizedStringResource {
        seconds < 60
            ? .progressWaitEstimateUnderMinute
            : .progressWaitEstimateMinutes(minutes: seconds / 60)
    }
}

extension OperationProgressText {
    /// Names the step an operation is on.
    ///
    /// - Parameter step: The launch, connect or pairing step.
    /// - Returns: The label.
    public static func label(_ step: OperationProgress.Step) -> LocalizedStringResource {
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
    public static func label(_ activity: OperationProgress.LaunchActivity) -> LocalizedStringResource {
        switch activity {
        case .clearingWithCatalog:
            .progressLaunchClearingWithCatalog
        case .checkingDevice:
            .progressLaunchCheckingDevice
        case .openingTitleSession:
            .progressLaunchOpeningTitleSession
        case .resolvingTitle:
            .progressLaunchResolvingTitle
        case .takingFreeLicence:
            .progressLaunchTakingFreeLicence
        case .openingAccountSession:
            .progressLaunchOpeningAccountSession
        case .reservingServer:
            .progressLaunchReservingServer
        case .measuringDatacenters:
            .progressLaunchMeasuringDatacenters
        case .waitingForDatacenterChoice:
            .progressLaunchWaitingForDatacenterChoice
        case .allocatingServer:
            .progressLaunchAllocatingServer
        case .migratingData:
            .progressLaunchMigratingData
        case .connectingToServer:
            .progressLaunchConnectingToServer
        case .measuringBandwidth:
            .progressLaunchMeasuringBandwidth
        case .loadingLibrary:
            .progressLaunchLoadingLibrary
        case .checkingMembership:
            .progressLaunchCheckingMembership
        case .checkingCloudStreaming:
            .progressLaunchCheckingCloudStreaming
        case .checkingOwnership:
            .progressLaunchCheckingOwnership
        case .checkingEntitlement:
            .progressLaunchCheckingEntitlement
        case .resolvingCloudGame:
            .progressLaunchResolvingCloudGame
        case .checkingExclusions:
            .progressLaunchCheckingExclusions
        case .checkingRelease:
            .progressLaunchCheckingRelease
        }
    }

    /// Describes the bandwidth measurement, if one is reported.
    ///
    /// - Parameter progress: The progress report.
    /// - Returns: The description, or `nil`.
    static func bandwidth(_ progress: OperationProgress) -> LocalizedStringResource? {
        progress.bandwidth?.progressDescription
    }

    /// Names a console connection step.
    ///
    /// - Parameter step: The step.
    /// - Returns: The label.
    public static func label(_ step: OperationProgress.ConnectStep) -> LocalizedStringResource {
        switch step {
        case .findingConsole:
            .progressConnectFindingConsole
        case .openingAccountSession:
            .progressConnectOpeningAccountSession
        case .wakingConsole:
            .progressConnectWakingConsole
        case .pairing:
            .progressConnectPairing
        case .reachingConsole:
            .progressConnectReachingConsole
        case .openingStreamRoute:
            .progressConnectOpeningStreamRoute
        case .requestingSession:
            .progressConnectRequestingSession
        case .openingControl:
            .progressConnectOpeningControl
        case .measuringConnection:
            .progressConnectMeasuringConnection
        case .startingStream:
            .progressConnectStartingStream
        }
    }

    /// Names a pairing step.
    ///
    /// - Parameter step: The step.
    /// - Returns: The label.
    public static func label(_ step: OperationProgress.PairingStep) -> LocalizedStringResource {
        switch step {
        case .starting:
            .progressPairingStarting
        case .openingAccountSession:
            .progressPairingOpeningAccountSession
        case .wakingConsole:
            .progressPairingWakingConsole
        case .reachingConsole:
            .progressPairingReachingConsole
        case .sendingRequest:
            .progressPairingSendingRequest
        case .waitingForAnswer:
            .progressPairingWaitingForAnswer
        case .saving:
            .progressPairingSaving
        }
    }
}

extension OperationProgressText {
    /// Describes a route negotiation step, naming whether it is the control or stream route.
    ///
    /// - Parameter route: The route progress.
    /// - Returns: The label.
    public static func label(_ route: OperationProgress.Route) -> LocalizedStringResource {
        let control = route.purpose == .control
        switch route.step {
        case .openingAccountSession:
            return .progressRouteOpeningAccountSession
        case .waitingForConsole:
            return .progressRouteWaitingForConsole
        case .gatheringCandidates:
            return control
                ? .progressRouteGatheringControl
                : .progressRouteGatheringStream
        case .exchangingOffers:
            return control
                ? .progressRouteExchangingControl
                : .progressRouteExchangingStream
        case .testingCandidates:
            return control
                ? .progressRouteTestingControl
                : .progressRouteTestingStream
        case .routeChosen:
            return control
                ? .progressRouteChosenControl
                : .progressRouteChosenStream
        case .confirmingRoute:
            return control
                ? .progressRouteConfirmingControl
                : .progressRouteConfirmingStream
        case .switchingControl:
            return .progressRouteSwitchingControl
        }
    }

    /// Describes the kind of route that was chosen.
    ///
    /// - Parameter kind: The route kind.
    /// - Returns: The label.
    public static func label(_ kind: OperationProgress.RouteKind) -> LocalizedStringResource {
        switch kind {
        case .local:
            .progressKindLocal
        case .publicAddress:
            .progressKindPublicAddress
        case .portGuessed:
            .progressKindPortGuessed
        case .discovered:
            .progressKindDiscovered
        }
    }

    /// Summarises the address candidates gathered for a route, by kind.
    ///
    /// - Parameter candidates: The candidate counts.
    /// - Returns: The summary.
    public static func label(_ candidates: OperationProgress.Candidates) -> LocalizedStringResource {
        .progressCandidates(
            total: candidates.total, local: candidates.local, publicAddress: candidates.publicAddress,
            guessed: candidates.portGuessed
        )
    }
}

extension OperationProgressText {
    /// Describes what an operation is waiting for.
    ///
    /// - Parameter reason: The wait reason.
    /// - Returns: The label.
    public static func label(_ reason: OperationProgress.WaitReason) -> LocalizedStringResource {
        switch reason {
        case .previousSessionClosing:
            .progressWaitPreviousSessionClosing
        case .serverQueue:
            .progressWaitServerQueue
        case .dataMigration:
            .progressWaitDataMigration
        case .datacenterChoice:
            .progressWaitDatacenterChoice
        case .titleNotReady:
            .progressWaitTitleNotReady
        case .networkUnreachable:
            .progressWaitNetworkUnreachable
        case .consoleWaking:
            .progressWaitConsoleWaking
        case .consoleJoining:
            .progressWaitConsoleJoining
        case .consoleAnswering:
            .progressWaitConsoleAnswering
        case .connectionRetry:
            .progressWaitConnectionRetry
        case .recentCloudSession:
            .progressWaitRecentCloudSession
        }
    }

    /// Describes a wait with a countdown to the next try.
    ///
    /// - Parameters:
    ///   - wait: The wait.
    ///   - since: Seconds since the report, subtracted from the countdown.
    /// - Returns: The reason, followed by when the next try happens when one is scheduled.
    public static func label(_ wait: OperationProgress.Wait, since: Int) -> LocalizedStringResource {
        let reason = label(wait.reason)
        guard let next = wait.nextTryMilliseconds, next > 0 else {
            return reason
        }
        let remaining = max(0, (next + 999) / 1000 - since)
        if wait.reason == .recentCloudSession {
            return settling(remaining)
        }
        return remaining == 0
            ? .progressWaitRetryNow(reason: String(localized: reason))
            : .progressWaitRetryIn(reason: String(localized: reason), seconds: remaining)
    }

    /// Counts down the settling time after the account's last cloud stream.
    ///
    /// - Parameter seconds: Whole seconds left.
    /// - Returns: "Waiting 20 seconds since last cloud stream", in the singular for one second.
    static func settling(_ seconds: Int) -> LocalizedStringResource {
        .progressSettling(seconds: seconds)
    }

    /// Describes the attempt: launches count tries while waiting, and connections and pairings show the
    /// attempt number after the first.
    ///
    /// - Parameter progress: The progress report.
    /// - Returns: The text, or `nil` when there is nothing to show.
    public static func attempt(_ progress: OperationProgress) -> LocalizedStringResource? {
        switch progress.step {
        case .launch:
            tries(progress)
        case .connect, .pairing:
            progress.attempt > 1
                ? .progressAttempt(number: progress.attempt)
                : nil
        }
    }

    /// Counts the tries made while an operation waits.
    ///
    /// - Parameter progress: The progress report.
    /// - Returns: The text, or `nil` when not waiting or nothing was tried yet.
    public static func tries(_ progress: OperationProgress) -> LocalizedStringResource? {
        guard progress.attempt > 0, progress.isWaiting else {
            return nil
        }
        return .progressTried(count: progress.attempt)
    }

    /// Describes why the previous attempt failed, preferring the console's quit reason.
    ///
    /// - Parameter failure: The previous failure.
    /// - Returns: The text, or `nil` when no reason is known.
    public static func label(_ failure: OperationProgress.Failure) -> LocalizedStringResource? {
        if let quit = failure.consoleQuit {
            return .progressLastAttemptFailed(reason: String(localized: label(quit)))
        }
        return failure.cause.map { .progressLastAttemptFailed(reason: String(localized: label($0))) }
    }
}

extension OperationProgressText {
    /// Describes why the console ended a session, in lowercase for use inside a sentence.
    ///
    /// - Parameter quit: The console's quit reason.
    /// - Returns: The description.
    public static func label(_ quit: OperationProgress.ConsoleQuit) -> LocalizedStringResource {
        switch quit {
        case .stopped:
            .progressQuitStopped
        case .sessionRequestUnknown:
            .progressQuitSessionRequestUnknown
        case .sessionRequestConnectionRefused:
            .progressQuitSessionRequestConnectionRefused
        case .consoleInUse:
            .progressQuitConsoleInUse
        case .remotePlayCrashed:
            .progressQuitRemotePlayCrashed
        case .remotePlayVersionMismatch:
            .progressQuitRemotePlayVersionMismatch
        case .controlUnknown:
            .progressQuitControlUnknown
        case .controlConnectFailed:
            .progressQuitControlConnectFailed
        case .controlConnectionRefused:
            .progressQuitControlConnectionRefused
        case .streamUnknown:
            .progressQuitStreamUnknown
        case .consoleDisconnected:
            .progressQuitConsoleDisconnected
        case .consoleShutDown:
            .progressQuitConsoleShutDown
        case .timeLimitReached:
            .progressQuitTimeLimitReached
        case .trialEnded:
            .progressQuitTrialEnded
        case .internetPairingFailed:
            .progressQuitInternetPairingFailed
        }
    }

    /// Describes the cause of a failure, in lowercase for use inside a sentence.
    ///
    /// - Parameter cause: The failure cause.
    /// - Returns: The description.
    public static func label(_ cause: OperationProgress.FailureCause) -> LocalizedStringResource {
        switch cause {
        case .invalidState:
            .progressCauseInvalidState
        case .invalidPreferences:
            .progressCauseInvalidPreferences
        case .providerUnavailable:
            .progressCauseProviderUnavailable
        case .controlFailed:
            .progressCauseControlFailed
        case .routeFailed:
            .progressCauseRouteFailed
        case .pipelineFailed:
            .progressCausePipelineFailed
        case .controllerRejected:
            .progressCauseControllerRejected
        case .loginPINRejected:
            .progressCauseLoginPINRejected
        case .shutdownFailed:
            .progressCauseShutdownFailed
        case .controlNetworkFailure:
            .progressCauseControlNetworkFailure
        case .controlTimeout:
            .progressCauseControlTimeout
        case .controlTruncated:
            .progressCauseControlTruncated
        case .controlInvalidResponse:
            .progressCauseControlInvalidResponse
        case .controlTooLarge:
            .progressCauseControlTooLarge
        case .controlRefused:
            .progressCauseControlRefused
        case .controlHandoffFailure:
            .progressCauseControlHandoffFailure
        case .invalidArgument:
            .progressCauseInvalidArgument
        case .sessionRequestConnectionRefused:
            .progressCauseSessionRequestConnectionRefused
        case .controlConnectionRefused:
            .progressCauseControlConnectionRefused
        case .resourceExhausted:
            .progressCauseResourceExhausted
        case .pairingRejected:
            .progressCausePairingRejected
        case .unpairedConsole:
            .progressCauseUnpairedConsole
        case .connectionLost:
            .progressCauseConnectionLost
        case .sessionRequestTruncated, .sessionRequestNetworkFailure, .sessionRequestTimeout,
             .sessionRequestInvalidResponse, .sessionRequestTooLarge, .sessionRequestRefused,
             .sessionRequestVersionMismatch, .sessionRequestInUse:
            sessionRequestLabel(cause)
        }
    }

    private static func sessionRequestLabel(
        _ cause: OperationProgress.FailureCause
    ) -> LocalizedStringResource {
        switch cause {
        case .sessionRequestTruncated:
            .progressCauseSessionRequestTruncated
        case .sessionRequestNetworkFailure:
            .progressCauseSessionRequestNetworkFailure
        case .sessionRequestTimeout:
            .progressCauseSessionRequestTimeout
        case .sessionRequestInvalidResponse:
            .progressCauseSessionRequestInvalidResponse
        case .sessionRequestTooLarge:
            .progressCauseSessionRequestTooLarge
        case .sessionRequestRefused:
            .progressCauseSessionRequestRefused
        case .sessionRequestVersionMismatch:
            .progressCauseSessionRequestVersionMismatch
        case .sessionRequestInUse:
            .progressCauseSessionRequestInUse
        case .invalidState, .invalidPreferences, .providerUnavailable, .controlFailed, .routeFailed,
             .pipelineFailed, .controllerRejected, .loginPINRejected, .shutdownFailed, .controlNetworkFailure,
             .controlTimeout, .controlTruncated, .controlInvalidResponse, .controlTooLarge, .controlRefused,
             .controlHandoffFailure, .invalidArgument, .sessionRequestConnectionRefused,
             .controlConnectionRefused, .resourceExhausted, .pairingRejected, .unpairedConsole,
             .connectionLost:
            .progressCauseSessionRequestFailed
        }
    }
}
