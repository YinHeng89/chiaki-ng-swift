import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels

extension PSNMessagesClient {
    /// The client over the core, finding each profile's PSN account in the app's accounts.
    ///
    /// - Parameter accounts: The app's account service.
    /// - Returns: The live client.
    public static func live(_ accounts: AccountService) -> Self {
        let bridge = PSNMessagesBridge()
        return Self(
            conversations: { profile throws(PSNMessagesFailure) in
                try await bridge.conversations(account: account(of: profile, in: accounts))
            },
            thread: { profile, group, thread, before throws(PSNMessagesFailure) in
                try await bridge.thread(
                    account: account(of: profile, in: accounts),
                    groupID: group,
                    threadID: thread,
                    before: before
                )
            },
            send: { profile, group, thread, text throws(PSNMessagesFailure) in
                try await bridge.send(
                    account: account(of: profile, in: accounts),
                    groupID: group,
                    threadID: thread,
                    text: text
                )
            },
            markRead: { profile, group, thread, message throws(PSNMessagesFailure) in
                try await bridge.markRead(
                    account: account(of: profile, in: accounts),
                    groupID: group,
                    threadID: thread,
                    messageID: message
                )
            }
        )
    }

    private static func account(
        of profile: ProfileID,
        in accounts: AccountService
    ) async throws(PSNMessagesFailure) -> AccountID {
        guard let account = try? await accounts.accountID(of: profile.uuid) else {
            throw .signedOut
        }
        return account
    }
}
