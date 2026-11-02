/// Why a web sign-in did not produce an account.
public enum SignInFailure: Error, Hashable, Sendable {
    /// The user closed the sign-in, or the operation was cancelled.
    case cancelled

    /// The sign-in page could not be opened on this device.
    case browserUnavailable

    /// The page left the sign-in hosts or failed to load.
    case navigationFailed

    /// The sign-in answer did not contain a usable NPSSO.
    case unreadableResponse

    /// Every QR code issued for the sign-in expired before one was approved.
    case codesExpired

    /// PSN refused the token or the account.
    case rejected

    /// PSN is limiting requests.
    case rateLimited

    /// The PlayStation service is temporarily down.
    case serviceUnavailable

    /// The network failed, or PSN answered in a way the sign-in could not use.
    case unreachable

    /// PSN signed in a different account than the one being reconnected.
    case differentAccount

    /// The account could not be saved: database or Keychain.
    case storage
}

/// Why the core's NPSSO exchange did not produce a signed-in user.
public enum CoreSignInFailure: Error, Hashable, Sendable {
    /// The NPSSO or another argument was not usable; nothing was sent.
    case invalidRequest

    /// The installation's device id was not usable.
    case invalidDevice

    /// The attempt was cancelled.
    case cancelled

    /// The request did not complete.
    case transport

    /// PSN refused the NPSSO.
    case rejected

    /// PSN is rate limiting sign-in.
    case rateLimited

    /// PSN answered with a status the exchange does not expect, with that status when it gave one.
    case unavailable(httpStatus: Int?)

    /// PSN's reply could not be read.
    case malformed

    /// The person refused a QR sign-in on the device that scanned the code.
    case declined

    /// PSN kept asking for additional verification until no replacement QR code was left.
    case verificationRequired

    /// Every QR code issued for the sign-in expired or was invalidated before it was approved.
    case expired

    /// The hosted sign-in page no longer has the shape a QR sign-in reads its registration from.
    case layoutChanged

    /// The core is not open.
    case coreClosed

    /// The user to sign in again is not one the core holds.
    case unknownUser

    /// The NPSSO belongs to another account than the one signing in again.
    case differentAccount(AccountID?, onlineID: String)
}
