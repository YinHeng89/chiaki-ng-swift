import Foundation

/// Why a stream session failed.
///
/// One type for console, cloud and guest streams. The text shown for each case lives with the views.
public enum StreamFailure: Error, Equatable, Sendable {
    /// The previous stream is still closing.
    case busy

    /// The video player could not be created.
    case renderer

    /// The console's saved pairing could not be loaded.
    case credentials

    /// The account must sign in again before it can stream from the cloud.
    case signInRequired

    /// The saved controller settings could not be loaded.
    case inputConfiguration

    /// The saved picture settings could not be loaded.
    case settingsUnavailable

    /// The cloud title has no valid launch information.
    case invalidTitle

    /// The stream stayed at one start stage past its deadline.
    case timedOut(StreamDeadline)

    /// The core ended the stream with an outcome, over the internet when `overInternet` is set.
    case stream(StreamOutcome, overInternet: Bool)

    /// The cloud service refused the stream, with the explanation shown to the player.
    case serviceRefused(LocalizedStringResource)

    /// A Kakusan guest stream failed.
    case kakusan(KakusanError)

    /// The outcome the core reported, when the failure came from the core.
    public var outcome: StreamOutcome? {
        guard case .stream(let outcome, _) = self else {
            return nil
        }
        return outcome
    }

    /// Whether the console refused the pairing, so pairing again is the way forward.
    public var rejectsPairing: Bool {
        outcome?.cause == .pairingRejected
    }
}

/// How long a starting stream may stay at one stage before it is given up.
public enum StreamDeadline: Hashable, Sendable {
    /// A console or guest start attempt, counted from zero.
    case startAttempt(Int)

    /// A cloud start step.
    case cloudStep(CloudStartStep)

    /// The deadline for a start stage.
    ///
    /// - Parameter stage: The stage the stream is at.
    public init(_ stage: StreamStartStage) {
        switch stage {
        case .connecting(let attempt):
            self = .startAttempt(attempt)
        case .cloud(let step, _):
            self = .cloudStep(step)
        }
    }

    /// The time allowed.
    public var duration: Duration {
        switch self {
        case .startAttempt:
            .seconds(75)
        case .cloudStep(.connecting):
            .seconds(30)
        case .cloudStep:
            .seconds(180)
        }
    }
}
