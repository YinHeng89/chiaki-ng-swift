import ChiakiModels
import Foundation

/// The words the app shows for a failed account operation or sign-in.
public enum AccountsFailureMessage {
    /// What to tell the user about a failed account operation.
    ///
    /// - Parameter failure: Why the operation failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: AccountsFailure) -> LocalizedStringResource {
        switch failure {
        case .loadFailed:
            .accountsFailureLoadFailed
        case .signIn(let failure):
            text(for: failure)
        case .invalidAccountID:
            .accountsFailureInvalidAccountId
        case .saveFailed:
            .accountsFailureSaveFailed
        case .deleteFailed:
            .accountsFailureDeleteFailed
        case .refreshFailed:
            .accountsFailureRefreshFailed
        }
    }

    /// What to tell the user about a failed sign-in.
    ///
    /// - Parameter failure: Why the sign-in failed.
    /// - Returns: One sentence with what to do next.
    public static func text(for failure: SignInFailure) -> LocalizedStringResource {
        switch failure {
        case .cancelled:
            .accountsSignInFailureCancelled
        case .browserUnavailable, .navigationFailed, .unreadableResponse:
            .accountsSignInFailureIncomplete
        case .codesExpired:
            .accountsSignInFailureCodesExpired
        case .rejected:
            .accountsSignInFailureRejected
        case .rateLimited:
            .accountsSignInFailureRateLimited
        case .serviceUnavailable:
            .accountsSignInFailureServiceUnavailable
        case .unreachable:
            .accountsSignInFailureUnreachable
        case .differentAccount:
            .accountsSignInFailureDifferentAccount
        case .storage:
            .accountsFailureSaveFailed
        }
    }
}
