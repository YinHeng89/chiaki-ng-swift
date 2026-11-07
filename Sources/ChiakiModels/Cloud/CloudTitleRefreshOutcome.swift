import Foundation

/// What refreshing one cloud title's ownership found.
public enum CloudTitleRefreshOutcome: Equatable, Sendable {
    /// The account owns the title, as it now reads.
    case owned(CloudGame)

    /// The account does not own the title.
    case notOwned

    /// The check failed.
    case failed(CloudTitleRefreshFailure)

    /// The outcome as a log label.
    public var logLabel: String {
        switch self {
        case .owned:
            "owned"
        case .notOwned:
            "not owned"
        case .failed:
            "failed"
        }
    }
}

/// Why refreshing one cloud title's ownership failed, as the text the app shows.
public struct CloudTitleRefreshFailure: Error, Equatable, Sendable {
    /// The ownership check was cancelled.
    public static let cancelled = Self(.cloudRefreshCancelled)

    /// PlayStation refused the ownership check, so the account must sign in again.
    public static let signInRefused = Self(.cloudRefreshSignInRefused)

    /// The ownership check failed for another reason.
    public static let checkFailed = Self(.cloudRefreshFailed)

    /// The check answered without the updated title.
    public static let titleMissing = Self(.cloudRefreshTitleMissing)

    /// No usable PlayStation sign-in is saved for the account.
    public static let noSignIn = Self(.cloudRefreshNoSignIn)

    /// The message to show.
    public let message: LocalizedStringResource

    /// Describes a failure.
    ///
    /// - Parameter message: The message to show.
    public init(_ message: LocalizedStringResource) {
        self.message = message
    }
}
