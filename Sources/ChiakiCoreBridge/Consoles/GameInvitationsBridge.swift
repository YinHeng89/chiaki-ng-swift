import ChiakiBridge
import ChiakiModels
import CxxStdlib
import Foundation

/// Lists the game invitations friends sent an account, through the open core.
///
/// The listing talks to PSN and blocks a core thread, so it runs on a dispatch queue while the calling task
/// waits; cancelling the task cancels the core request.
public struct GameInvitationsBridge: Sendable {
    private final class Watcher: @unchecked Sendable {
        let continuation: AsyncStream<PSNAlert>.Continuation

        init(_ continuation: AsyncStream<PSNAlert>.Continuation) {
            self.continuation = continuation
        }
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// The game and party invitations and messages that arrive for an account while the stream is read.
    ///
    /// The core holds the account's PSN push channel open on a dispatch queue until the stream is cancelled, so
    /// PSN is asked nothing on a timer. The stream finishes when the watch ends, including when the channel cannot
    /// be opened.
    ///
    /// - Parameter account: The account.
    /// - Returns: Each alert as it arrives.
    public func alerts(account: AccountID) -> AsyncStream<PSNAlert> {
        AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let task = Task {
                let watcher = Watcher(continuation)
                _ = await CoreCancellation.run(qos: .utility) { request in
                    withExtendedLifetime(watcher) {
                        _ = chiaki_bridge.GameInvitationsBridge.watch(
                            request,
                            UsersBridge.vector(account),
                            { facts, context in
                                guard let facts, let context else {
                                    return
                                }
                                Unmanaged<Watcher>.fromOpaque(context).takeUnretainedValue().continuation
                                    .yield(.invitation(GameInvitationsBridge.invitation(of: facts.pointee)))
                            },
                            { facts, context in
                                guard let facts, let context else {
                                    return
                                }
                                Unmanaged<Watcher>.fromOpaque(context).takeUnretainedValue().continuation
                                    .yield(.message(GameInvitationsBridge.message(of: facts.pointee)))
                            },
                            { facts, context in
                                guard let facts, let context else {
                                    return
                                }
                                Unmanaged<Watcher>.fromOpaque(context).takeUnretainedValue().continuation
                                    .yield(.party(GameInvitationsBridge.party(of: facts.pointee)))
                            },
                            Unmanaged.passUnretained(watcher).toOpaque()
                        )
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// The model message alert of the bridge's facts.
    ///
    /// - Parameter facts: The bridge's facts.
    /// - Returns: The message alert.
    static func message(of facts: chiaki_bridge.MessageAlertFacts) -> PSNMessageAlert {
        PSNMessageAlert(
            sender: String(facts.sender),
            groupID: String(facts.group_id),
            threadID: String(facts.thread_id)
        )
    }

    /// The model party alert of the bridge's facts.
    ///
    /// - Parameter facts: The bridge's facts.
    /// - Returns: The party alert.
    static func party(of facts: chiaki_bridge.PartyAlertFacts) -> PSNPartyAlert {
        PSNPartyAlert(sender: String(facts.sender), sessionID: String(facts.session_id))
    }

    /// The account's game invitations, newest first.
    ///
    /// - Parameter account: The account.
    /// - Returns: The invitations.
    /// - Throws: The `ChiakiModels/CloudInvitationFailure` that stopped the listing.
    public func invitations(account: AccountID) async throws(CloudInvitationFailure)
        -> [CloudGameInvitation] {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.GameInvitationsBridge.invitations(
                request,
                UsersBridge.vector(account)
            ))
        }
        return try result.get()
    }

    /// Deletes notifications from the account's list.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - notificationIDs: The notifications, from `ChiakiModels/CloudGameInvitation/notificationIDs`.
    /// - Throws: The `ChiakiModels/CloudInvitationFailure` that stopped the change.
    public func dismiss(account: AccountID, notificationIDs: [String]) async throws(CloudInvitationFailure) {
        let result: Result<Void, CloudInvitationFailure> = await CoreCancellation
            .run(qos: .utility) { request in
                var ids = chiaki_bridge.Texts()
                for id in notificationIDs {
                    ids.push_back(std.string(id))
                }
                return Self.result(of: chiaki_bridge.GameInvitationsBridge.dismiss(
                    request,
                    UsersBridge.vector(account),
                    ids
                ))
                .map { _ in
                }
            }
        try result.get()
    }

    /// Sends a player session's game intent to the account's cloud console and waits for completion.
    ///
    /// - Parameters:
    ///   - account: The account playing the cloud game.
    ///   - sessionID: The invited player session.
    /// - Throws: The failure reported by PSN or the cloud console.
    public func join(account: AccountID, sessionID: String) async throws(CloudInvitationFailure) {
        let result: Result<Void, CloudInvitationFailure> = await CoreCancellation
            .run(qos: .utility) { request in
                let outcome = chiaki_bridge.GameInvitationsBridge.join(
                    request,
                    UsersBridge.vector(account),
                    std.string(sessionID)
                )
                if let refused = outcome.value {
                    return .failure(Self.failure(of: refused))
                }
                return .success(())
            }
        try result.get()
    }

    /// Has a home PS5 join a friend's party and waits for it, moving the party's voice chat to that PS5.
    /// PSN forbids the command on a cloud console, so there is no cloud form.
    ///
    /// - Parameters:
    ///   - account: The account the console belongs to.
    ///   - sessionID: The party session.
    ///   - console: The home PS5.
    /// - Throws: The failure reported by PSN or the console.
    public func joinParty(
        account: AccountID,
        sessionID: String,
        on console: HardwareID
    ) async throws(CloudInvitationFailure) {
        let result: Result<Void, CloudInvitationFailure> = await CoreCancellation
            .run(qos: .utility) { request in
                let outcome = chiaki_bridge.GameInvitationsBridge.join_party_on(
                    request,
                    UsersBridge.vector(account),
                    chiaki_bridge.Bytes(console.bytes),
                    std.string(sessionID)
                )
                if let refused = outcome.value {
                    return .failure(Self.failure(of: refused))
                }
                return .success(())
            }
        try result.get()
    }

    /// Has a home PS5 join an invitation's game session and waits for it.
    ///
    /// - Parameters:
    ///   - account: The account the console belongs to.
    ///   - sessionID: The invited game session.
    ///   - console: The home PS5.
    /// - Throws: The failure reported by PSN or the console.
    public func join(
        account: AccountID,
        sessionID: String,
        on console: HardwareID
    ) async throws(CloudInvitationFailure) {
        let result: Result<Void, CloudInvitationFailure> = await CoreCancellation
            .run(qos: .utility) { request in
                let outcome = chiaki_bridge.GameInvitationsBridge.join_on(
                    request,
                    UsersBridge.vector(account),
                    chiaki_bridge.Bytes(console.bytes),
                    std.string(sessionID)
                )
                if let refused = outcome.value {
                    return .failure(Self.failure(of: refused))
                }
                return .success(())
            }
        try result.get()
    }

    /// Preserves the reason a cloud invitation command failed across the core boundary.
    ///
    /// - Parameter failure: The core's join failure.
    /// - Returns: The failure displayed by the invitation feature.
    static func failure(of failure: libchiaking.consoles.InvitationJoinFailure) -> CloudInvitationFailure {
        switch failure.reason {
        case .invalid_session:
            .cannotJoin
        case .session_ended:
            .sessionEnded
        case .already_joined:
            .alreadyJoined
        case .full:
            .full
        case .cannot_join:
            .cannotJoin
        case .no_cloud_console:
            .noCloudConsole
        case .console_unavailable:
            .consoleUnavailable
        case .refused:
            .rejected
        case .failed:
            .failed
        case .timed_out:
            .timedOut
        case .cancelled:
            .cancelled
        case .unanswered:
            failure.unanswered.value.map { Self.failure(of: $0.reason) } ?? .unavailable
        }
    }

    /// The model result of an invitation listing.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The invitations or the failure.
    static func result(
        of outcome: chiaki_bridge.GameInvitationsOutcome
    ) -> Result<[CloudGameInvitation], CloudInvitationFailure> {
        switch outcome.kind() {
        case .answered:
            .success(outcome.invitations().map(invitation(of:)))
        case .unanswered:
            .failure(failure(of: outcome.why_unanswered().reason))
        case .refused:
            .failure(.unavailable)
        }
    }

    /// The model invitation of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The invitation.
    static func invitation(of facts: chiaki_bridge.GameInvitationFacts) -> CloudGameInvitation {
        CloudGameInvitation(
            id: String(facts.session_id),
            invitationID: String(facts.invitation_id),
            notificationIDs: facts.notification_ids.map {
                String($0)
            },
            inviter: String(facts.inviter),
            sessionName: String(facts.session_name),
            titleIDs: facts.title_ids.map {
                String($0)
            },
            sent: facts.sent_ms > 0
                ? Timestamp.date(milliseconds: facts.sent_ms)
                : nil,
            unread: facts.unread,
            players: Int(facts.players),
            maxPlayers: Int(facts.max_players),
            joining: joining(of: facts.joining),
            kind: kind(of: facts.kind)
        )
    }

    /// The model kind of the core's.
    ///
    /// - Parameter kind: The core's kind.
    /// - Returns: The model kind.
    static func kind(of kind: libchiaking.consoles.GameInvitation.Kind) -> CloudGameInvitation.Kind {
        switch kind {
        case .game:
            .game
        case .party:
            .party
        }
    }

    /// The model joining state of the core's.
    ///
    /// - Parameter joining: The core's state.
    /// - Returns: The model state.
    static func joining(of joining: libchiaking.consoles.GameInvitation.Joining) -> CloudGameInvitation
        .Joining {
        switch joining {
        case .joinable:
            .joinable
        case .already_joined:
            .alreadyJoined
        case .full:
            .full
        case .cannot_join:
            .cannotJoin
        }
    }

    /// The model failure of a request PSN did not answer.
    ///
    /// - Parameter reason: Why PSN did not answer.
    /// - Returns: The failure.
    static func failure(of reason: libchiaking.users.Unanswered.Reason) -> CloudInvitationFailure {
        switch reason {
        case .cancelled:
            .cancelled
        case .signed_out:
            .signedOut
        case .sign_in_expired, .store_access_lapsed, .remote_play_access_missing:
            .auth
        case .rejected:
            .rejected
        case .rate_limited, .unavailable, .malformed, .old_service_refused:
            .unavailable
        }
    }
}
