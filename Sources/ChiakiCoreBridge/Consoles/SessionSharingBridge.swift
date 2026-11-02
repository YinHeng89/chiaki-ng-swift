import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Lists an account's PSN friends, finds the game session it plays in, asks for a share link and sends
/// invitations, through the open core.
///
/// Each call talks to PSN and blocks a core thread, so it runs on a dispatch queue while the calling task waits;
/// cancelling the task cancels the core request.
public struct SessionSharingBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// The account's friends, online friends first.
    ///
    /// - Parameter account: The account.
    /// - Returns: The friends.
    /// - Throws: The `ChiakiModels/CloudInvitationFailure` that stopped the listing.
    public func friends(account: AccountID) async throws(CloudInvitationFailure) -> [PSNFriend] {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.SessionSharingBridge.friends(request, UsersBridge.vector(account))
            switch outcome.kind() {
            case .listed:
                return Result<[PSNFriend], CloudInvitationFailure>.success(outcome.friends().map { facts in
                    PSNFriend(
                        id: String(facts.account_id),
                        onlineID: String(facts.online_id),
                        avatarURL: URL(string: String(facts.avatar_url)),
                        online: facts.online,
                        playing: String(facts.playing)
                    )
                })
            case .unanswered:
                return .failure(GameInvitationsBridge.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// The game session the account plays in for a title.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - titleID: The title, such as `PPSA01234_00`.
    ///   - platform: The platform it runs on, such as `PS5`.
    /// - Returns: The session, or `nil` when the account plays in none for the title.
    /// - Throws: The `ChiakiModels/CloudInvitationFailure` that stopped the lookup.
    public func ownGameSession(
        account: AccountID,
        titleID: String,
        platform: String
    ) async throws(CloudInvitationFailure) -> OwnGameSession? {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.SessionSharingBridge.own_game_session(
                request,
                UsersBridge.vector(account),
                std.string(titleID),
                std.string(platform)
            )
            switch outcome.kind() {
            case .found:
                let facts = outcome.session()
                return Result<OwnGameSession?, CloudInvitationFailure>.success(OwnGameSession(
                    id: String(facts.session_id),
                    name: String(facts.name),
                    players: Int(facts.players),
                    maxPlayers: Int(facts.max_players),
                    openToAnyone: facts.open_to_anyone
                ))
            case .missing:
                return .success(nil)
            case .unanswered:
                return .failure(GameInvitationsBridge.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// A link friends can open to join a game session.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - sessionID: The session.
    /// - Returns: The link.
    /// - Throws: The `ChiakiModels/CloudInvitationFailure` that stopped the request.
    public func shareLink(account: AccountID,
                          sessionID: String) async throws(CloudInvitationFailure) -> SessionLink {
        let result = await CoreCancellation.run(qos: .utility) { request in
            let outcome = chiaki_bridge.SessionSharingBridge.share(
                request,
                UsersBridge.vector(account),
                std.string(sessionID)
            )
            switch outcome.kind() {
            case .linked:
                let link = outcome.link()
                guard let url = URL(string: String(link.url)) else {
                    return Result<SessionLink, CloudInvitationFailure>.failure(.unavailable)
                }
                return .success(SessionLink(url: url, imageURL: URL(string: String(link.image_url))))
            case .unanswered:
                return .failure(GameInvitationsBridge.failure(of: outcome.why_unanswered().reason))
            case .closed:
                return .failure(.unavailable)
            }
        }
        return try result.get()
    }

    /// Invites friends to a game session or a party.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - target: The session or party.
    ///   - friendIDs: The friends' account ids.
    /// - Throws: The `ChiakiModels/CloudInvitationFailure` that stopped the invitations.
    public func invite(
        account: AccountID,
        target: InvitationTarget,
        friendIDs: [String]
    ) async throws(CloudInvitationFailure) {
        let result: Result<Void, CloudInvitationFailure> = await CoreCancellation
            .run(qos: .utility) { request in
                var ids = chiaki_bridge.Texts()
                for id in friendIDs {
                    ids.push_back(std.string(id))
                }
                let party: Bool
                let session: String
                switch target {
                case .game(let id):
                    party = false
                    session = id
                case .party(let id):
                    party = true
                    session = id
                }
                let refused = chiaki_bridge.SessionSharingBridge.invite(
                    request,
                    UsersBridge.vector(account),
                    party,
                    std.string(session),
                    ids
                )
                if let refused = refused.value {
                    return .failure(GameInvitationsBridge.failure(of: refused.reason))
                }
                return .success(())
            }
        try result.get()
    }
}
