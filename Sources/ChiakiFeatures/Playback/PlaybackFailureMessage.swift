import ChiakiModels
import Foundation

/// The words the app shows for a console stream that could not start or ended early.
public enum PlaybackFailureMessage {
    /// A sentence telling the player what went wrong and, where possible, what to do next.
    ///
    /// - Parameter failure: Why the stream stopped.
    /// - Returns: The sentence.
    public static func text(for failure: PlaybackFailure) -> String {
        switch failure {
        case .credentials:
            "Saved pairing credentials couldn’t be loaded. Pair the console again."
        case .consoleNotOnLocalNetwork:
            "This console hasn’t been found on your local network yet. "
                + "Make sure it’s on and on the same network, wait a few seconds, then try again, "
                + "or use Remote."
        case .remoteUnavailable:
            "This console is no longer available through your PlayStation account."
        case .remoteDisabled:
            "Remote Play is disabled for this console in your PlayStation account."
        case .inputConfiguration:
            "Saved controller settings couldn’t be loaded."
        case .renderer:
            "The Metal video surface couldn’t be created."
        case .wakeRefused:
            "The wake request could not be sent."
        case .stream(.startRefused(let refusal), let overInternet):
            message(refusal, overInternet: overInternet)
        case .stream(let outcome, _):
            message(outcome)
        }
    }

    private static func message(_ refusal: StreamOutcome.StartRefusal, overInternet: Bool) -> String {
        switch refusal {
        case .busy:
            "The previous stream is still closing. Try again in a moment."
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
                "PlayStation Network couldn’t be reached. Check your internet connection and try again."
            } else {
                "Your local network couldn’t be reached. Check your connection, and that chiaki-ng has "
                    + "Local Network access in System Settings › Privacy & Security."
            }
        case .remotePlayDisabled:
            text(for: .remoteDisabled)
        case .signInExpired, .needsPSNSignIn:
            "Sign in to PlayStation again to play over the internet."
        case .invalidPreferences:
            "The stream settings were rejected. Check the picture settings."
        case .noDecoder:
            text(for: .renderer)
        case .coreClosed:
            "Streaming is unavailable. Quit and reopen the app."
        case .cancelled:
            "Start cancelled"
        case .hostRefused:
            "The stream couldn’t start on this device. Close other apps and try again."
        case .launchRefused, .invalidTitle:
            stopped(.startRefused(refusal))
        }
    }

    private static func message(_ outcome: StreamOutcome) -> String {
        if outcome.cause == .pairingRejected {
            return "The console no longer accepts this pairing. Unpair, then pair again."
        }
        if outcome.cause == .unpairedConsole {
            return "PlayStation Network connected to a PS4 that isn’t paired with chiaki-ng. "
                + "Pair that PS4 at home first, or make this PS4 the primary console on your account."
        }
        if outcome.cause == .connectionLost {
            return "The connection to the console was lost. Check the network and try again."
        }
        return switch outcome {
        case .consoleQuit(.sessionRequestUnknown), .startFailed(.controlNetworkFailure),
             .startFailed(.controlTimeout):
            "The console did not become ready for Remote Play after the wake request."
        case .consoleQuit(.sessionRequestConnectionRefused), .consoleQuit(.controlConnectionRefused),
             .startFailed(.controlRefused), .startFailed(.sessionRequestConnectionRefused),
             .startFailed(.controlConnectionRefused), .sessionFailed(.sessionRequestConnectionRefused),
             .sessionFailed(.controlConnectionRefused):
            "The console refused the connection. Check Remote Play is available."
        case .startFailed(.resourceExhausted), .sessionFailed(.resourceExhausted),
             .shutdownFailed(.resourceExhausted):
            "chiaki-ng ran out of network sockets or file handles. Quit and reopen the app, then try again."
        case .consoleQuit(.consoleInUse):
            "Remote Play is already in use on this console."
        case .consoleQuit(.remotePlayVersionMismatch):
            "The console and client Remote Play versions don’t match."
        case .consoleQuit(.timeLimitReached):
            "Streaming game closed because the time limit was reached."
        case .consoleQuit(.trialEnded):
            "Your game trial has ended. Buy the game from the PlayStation Store to keep playing."
        case .sessionFailed(let cause?):
            sessionMessage(cause) ?? stopped(outcome)
        default:
            stopped(outcome)
        }
    }

    private static func sessionMessage(_ cause: StreamOutcome.Cause) -> String? {
        switch cause {
        case .controlNetworkFailure:
            "The Ctrl connection failed. Check the network and try again."
        case .controlTimeout:
            "The Ctrl connection timed out. Try again."
        case .controlTruncated:
            "The Ctrl response was incomplete. Try again."
        case .controlInvalidResponse:
            "The Ctrl response was invalid."
        case .controlTooLarge:
            "The Ctrl response was too large."
        case .controlRefused:
            "The console refused the Ctrl connection. Check Remote Play is available."
        case .controlHandoffFailure:
            "The Ctrl connection could not hand off to streaming."
        case .sessionRequestTruncated:
            "The session setup response was incomplete. Try again."
        case .sessionRequestNetworkFailure:
            "The session setup connection failed. Check the network and try again."
        case .sessionRequestTimeout:
            "Session setup timed out. Try again."
        case .sessionRequestInvalidResponse:
            "The session setup response was invalid."
        case .sessionRequestTooLarge:
            "The session setup response was too large."
        case .sessionRequestRefused:
            "The console refused session setup. Check Remote Play is available."
        case .sessionRequestVersionMismatch:
            "The console and client Remote Play versions do not match."
        case .sessionRequestInUse:
            "Remote Play is already in use on this console. Close the active session and try again."
        default:
            nil
        }
    }

    private static func stopped(_ outcome: StreamOutcome) -> String {
        "The video session stopped (\(outcome.name))."
    }
}

/// The words the app shows for a cloud stream that could not start or continue.
public enum CloudPlaybackFailureMessage {
    /// What to tell the player when the cloud server stopped sending anything, as when the network drops.
    public static let connectionLost =
        "The connection to the cloud stream was lost. Nothing arrived for 20 seconds. Check your network and try again."

    /// What to tell the player about a failure.
    ///
    /// - Parameter failure: Why the stream stopped.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: CloudPlaybackFailure) -> String {
        switch failure {
        case .notStreamable(let detail):
            "This title can't be streamed: \(detail)."
        case .notReleased(let detail):
            "Not released yet: \(detail)."
        case .invalidTitle:
            "This title has no valid cloud launch information. Refresh the library."
        case .signInRequired:
            "Sign in again to renew your PlayStation credentials."
        case .busy:
            "The previous stream is still closing. Try again in a moment."
        case .renderer:
            "The video player could not start."
        case .surfaceLost:
            "The video player disconnected. Return to the library and try again."
        case .timedOut:
            "The cloud connection timed out. Please try again."
        case .refused(let message):
            message
        case .stream(let outcome) where outcome.cause == .connectionLost:
            Self.connectionLost
        case .stream(let outcome):
            "The cloud session could not continue (\(outcome.name)). Try again."
        }
    }
}

extension StreamEndReport {
    /// A player-facing message for a cloud launch refusal or a start refusal with cloud wording, or `nil` to
    /// fall back to the generic message.
    public var cloudMessage: String? {
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
            return "Cloud video settings were rejected. Check the requested resolution and bitrate."
        case .noDecoder:
            return CloudPlaybackFailureMessage.text(for: .renderer)
        default:
            return nil
        }
    }
}

extension CloudLaunchRefused {
    /// The player-facing message for the refusal.
    var message: String {
        switch self {
        case .notCleared(let clearance):
            CloudClearanceRefusalMessage.text(for: clearance)
        case .privacySettings:
            "Review your PlayStation privacy settings, then try again."
        case .licenceNotFree(let price):
            price.isEmpty
                ? "This title must be bought before it can be streamed."
                : "This title must be bought before it can be streamed (\(price))."
        case .membershipRejected:
            "PlayStation Plus Premium is required to stream this title."
        case .outsideStreamingPlan:
            "This title is no longer part of the PlayStation Plus streaming catalog."
        case .storeRegion:
            "This title is sold in a different PlayStation Store region than your account’s, so it can’t be licensed to you for streaming."
        case .notBuilt:
            "This build of the app can’t start PS Cloud titles."
        case .titleNotFound:
            "PlayStation couldn’t find this title for streaming."
        case .refusedByStreamService:
            "PlayStation refused to stream this title."
        case .noReachableDatacenter:
            "No streaming datacenter could be reached. Check the network and try again."
        case .datacenterUnavailable(let datacenter):
            datacenter.isEmpty
                ? "The chosen datacenter is unavailable."
                : "Datacenter \(datacenter) is unavailable."
        case .noServer:
            "No streaming server is free right now. Try again later."
        case .signInExpired:
            CloudPlaybackFailureMessage.text(for: .signInRequired)
        case .unavailable:
            "Cloud streaming is unavailable right now. Try again."
        }
    }
}

/// The text shown for a `ChiakiModels/StreamFailure`, worded for the kind of stream that failed.
public struct StreamFailureMessage: Equatable {
    /// The text.
    public let text: String

    /// Words a failure.
    ///
    /// - Parameters:
    ///   - failure: The failure.
    ///   - kind: The kind of stream that failed.
    public init(_ failure: StreamFailure, kind: StreamKind) {
        text = Self.text(failure, kind: kind)
    }

    private static func text(_ failure: StreamFailure, kind: StreamKind) -> String {
        switch failure {
        case .busy:
            "The previous stream is still closing. Try again in a moment."
        case .renderer:
            kind == .cloud
                ? "The video player could not start."
                : PlaybackFailureMessage.text(for: .renderer)
        case .credentials:
            PlaybackFailureMessage.text(for: .credentials)
        case .signInRequired:
            CloudPlaybackFailureMessage.text(for: .signInRequired)
        case .inputConfiguration:
            PlaybackFailureMessage.text(for: .inputConfiguration)
        case .settingsUnavailable:
            "The saved stream settings couldn’t be loaded. Check the picture settings and try again."
        case .invalidTitle:
            CloudPlaybackFailureMessage.text(for: .invalidTitle)
        case .timedOut(.startAttempt):
            "The connection attempt timed out before video started (75 seconds)."
        case .timedOut(.cloudStep):
            "The cloud connection timed out. Please try again."
        case .stream(.consoleQuit(let reason), let overInternet) where reason?.endsPlayTime == true:
            PlaybackFailureMessage.text(for: .stream(.consoleQuit(reason), overInternet: overInternet))
        case .stream(let outcome, _) where kind == .cloud && outcome.cause == .connectionLost:
            CloudPlaybackFailureMessage.connectionLost
        case .stream(let outcome, let overInternet):
            kind == .cloud
                ? "The cloud session could not continue (\(outcome.name)). Try again."
                : PlaybackFailureMessage.text(for: .stream(outcome, overInternet: overInternet))
        case .serviceRefused(let message):
            message
        case .kakusan(let error):
            "The shared game failed: \(error.rawValue)."
        }
    }
}
