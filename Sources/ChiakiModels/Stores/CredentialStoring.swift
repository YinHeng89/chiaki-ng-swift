/// Where the core's signed-in accounts and home users are persisted.
///
/// The core restores every account from here when it opens and saves each sign-in, token refresh and
/// removal through it.
public protocol CredentialStoring: Sendable {
    /// Loads every signed-in account whose secrets decrypt.
    ///
    /// - Returns: The saved sign-ins, oldest profile first.
    /// - Throws: ``CredentialStoreFailure/unavailable`` when the store cannot be read.
    func savedSignIns() throws(CredentialStoreFailure) -> [StoredSignIn]

    /// Loads every account added by id only.
    ///
    /// - Returns: The saved home users, oldest profile first.
    /// - Throws: ``CredentialStoreFailure/unavailable`` when the store cannot be read.
    func homeUsers() throws(CredentialStoreFailure) -> [StoredHomeUser]

    /// Saves a sign-in, replacing the account's NPSSO, tokens, region and context.
    ///
    /// - Parameter signIn: The sign-in.
    /// - Throws: ``CredentialStoreFailure/unavailable`` when the write failed; nothing is written then.
    func save(_ signIn: StoredSignIn) throws(CredentialStoreFailure)

    /// Saves an account added by id only, unless the account is saved already.
    ///
    /// - Parameter homeUser: The home user.
    /// - Throws: ``CredentialStoreFailure/unavailable`` when the write failed.
    func save(_ homeUser: StoredHomeUser) throws(CredentialStoreFailure)

    /// Deletes every profile holding an account, with everything stored for it.
    ///
    /// - Parameter account: The account.
    /// - Throws: ``CredentialStoreFailure/unavailable`` when the delete failed.
    func remove(_ account: AccountID) throws(CredentialStoreFailure)
}

/// Why the credential store could not do what the core asked.
public enum CredentialStoreFailure: Error, Hashable, Sendable {
    /// The store could not be read or written.
    case unavailable
}
