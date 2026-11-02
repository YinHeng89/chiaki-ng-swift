import ChiakiModels

/// The words the app shows and logs for a failed pairing.
public enum PairingFailureMessage {
    /// What to tell the user about a failure.
    ///
    /// - Parameter failure: Why the attempt failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: PairingFailure) -> String {
        switch failure {
        case .invalidInput:
            "Enter a valid console address and eight-digit PIN."
        case .rejected:
            "Registration failed. Check the console address and generate a new PIN."
        case .unreachable:
            "The console didn't answer. Check the address and that the console is on, then try again."
        case .unavailable:
            "The registration service is unavailable."
        case .notSaved:
            "Couldn't save the registration. Try again."
        case .sessionPlaying:
            "A session is playing"
        case .cancelled:
            "Registration was cancelled."
        case .overInternet(let stage, code: nil):
            "PlayStation registration failed during \(name(of: stage)). Retry or use a local PIN."
        case .overInternet(let stage, code: let code?):
            "PlayStation registration failed during \(name(of: stage)) (code \(code)). Retry or use a local PIN."
        }
    }

    /// The name of an internet pairing stage, as it reads inside a sentence.
    ///
    /// - Parameter stage: The stage.
    /// - Returns: A lowercase phrase such as `"console wake"`.
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
}
