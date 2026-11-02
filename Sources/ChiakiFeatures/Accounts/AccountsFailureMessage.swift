import ChiakiModels

/// The words the app shows for a failed account operation or sign-in.
public enum AccountsFailureMessage {
    /// What to tell the user about a failed account operation.
    ///
    /// - Parameter failure: Why the operation failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: AccountsFailure) -> String {
        switch failure {
        case .loadFailed:
            "Couldn’t open saved accounts. Try again."
        case .signIn(let failure):
            text(for: failure)
        case .invalidAccountID:
            "That isn’t a Base64 PSN account ID."
        case .saveFailed:
            "Couldn’t save this account. Check storage and Keychain access, then try again."
        case .deleteFailed:
            "Couldn’t delete this account. Try again."
        case .refreshFailed:
            "Couldn’t refresh your accounts. Try again."
        }
    }

    /// What to tell the user about a failed sign-in.
    ///
    /// - Parameter failure: Why the sign-in failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: SignInFailure) -> String {
        switch failure {
        case .cancelled:
            "Sign-in cancelled."
        case .browserUnavailable, .navigationFailed, .unreadableResponse:
            "The sign-in couldn’t finish. Try again."
        case .codesExpired:
            "The sign-in codes expired before one was approved. Show a new code to try again."
        case .rejected:
            "The sign-in was refused. Try again."
        case .rateLimited:
            "PlayStation is limiting requests. Try again later."
        case .serviceUnavailable:
            "The PlayStation service is temporarily unavailable."
        case .unreachable:
            "Couldn’t reach or verify your PlayStation account. Try again."
        case .differentAccount:
            "That is a different PlayStation account. Sign in with the account you are reconnecting."
        case .storage:
            "Couldn’t save this account. Check storage and Keychain access, then try again."
        }
    }
}
