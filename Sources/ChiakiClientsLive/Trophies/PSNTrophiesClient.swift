import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels

extension PSNTrophiesClient {
    /// The client over the core, finding each profile's PSN account in the app's accounts.
    ///
    /// - Parameter accounts: The app's account service.
    /// - Returns: The live client.
    public static func live(_ accounts: AccountService) -> Self {
        let bridge = PSNTrophiesBridge()
        return Self(
            summary: { profile throws(PSNTrophiesFailure) in
                try await bridge.summary(account: account(of: profile, in: accounts))
            },
            titles: { profile throws(PSNTrophiesFailure) in
                try await bridge.titles(account: account(of: profile, in: accounts))
            },
            trophies: { profile, title throws(PSNTrophiesFailure) in
                try await bridge.trophies(account: account(of: profile, in: accounts), titleID: title)
            },
            current: { profile, title throws(PSNTrophiesFailure) in
                try await bridge.current(account: account(of: profile, in: accounts), titleID: title)
            },
            startOver: { profile in
                guard let account = try? await account(of: profile, in: accounts) else {
                    return
                }
                await bridge.startOver(account: account)
            }
        )
    }

    private static func account(
        of profile: ProfileID,
        in accounts: AccountService
    ) async throws(PSNTrophiesFailure) -> AccountID {
        guard let account = try? await accounts.accountID(of: profile.uuid) else {
            throw .signedOut
        }
        return account
    }
}
