/// Why game invitations could not be listed or joined.
public enum CloudInvitationFailure: Error, Equatable, Sendable {
    /// The account has no PSN sign-in.
    case signedOut
    /// PSN refused the account's credentials.
    case auth
    /// PSN could not be reached or did not answer.
    case unavailable
    /// The request was cancelled.
    case cancelled
    /// The session has ended.
    case sessionEnded
    /// The player already plays in the session.
    case alreadyJoined
    /// The session is full.
    case full
    /// The session gives no way to join it.
    case cannotJoin
    /// PSN lists no cloud console for the account.
    case noCloudConsole
    /// The home console cannot take the command: it was forgotten, is a PS4, holds no pairing for the account or
    /// is not on its PSN account.
    case consoleUnavailable
    /// PSN refused the join.
    case rejected
    /// The cloud console could not join.
    case failed
    /// The cloud console did not finish joining in time.
    case timedOut
}
