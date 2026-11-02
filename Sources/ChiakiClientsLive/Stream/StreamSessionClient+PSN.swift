import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels

extension StreamSessionClient {
    /// Returns this client with the PlayStation Network requests going through the core, finding each
    /// profile's PSN account in the app's accounts, and the cloud captures saved through the app's capture
    /// saver.
    ///
    /// - Parameters:
    ///   - accounts: The app's account service.
    ///   - captures: The one capture saver.
    /// - Returns: A copy whose invitation, friend, alert and capture operations are live.
    public func reachingPSN(through accounts: AccountService, captures: CloudCaptureSaver) -> Self {
        let bridge = GameInvitationsBridge()
        let sharing = SessionSharingBridge()
        var client = self
        client.saveCapture = { capture, followsPlayStation in
            await captures.save(capture, followsPlayStation: followsPlayStation)
        }
        client.resumeCaptures = {
            await captures.resume()
        }
        client.invitations = { profile throws(CloudInvitationFailure) in
            try await bridge.invitations(account: Self.account(of: profile, in: accounts))
        }
        client.joinOnCloud = { profile, session throws(CloudInvitationFailure) in
            try await bridge.join(account: Self.account(of: profile, in: accounts), sessionID: session)
        }
        client.joinParty = { profile, session, console throws(CloudInvitationFailure) in
            try await bridge.joinParty(
                account: Self.account(of: profile, in: accounts),
                sessionID: session,
                on: console
            )
        }
        client.joinOn = { profile, session, console throws(CloudInvitationFailure) in
            try await bridge.join(
                account: Self.account(of: profile, in: accounts),
                sessionID: session,
                on: console
            )
        }
        client.dismissNotifications = { profile, ids throws(CloudInvitationFailure) in
            try await bridge.dismiss(account: Self.account(of: profile, in: accounts), notificationIDs: ids)
        }
        client.psnAlerts = { profile in
            Self.alerts(of: profile, through: bridge, in: accounts)
        }
        client.friends = { profile throws(CloudInvitationFailure) in
            try await sharing.friends(account: Self.account(of: profile, in: accounts))
        }
        client.ownGameSession = { profile, title, platform throws(CloudInvitationFailure) in
            try await sharing.ownGameSession(
                account: Self.account(of: profile, in: accounts),
                titleID: title,
                platform: platform
            )
        }
        client.shareLink = { profile, session throws(CloudInvitationFailure) in
            try await sharing.shareLink(account: Self.account(of: profile, in: accounts), sessionID: session)
        }
        client.inviteFriends = { profile, target, friends throws(CloudInvitationFailure) in
            try await sharing.invite(
                account: Self.account(of: profile, in: accounts),
                target: target,
                friendIDs: friends
            )
        }
        return client
    }

    private static func alerts(
        of profile: ProfileID,
        through bridge: GameInvitationsBridge,
        in accounts: AccountService
    ) -> AsyncStream<PSNAlert> {
        AsyncStream { continuation in
            let task = Task {
                guard let account = try? await account(of: profile, in: accounts) else {
                    continuation.finish()
                    return
                }
                for await alert in bridge.alerts(account: account) {
                    continuation.yield(alert)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func account(
        of profile: ProfileID,
        in accounts: AccountService
    ) async throws(CloudInvitationFailure) -> AccountID {
        guard let account = try? await accounts.accountID(of: profile.uuid) else {
            throw .signedOut
        }
        return account
    }
}
