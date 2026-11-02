import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Invites friends to the game session the player streams in the cloud, from the stream menu's Invitations panel.
///
/// It finds the player's session for the streamed game and lists the player's friends; the player picks friends
/// and sends the invitations, or asks for a share link when anyone may join the session. While the player plays in
/// no session yet, it looks again every few seconds until the game creates one. The session, the friends, a send
/// and the link each move through their own small state machine, and every answer carries the operation that asked
/// for it, so a late answer never replaces a newer one.
@Reducer public struct InviteFriendsFeature {
    /// How long the picker waits before looking for the session again while the player plays in none.
    public static let lookAgainAfter = Duration.seconds(5)

    /// Where finding the player's session stands.
    public enum Session: Equatable, Sendable {
        /// The operation with this id is looking for it.
        case finding(UUID)
        /// The player plays in this session.
        case found(OwnGameSession)
        /// The player plays in no session of the game, so there is nothing to invite to yet.
        case none
        /// The session could not be looked up.
        case failed(CloudInvitationFailure)
    }

    /// Where the friends list stands.
    public enum Friends: Equatable, Sendable {
        /// The operation with this id is listing them.
        case loading(UUID)
        /// PSN listed these friends.
        case loaded([PSNFriend])
        /// The friends could not be listed.
        case failed(CloudInvitationFailure)
    }

    /// Where sending invitations stands.
    public enum Sending: Equatable, Sendable {
        /// Nothing is being sent.
        case idle
        /// The operation with this id is sending this many invitations.
        case sending(UUID, count: Int)
        /// PSN accepted this many invitations.
        case sent(Int)
        /// The invitations could not be sent.
        case failed(CloudInvitationFailure)
    }

    /// Where the share link stands.
    public enum Link: Equatable, Sendable {
        /// No link has been asked for.
        case idle
        /// The operation with this id is asking for it.
        case loading(UUID)
        /// PSN gave this link.
        case shown(SessionLink)
        /// The link could not be made.
        case failed(CloudInvitationFailure)
    }

    /// The picker's state.
    @ObservableState public struct State: Equatable {
        /// The profile the stream plays for.
        public var profile: ProfileID
        /// The streamed game's title id, such as `PPSA01234_00`.
        public var titleID: String
        /// The platform the game runs on, such as `PS5`.
        public var platform: String
        /// Where finding the player's session stands.
        public var session = Session.none
        /// Where the friends list stands.
        public var friends = Friends.loaded([])
        /// The friends picked to invite, by account id.
        public var selected: Set<String> = []
        /// Where sending stands.
        public var sending = Sending.idle
        /// Where the share link stands.
        public var link = Link.idle

        /// Creates the picker for a streamed game.
        ///
        /// - Parameters:
        ///   - profile: The profile the stream plays for.
        ///   - titleID: The game's title id.
        ///   - platform: The platform it runs on.
        public init(profile: ProfileID, titleID: String, platform: String) {
            self.profile = profile
            self.titleID = titleID
            self.platform = platform
        }

        /// The friends listed, or none while they load or after a failure.
        public var listed: [PSNFriend] {
            guard case .loaded(let friends) = friends else {
                return []
            }
            return friends
        }

        /// The session found, when there is one.
        public var found: OwnGameSession? {
            guard case .found(let session) = session else {
                return nil
            }
            return session
        }

        /// Whether the picked friends can be invited now.
        public var canSend: Bool {
            guard found != nil, !selected.isEmpty else {
                return false
            }
            if case .sending = sending {
                return false
            }
            return true
        }

        /// Whether the share link can be asked for: the session lets anyone join.
        public var canShare: Bool {
            guard found?.openToAnyone == true else {
                return false
            }
            if case .loading = link {
                return false
            }
            return true
        }
    }

    /// What the picker can do.
    public enum Action: Equatable, Sendable {
        /// The picker opened, so the session and the friends are read.
        case appeared
        /// The session lookup started by an operation finished.
        case sessionFound(UUID, Result<OwnGameSession?, CloudInvitationFailure>)
        /// The wait after finding no session ended, so the session is looked up again.
        case sessionWaitEnded
        /// The friends listing started by an operation finished.
        case friendsListed(UUID, Result<[PSNFriend], CloudInvitationFailure>)
        /// The player picked or unpicked a friend.
        case toggled(String)
        /// The player asked to send the invitations.
        case send
        /// The send started by an operation finished.
        case sent(UUID, CloudInvitationFailure?)
        /// The player asked for a share link.
        case share
        /// The link asked for by an operation arrived.
        case linkMade(UUID, Result<SessionLink, CloudInvitationFailure>)
        /// The stream stopped or the picker closed, so its requests end.
        case stopped
    }

    /// Cancellation identifiers for the picker's requests.
    public enum CancelID: Sendable {
        /// The session lookup, or the wait before looking again.
        case session
        /// The friends listing.
        case friends
        /// A send.
        case send
        /// The share link.
        case link
    }

    /// Reads friends and sessions and sends invitations through PSN.
    @Dependency(\.streamSession) var client
    /// Generates operation identifiers.
    @Dependency(\.uuid) var uuid
    /// Paces looking for the session again.
    @Dependency(\.continuousClock) var clock

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                return .merge(findSession(&state), listFriends(&state))
            case let .sessionFound(operation, result):
                guard case .finding(operation) = state.session else {
                    return .none
                }
                switch result {
                case .success(.some(let session)):
                    state.session = .found(session)
                    return .none
                case .success(.none):
                    state.session = .none
                    return waitForSession()
                case .failure(let failure):
                    state.session = .failed(failure)
                    return .none
                }
            case .sessionWaitEnded:
                guard state.session == .none else {
                    return .none
                }
                return findSession(&state)
            case let .friendsListed(operation, result):
                guard case .loading(operation) = state.friends else {
                    return .none
                }
                switch result {
                case .success(let friends):
                    state.friends = .loaded(friends)
                    state.selected.formIntersection(friends.map(\.id))
                case .failure(let failure):
                    state.friends = .failed(failure)
                }
                return .none
            case .toggled(let id):
                guard state.listed.contains(where: { $0.id == id }) else {
                    return .none
                }
                if state.selected.contains(id) {
                    state.selected.remove(id)
                } else {
                    state.selected.insert(id)
                }
                if case .sending = state.sending {
                    return .none
                }
                state.sending = .idle
                return .none
            case .send:
                return send(&state)
            case let .sent(operation, failure):
                guard case .sending(operation, let count) = state.sending else {
                    return .none
                }
                if let failure {
                    state.sending = .failed(failure)
                } else {
                    state.sending = .sent(count)
                    state.selected = []
                }
                return .none
            case .share:
                return share(&state)
            case let .linkMade(operation, result):
                guard case .loading(operation) = state.link else {
                    return .none
                }
                switch result {
                case .success(let link):
                    state.link = .shown(link)
                case .failure(let failure):
                    state.link = .failed(failure)
                }
                return .none
            case .stopped:
                if case .finding = state.session {
                    state.session = .none
                }
                if case .loading = state.friends {
                    state.friends = .loaded([])
                }
                if case .sending = state.sending {
                    state.sending = .idle
                }
                if case .loading = state.link {
                    state.link = .idle
                }
                return .merge(
                    .cancel(id: CancelID.session),
                    .cancel(id: CancelID.friends),
                    .cancel(id: CancelID.send),
                    .cancel(id: CancelID.link)
                )
            }
        }
    }

    private func findSession(_ state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.session = .finding(operation)
        state.link = .idle
        let profile = state.profile
        let title = state.titleID
        let platform = state.platform
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                let session = try await client.ownGameSession(profile, title, platform)
                await send(.sessionFound(operation, .success(session)))
            } catch {
                await send(.sessionFound(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.session, cancelInFlight: true)
    }

    private func waitForSession() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.lookAgainAfter)
            await send(.sessionWaitEnded)
        }
        .cancellable(id: CancelID.session, cancelInFlight: true)
    }

    private func listFriends(_ state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.friends = .loading(operation)
        let profile = state.profile
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                let friends = try await client.friends(profile)
                await send(.friendsListed(operation, .success(friends)))
            } catch {
                await send(.friendsListed(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.friends, cancelInFlight: true)
    }

    private func send(_ state: inout State) -> Effect<Action> {
        guard state.canSend, let session = state.found else {
            return .none
        }
        let operation = uuid()
        let invitees = state.listed.map(\.id).filter(state.selected.contains)
        state.sending = .sending(operation, count: invitees.count)
        let profile = state.profile
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                try await client.inviteFriends(profile, .game(session.id), invitees)
                await send(.sent(operation, nil))
            } catch {
                await send(.sent(operation, error))
            }
        }
        .cancellable(id: CancelID.send, cancelInFlight: true)
    }

    private func share(_ state: inout State) -> Effect<Action> {
        guard state.canShare, let session = state.found else {
            return .none
        }
        let operation = uuid()
        state.link = .loading(operation)
        let profile = state.profile
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                let link = try await client.shareLink(profile, session.id)
                await send(.linkMade(operation, .success(link)))
            } catch {
                await send(.linkMade(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.link, cancelInFlight: true)
    }
}
