import ChiakiModels
import ComposableArchitecture
import Foundation

/// Reads, adds, signs in, refreshes and deletes the accounts the app knows, captures the NPSSO of a web
/// sign-in, and lists and reveals the accounts' credentials for the Tokens settings panel.
///
/// Account failures are returned, never thrown, so a feature sends each result back tagged with the operation
/// that started it. The live value is provided by the app's composition root, which owns the open database and
/// core and shows the web sign-in page; this module declares the interface and an unimplemented test value.
public struct AccountsClient: Sendable {
    /// Reads every saved account, merging unlinked duplicates first.
    public var load: @Sendable () async -> Result<[AccountProfile], AccountsFailure>

    /// Saves an account added by account id, for local play without a sign-in.
    public var addAccountID: @Sendable (
        _ profile: UUID,
        _ name: String,
        _ account: AccountID
    ) async -> Result<AccountProfile, AccountsFailure>

    /// Signs in through the core with a captured NPSSO and saves the account.
    ///
    /// The capture is consumed: its token is wiped when the sign-in no longer needs it.
    public var signIn: @Sendable (
        _ profile: UUID,
        _ capture: consuming SignInCapture
    ) async -> Result<AccountProfile, SignInFailure>

    /// Signs a new account in through the core by a QR code another device scans and approves, and saves it.
    ///
    /// Each step before the sign-in ends is reported through `progress`. Cancelling the calling task ends the
    /// sign-in with `ChiakiModels/SignInFailure/cancelled`.
    public var signInWithQR: @Sendable (
        _ profile: UUID,
        _ progress: @escaping @Sendable (QRSignInProgress) -> Void
    ) async -> Result<AccountProfile, SignInFailure>

    /// Deletes an account with its tokens, pairings and cached profile.
    ///
    /// Returns `nil` on success, or why the account could not be deleted.
    public var delete: @Sendable (_ profile: UUID) async -> AccountsFailure?

    /// Refreshes every signed-in account's profile and membership.
    public var refresh: @Sendable () async -> Result<AccountRefreshResult, AccountsFailure>

    /// Reads the account the user last selected.
    public var selectedAccount: @Sendable () async -> UUID?

    /// Remembers the account the user selected.
    ///
    /// Returns whether it was remembered.
    public var selectAccount: @Sendable (_ profile: UUID) async -> Bool

    /// Shows the web sign-in and waits for the user to finish, capturing the NPSSO it issues.
    ///
    /// The capture reports each stage through `stages`. Cancelling the calling task closes the page and
    /// throws `ChiakiModels/SignInFailure/cancelled`.
    public var captureSignIn: @Sendable (
        _ stages: @escaping @Sendable (SignInStage) -> Void
    ) async throws(SignInFailure) -> SignInCapture

    /// Lists the saved accounts that have a PlayStation Network sign-in, with their held credentials.
    public var tokenAccounts: @Sendable () async throws -> [TokenAccount]

    /// Asks the device owner to authenticate for the given reason and returns whether they did.
    public var authenticateOwner: @Sendable (_ reason: String) async -> Bool

    /// Reads the secret of one credential kind for the account with these identifier bytes, or the reason it
    /// cannot be revealed.
    public var revealToken: @Sendable (_ account: Data, _ kind: CredentialKind) async
        -> Result<RevealedSecret, NotRevealed>

    /// Creates a client from its operations.
    ///
    /// - Parameters:
    ///   - load: Reads every saved account.
    ///   - addAccountID: Saves an account added by account id.
    ///   - signIn: Signs in with a captured NPSSO and saves the account.
    ///   - signInWithQR: Signs in by a QR code and saves the account.
    ///   - delete: Deletes an account.
    ///   - refresh: Refreshes every signed-in account.
    ///   - selectedAccount: Reads the selected account.
    ///   - selectAccount: Remembers the selected account.
    ///   - captureSignIn: Shows the web sign-in and returns the captured NPSSO; by default it reports an issue.
    ///   - tokenAccounts: Lists the accounts with their credentials; by default none.
    ///   - authenticateOwner: Asks the device owner to authenticate; by default it refuses.
    ///   - revealToken: Reveals one credential's secret; by default it reveals nothing.
    public init(
        load: @escaping @Sendable () async -> Result<[AccountProfile], AccountsFailure>,
        addAccountID: @escaping @Sendable (UUID, String, AccountID) async -> Result<
            AccountProfile,
            AccountsFailure
        >,
        signIn: @escaping @Sendable (UUID, consuming SignInCapture) async -> Result<
            AccountProfile,
            SignInFailure
        >,
        signInWithQR: @escaping @Sendable (UUID, @escaping @Sendable (QRSignInProgress) -> Void) async
            -> Result<
                AccountProfile,
                SignInFailure
            >,
        delete: @escaping @Sendable (UUID) async -> AccountsFailure?,
        refresh: @escaping @Sendable () async -> Result<AccountRefreshResult, AccountsFailure>,
        selectedAccount: @escaping @Sendable () async -> UUID?,
        selectAccount: @escaping @Sendable (UUID) async -> Bool,
        captureSignIn: @escaping @Sendable (
            _ stages: @escaping @Sendable (SignInStage) -> Void
        ) async throws(SignInFailure) -> SignInCapture = { _ throws(SignInFailure) in
            reportIssue("AccountsClient.captureSignIn is unimplemented")
            throw .browserUnavailable
        },
        tokenAccounts: @escaping @Sendable () async throws -> [TokenAccount] = {
            []
        },
        authenticateOwner: @escaping @Sendable (String) async -> Bool = { _ in
            false
        },
        revealToken: @escaping @Sendable (Data, CredentialKind) async
            -> Result<RevealedSecret, NotRevealed> = {
                _, _ in
                .failure(NotRevealed(.coreClosed))
            }
    ) {
        self.load = load
        self.addAccountID = addAccountID
        self.signIn = signIn
        self.signInWithQR = signInWithQR
        self.delete = delete
        self.refresh = refresh
        self.selectedAccount = selectedAccount
        self.selectAccount = selectAccount
        self.captureSignIn = captureSignIn
        self.tokenAccounts = tokenAccounts
        self.authenticateOwner = authenticateOwner
        self.revealToken = revealToken
    }
}

extension AccountsClient: TestDependencyKey {
    /// Reports an issue for every account operation and sign-in capture a test did not override; no account is
    /// remembered as selected, remembering one succeeds without storing it, no credentials are listed, the
    /// device owner never authenticates and nothing is revealed.
    public static let testValue = AccountsClient(
        load: {
            reportIssue("AccountsClient.load is unimplemented")
            return .failure(.loadFailed)
        },
        addAccountID: { _, _, _ in
            reportIssue("AccountsClient.addAccountID is unimplemented")
            return .failure(.saveFailed)
        },
        signIn: { _, _ in
            reportIssue("AccountsClient.signIn is unimplemented")
            return .failure(.storage)
        },
        signInWithQR: { _, _ in
            reportIssue("AccountsClient.signInWithQR is unimplemented")
            return .failure(.storage)
        },
        delete: { _ in
            reportIssue("AccountsClient.delete is unimplemented")
            return .deleteFailed
        },
        refresh: {
            reportIssue("AccountsClient.refresh is unimplemented")
            return .failure(.refreshFailed)
        },
        selectedAccount: {
            nil
        },
        selectAccount: { _ in
            true
        }
    )
}

extension DependencyValues {
    /// The accounts the app knows.
    public var accounts: AccountsClient {
        get {
            self[AccountsClient.self]
        }
        set {
            self[AccountsClient.self] = newValue
        }
    }
}
