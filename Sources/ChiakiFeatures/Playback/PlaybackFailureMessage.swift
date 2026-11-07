import ChiakiModels
import Foundation

/// The words the app shows for a console stream that could not start or ended early.
public enum PlaybackFailureMessage {
    /// A sentence telling the player what went wrong and, where possible, what to do next.
    ///
    /// - Parameter failure: Why the stream stopped.
    /// - Returns: The sentence.
    public static func text(for failure: PlaybackFailure) -> LocalizedStringResource {
        switch failure {
        case .credentials:
            .playbackFailureCredentials
        case .consoleNotOnLocalNetwork:
            .playbackFailureConsoleNotOnLocalNetwork
        case .remoteUnavailable:
            .playbackFailureRemoteUnavailable
        case .remoteDisabled:
            .playbackFailureRemoteDisabled
        case .inputConfiguration:
            .playbackFailureInputConfiguration
        case .renderer:
            .playbackFailureRenderer
        case .wakeRefused:
            .playbackFailureWakeRefused
        case .stream(.startRefused(let refusal), let overInternet):
            message(refusal, overInternet: overInternet)
        case .stream(let outcome, _):
            message(outcome)
        }
    }

    private static func message(
        _ refusal: StreamOutcome.StartRefusal,
        overInternet: Bool
    ) -> LocalizedStringResource {
        switch refusal {
        case .busy:
            .playbackFailureBusy
        case .notPaired, .unknownUser, .unknownConsole:
            text(for: .credentials)
        case .consoleUnreachable:
            if overInternet {
                text(for: .remoteUnavailable)
            } else {
                text(for: .consoleNotOnLocalNetwork)
            }
        case .networkUnreachable:
            if overInternet {
                .playbackFailureNetworkUnreachableInternet
            } else {
                .playbackFailureNetworkUnreachableLocal
            }
        case .remotePlayDisabled:
            text(for: .remoteDisabled)
        case .signInExpired, .needsPSNSignIn:
            .playbackFailureSignInPlayStation
        case .invalidPreferences:
            .playbackFailureInvalidPreferences
        case .noDecoder:
            text(for: .renderer)
        case .coreClosed:
            .playbackFailureCoreClosed
        case .cancelled:
            .playbackFailureStartCancelled
        case .hostRefused:
            .playbackFailureHostRefused
        case .launchRefused, .invalidTitle:
            stopped(.startRefused(refusal))
        }
    }

    private static func message(_ outcome: StreamOutcome) -> LocalizedStringResource {
        if outcome.cause == .pairingRejected {
            return .playbackFailurePairingRejected
        }
        if outcome.cause == .unpairedConsole {
            return .playbackFailureUnpairedConsole
        }
        if outcome.cause == .connectionLost {
            return .playbackFailureConnectionLost
        }
        return switch outcome {
        case .consoleQuit(.sessionRequestUnknown), .startFailed(.controlNetworkFailure),
             .startFailed(.controlTimeout):
            .playbackFailureWakeNotReady
        case .consoleQuit(.sessionRequestConnectionRefused), .consoleQuit(.controlConnectionRefused),
             .startFailed(.controlRefused), .startFailed(.sessionRequestConnectionRefused),
             .startFailed(.controlConnectionRefused), .sessionFailed(.sessionRequestConnectionRefused),
             .sessionFailed(.controlConnectionRefused):
            .playbackFailureConnectionRefused
        case .startFailed(.resourceExhausted), .sessionFailed(.resourceExhausted),
             .shutdownFailed(.resourceExhausted):
            .playbackFailureResourceExhausted
        case .consoleQuit(.consoleInUse):
            .playbackFailureConsoleInUse
        case .consoleQuit(.remotePlayVersionMismatch):
            .playbackFailureVersionMismatch
        case .consoleQuit(.timeLimitReached):
            .playbackFailureTimeLimitReached
        case .consoleQuit(.trialEnded):
            .playbackFailureTrialEnded
        case .sessionFailed(let cause?):
            sessionMessage(cause) ?? stopped(outcome)
        default:
            stopped(outcome)
        }
    }

    private static func sessionMessage(_ cause: StreamOutcome.Cause) -> LocalizedStringResource? {
        switch cause {
        case .controlNetworkFailure:
            .playbackFailureCtrlNetworkFailure
        case .controlTimeout:
            .playbackFailureCtrlTimeout
        case .controlTruncated:
            .playbackFailureCtrlTruncated
        case .controlInvalidResponse:
            .playbackFailureCtrlInvalidResponse
        case .controlTooLarge:
            .playbackFailureCtrlTooLarge
        case .controlRefused:
            .playbackFailureCtrlRefused
        case .controlHandoffFailure:
            .playbackFailureCtrlHandoffFailure
        case .sessionRequestTruncated:
            .playbackFailureSessionSetupTruncated
        case .sessionRequestNetworkFailure:
            .playbackFailureSessionSetupNetworkFailure
        case .sessionRequestTimeout:
            .playbackFailureSessionSetupTimeout
        case .sessionRequestInvalidResponse:
            .playbackFailureSessionSetupInvalidResponse
        case .sessionRequestTooLarge:
            .playbackFailureSessionSetupTooLarge
        case .sessionRequestRefused:
            .playbackFailureSessionSetupRefused
        case .sessionRequestVersionMismatch:
            .playbackFailureSessionSetupVersionMismatch
        case .sessionRequestInUse:
            .playbackFailureSessionSetupInUse
        default:
            nil
        }
    }

    private static func stopped(_ outcome: StreamOutcome) -> LocalizedStringResource {
        .playbackFailureVideoSessionStopped(outcome: outcome.name)
    }
}

/// The words the app shows for a cloud stream that could not start or continue.
public enum CloudPlaybackFailureMessage {
    /// What to tell the player when the cloud server stopped sending anything, as when the network drops.
    public static let connectionLost: LocalizedStringResource = .playbackFailureCloudConnectionLost

    /// What to tell the player about a failure.
    ///
    /// - Parameter failure: Why the stream stopped.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: CloudPlaybackFailure) -> LocalizedStringResource {
        switch failure {
        case .notStreamable(let detail):
            .playbackFailureCloudNotStreamable(detail: detail)
        case .notReleased(let detail):
            .playbackFailureCloudNotReleased(detail: detail)
        case .invalidTitle:
            .playbackFailureCloudInvalidTitle
        case .signInRequired:
            .playbackFailureCloudSignInRequired
        case .busy:
            .playbackFailureBusy
        case .renderer:
            .playbackFailureCloudRenderer
        case .surfaceLost:
            .playbackFailureCloudSurfaceLost
        case .timedOut:
            .playbackFailureCloudTimedOut
        case .refused(let message):
            .verbatim(message)
        case .stream(let outcome) where outcome.cause == .connectionLost:
            Self.connectionLost
        case .stream(let outcome):
            .playbackFailureCloudSessionStopped(outcome: outcome.name)
        }
    }
}

extension StreamEndReport {
    /// A player-facing message for a cloud launch refusal or a start refusal with cloud wording, or `nil` to
    /// fall back to the generic message.
    public var cloudMessage: LocalizedStringResource? {
        if let launchRefused {
            return launchRefused.message
        }
        guard case .startRefused(let refusal) = outcome else {
            return nil
        }
        switch refusal {
        case .busy:
            return CloudPlaybackFailureMessage.text(for: .busy)
        case .signInExpired, .needsPSNSignIn, .unknownUser:
            return CloudPlaybackFailureMessage.text(for: .signInRequired)
        case .invalidTitle:
            return CloudPlaybackFailureMessage.text(for: .invalidTitle)
        case .invalidPreferences:
            return .playbackFailureCloudInvalidPreferences
        case .noDecoder:
            return CloudPlaybackFailureMessage.text(for: .renderer)
        default:
            return nil
        }
    }
}

extension CloudLaunchRefused {
    /// The player-facing message for the refusal.
    var message: LocalizedStringResource {
        switch self {
        case .notCleared(let clearance):
            CloudClearanceRefusalMessage.text(for: clearance)
        case .privacySettings:
            .playbackFailureLaunchPrivacySettings
        case .licenceNotFree(let price):
            price.isEmpty
                ? .playbackFailureLaunchMustBuy
                : .playbackFailureLaunchMustBuyPrice(price: price)
        case .membershipRejected:
            .playbackFailureLaunchMembership
        case .outsideStreamingPlan:
            .playbackFailureLaunchOutsidePlan
        case .storeRegion:
            .playbackFailureLaunchStoreRegion
        case .notBuilt:
            .playbackFailureLaunchNotBuilt
        case .titleNotFound:
            .playbackFailureLaunchTitleNotFound
        case .refusedByStreamService:
            .playbackFailureLaunchRefusedByService
        case .noReachableDatacenter:
            .playbackFailureLaunchNoReachableDatacenter
        case .datacenterUnavailable(let datacenter):
            datacenter.isEmpty
                ? .playbackFailureLaunchDatacenterUnavailable
                : .playbackFailureLaunchNamedDatacenterUnavailable(datacenter: datacenter)
        case .noServer:
            .playbackFailureLaunchNoServer
        case .signInExpired:
            CloudPlaybackFailureMessage.text(for: .signInRequired)
        case .unavailable:
            .playbackFailureLaunchUnavailable
        }
    }
}

/// The text shown for a `ChiakiModels/StreamFailure`, worded for the kind of stream that failed.
public struct StreamFailureMessage: Equatable {
    /// The text.
    public let text: LocalizedStringResource

    /// Words a failure.
    ///
    /// - Parameters:
    ///   - failure: The failure.
    ///   - kind: The kind of stream that failed.
    public init(_ failure: StreamFailure, kind: StreamKind) {
        text = Self.text(failure, kind: kind)
    }

    private static func text(_ failure: StreamFailure, kind: StreamKind) -> LocalizedStringResource {
        switch failure {
        case .busy:
            .playbackFailureBusy
        case .renderer:
            kind == .cloud
                ? .playbackFailureCloudRenderer
                : PlaybackFailureMessage.text(for: .renderer)
        case .credentials:
            PlaybackFailureMessage.text(for: .credentials)
        case .signInRequired:
            CloudPlaybackFailureMessage.text(for: .signInRequired)
        case .inputConfiguration:
            PlaybackFailureMessage.text(for: .inputConfiguration)
        case .settingsUnavailable:
            .playbackFailureSettingsUnavailable
        case .invalidTitle:
            CloudPlaybackFailureMessage.text(for: .invalidTitle)
        case .timedOut(.startAttempt):
            .playbackFailureStartAttemptTimedOut
        case .timedOut(.cloudStep):
            .playbackFailureCloudTimedOut
        case .stream(.consoleQuit(let reason), let overInternet) where reason?.endsPlayTime == true:
            PlaybackFailureMessage.text(for: .stream(.consoleQuit(reason), overInternet: overInternet))
        case .stream(let outcome, _) where kind == .cloud && outcome.cause == .connectionLost:
            CloudPlaybackFailureMessage.connectionLost
        case .stream(let outcome, _) where kind == .cloud:
            .playbackFailureCloudSessionStopped(outcome: outcome.name)
        case .stream(let outcome, let overInternet):
            PlaybackFailureMessage.text(for: .stream(outcome, overInternet: overInternet))
        case .serviceRefused(let message):
            message
        case .kakusan(let error):
            .playbackFailureKakusan(error: error.rawValue)
        }
    }
}
