import ChiakiModels
import Foundation

/// The words the app shows and logs for a failed pairing.
public enum PairingFailureMessage {
    /// What to tell the user about a failure.
    ///
    /// - Parameter failure: Why the attempt failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: PairingFailure) -> LocalizedStringResource {
        switch failure {
        case .invalidInput:
            .consolesRegistrationInvalidInput
        case .rejected:
            .consolesRegistrationRejected
        case .unreachable:
            .consolesRegistrationUnreachable
        case .unavailable:
            .consolesRegistrationUnavailable
        case .notSaved:
            .consolesRegistrationNotSaved
        case .sessionPlaying:
            .consolesRegistrationSessionPlaying
        case .cancelled:
            .consolesRegistrationCancelled
        case .overInternet(let stage, code: nil):
            .consolesRegistrationOverInternetFailed(stage: String(localized: title(of: stage)))
        case .overInternet(let stage, code: let code?):
            .consolesRegistrationOverInternetFailedCode(
                stage: String(localized: title(of: stage)),
                code: String(code)
            )
        }
    }

    /// The name of an internet pairing stage, as it reads inside a log sentence.
    ///
    /// - Parameter stage: The stage.
    /// - Returns: A lowercase English phrase such as `"console wake"`.
    public static func name(of stage: InternetPairingStage) -> String {
        switch stage {
        case .starting:
            "service initialization"
        case .openingSession:
            "PSN session creation"
        case .wakingConsole:
            "console wake"
        case .connecting:
            "console connection"
        case .pairing:
            "console registration"
        }
    }

    private static func title(of stage: InternetPairingStage) -> LocalizedStringResource {
        switch stage {
        case .starting:
            .consolesRegistrationStageStarting
        case .openingSession:
            .consolesRegistrationStageOpeningSession
        case .wakingConsole:
            .consolesRegistrationStageWakingConsole
        case .connecting:
            .consolesRegistrationStageConnecting
        case .pairing:
            .consolesRegistrationStagePairing
        }
    }
}
