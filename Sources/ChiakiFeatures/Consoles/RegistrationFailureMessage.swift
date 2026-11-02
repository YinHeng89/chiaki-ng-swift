import ChiakiModels

/// The words the app shows for an account or console step that failed.
public enum RegistrationFailureMessage {
    /// What to tell the player about a failure.
    ///
    /// - Parameter failure: Why the step failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: RegistrationFailure) -> String {
        switch failure {
        case .invalidInput:
            "Enter a valid console address and eight-digit PIN."
        case .rejected:
            "Registration failed. Check the console address and generate a new PIN."
        case .unreachable:
            "The console didn't answer. Check the address and that the console is on, then try again."
        case .remoteRejected:
            "PlayStation registration failed. Retry or use a local PIN."
        case .unavailable:
            "The registration service is unavailable."
        case .storage:
            "Couldn't save the registration. Try again."
        case .sessionPlaying:
            "A session is playing"
        }
    }
}
