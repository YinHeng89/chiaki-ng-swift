/// Why an account operation did not finish.
public enum AccountsFailure: Error, Hashable, Sendable {
    /// The saved accounts could not be read.
    case loadFailed

    /// The web sign-in failed.
    case signIn(SignInFailure)

    /// The typed account id is not the Base64 text of eight bytes.
    case invalidAccountID

    /// An account added by account id could not be saved.
    case saveFailed

    /// The account could not be deleted.
    case deleteFailed

    /// The saved accounts could not be read or updated while refreshing them.
    case refreshFailed
}
