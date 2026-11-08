import ChiakiModels
import Foundation

/// The words the app shows for an account or console step that failed.
public enum RegistrationFailureMessage {
    /// What to tell the player about a failure.
    ///
    /// - Parameter failure: Why the step failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: RegistrationFailure) -> LocalizedStringResource {
        switch failure {
        case .invalidInput:
            .consolesRegistrationInvalidInput
        case .rejected:
            .consolesRegistrationRejected
        case .unreachable:
            .consolesRegistrationUnreachable
        case .remoteRejected:
            .consolesRegistrationRemoteRejected
        case .unavailable:
            .consolesRegistrationUnavailable
        case .storage:
            .consolesRegistrationNotSaved
        case .sessionPlaying:
            .consolesRegistrationSessionPlaying
        }
    }
}
