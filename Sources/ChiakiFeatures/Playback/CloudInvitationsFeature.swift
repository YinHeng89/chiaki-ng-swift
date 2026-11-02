import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Owns the stream menu's Invitations panel during a PS5 cloud or PS Now stream: the game invitations friends sent,
/// and joining one through the cloud-assisted navigation command on PS5 cloud, or through the stream's INVITE deep
/// link on PS Now. Party invitations are left out: PSN forbids the party command on a cloud console.
///
/// Listing and joining each move through their own small state machine, and every completion carries the
/// operation that started it, so an answer to an older request never replaces a newer one.
@Reducer public struct CloudInvitationsFeature {
    /// Where the invitation list stands.
    public enum Listing: Equatable, Sendable {
        /// Nothing has been asked yet.
        case idle
        /// The operation with this id is asking PSN, showing the invitations listed before meanwhile.
        case loading(UUID, kept: [CloudGameInvitation])
        /// PSN answered with these invitations.
        case loaded([CloudGameInvitation])
        /// PSN could not be asked or did not answer.
        case failed(CloudInvitationFailure)
    }

    /// Where a join stands.
    public enum Joining: Equatable, Sendable {
        /// No join has been asked for.
        case idle
        /// The operation with this id is joining the invitation's session.
        case joining(invitation: String, operation: UUID)
        /// The cloud console reported that the game-intent command completed.
        case joined(String)
        /// The join of the invitation's session failed.
        case failed(invitation: String, CloudInvitationFailure)
    }

    /// The Invitations panel's state.
    @ObservableState public struct State: Equatable {
        /// The profile the cloud stream plays for.
        public var profile: ProfileID
        /// The game being streamed; only invitations to it are shown.
        public var product: ProductID
        /// The other generation's version of the game being streamed, whose invitations are shown too.
        public var otherVersion: ProductID?
        /// Where the invitation list stands.
        public var listing = Listing.idle
        /// Where the latest join stands.
        public var joining = Joining.idle
        /// The friend picker, while the player is inviting friends.
        public var invite: InviteFriendsFeature.State?
        /// The invitation the stream was started to accept, joined once the stream plays.
        public var pendingJoin: CloudGameInvitation?
        /// The invitation being joined because the stream was started to accept it, so a failure is announced
        /// rather than shown only in the panel.
        public var automaticJoin: String?

        /// Creates the state for a cloud stream.
        ///
        /// - Parameters:
        ///   - profile: The profile the stream plays for.
        ///   - product: The game being streamed.
        ///   - otherVersion: The other generation's version of the game being streamed.
        ///   - pendingJoin: The invitation to join once the stream plays, if the stream was started to accept one.
        public init(
            profile: ProfileID,
            product: ProductID,
            otherVersion: ProductID? = nil,
            pendingJoin: CloudGameInvitation? = nil
        ) {
            self.profile = profile
            self.product = product
            self.otherVersion = otherVersion
            self.pendingJoin = pendingJoin
        }

        /// Every invitation listed, or the ones listed before while the list is read again.
        public var invitations: [CloudGameInvitation] {
            switch listing {
            case .loaded(let invitations), .loading(_, let invitations):
                invitations
            case .idle, .failed:
                []
            }
        }

        /// The game invitations to the game being streamed or its other generation's version, newest first.
        public var shown: [CloudGameInvitation] {
            invitations.filter { invitation in
                invitation.kind == .game && (invitation.isFor(product: product) || otherVersion.map {
                    invitation.isFor(product: $0)
                } == true)
            }
        }

        /// The streamed game's title id, such as `PPSA01234_00`, when it is a PS5 game whose session friends can
        /// be invited to; PS4 games on PS Now play in old NP sessions the session manager does not know.
        public var invitableTitle: String? {
            let parts = product.rawValue.split(separator: "-")
            guard parts.count > 1, parts[1].hasPrefix("PPSA") else {
                return nil
            }
            return String(parts[1])
        }

        /// Whether a join is under way.
        public var isJoining: Bool {
            guard case .joining = joining else {
                return false
            }
            return true
        }
    }

    /// Events the Invitations panel handles.
    public enum Action: Equatable, Sendable {
        /// The panel opened, so the list is read again unless a read is under way.
        case appeared
        /// The player asked for the list again.
        case refresh
        /// PSN answered the listing started by an operation.
        case listed(UUID, Result<[CloudGameInvitation], CloudInvitationFailure>)
        /// The stream started playing, so an invitation it was started to accept is joined.
        case streamStarted
        /// The stream stopped playing, so its pending invitation requests end.
        case streamEnded
        /// The player chose to join an invitation.
        case join(String)
        /// The join started by an operation finished.
        case joinFinished(UUID, CloudInvitationFailure?)
        /// The player opened the friend picker.
        case inviteOpened
        /// The player closed the friend picker.
        case inviteClosed
        /// The friend picker acted.
        case invite(InviteFriendsFeature.Action)
        /// A request for the hosting stream.
        case delegate(Delegate)
    }

    /// Requests for the hosting stream.
    public enum Delegate: Equatable, Sendable {
        /// The cloud console completed the join command, so the menu can give way to the game.
        case joined
        /// The invitation the stream was started to accept could not be joined, for the reason given.
        case automaticJoinFailed(CloudInvitationFailure)
    }

    /// Cancellation identifiers for the panel's in-flight requests.
    public enum CancelID: Sendable {
        /// The latest listing.
        case listing
        /// The latest join.
        case join
    }

    /// Lists invitations through PSN and sends the INVITE deep link through the playing stream.
    @Dependency(\.streamSession) var client
    /// Generates operation identifiers.
    @Dependency(\.uuid) var uuid

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appeared:
                if case .loading = state.listing {
                    return .none
                }
                return list(&state)
            case .refresh:
                return list(&state)
            case let .listed(operation, result):
                guard case .loading(operation, _) = state.listing else {
                    return .none
                }
                switch result {
                case .success(let invitations):
                    state.listing = .loaded(invitations)
                case .failure(let failure):
                    state.listing = .failed(failure)
                }
                return .none
            case .streamStarted:
                guard let invitation = state.pendingJoin else {
                    return .none
                }
                state.pendingJoin = nil
                if !state.invitations.contains(where: { $0.id == invitation.id }) {
                    state.listing = .loaded(state.invitations + [invitation])
                }
                state.automaticJoin = invitation.id
                let joining = join(invitation.id, state: &state)
                guard state.isJoining else {
                    state.automaticJoin = nil
                    return .send(.delegate(.automaticJoinFailed(.cannotJoin)))
                }
                return joining
            case .streamEnded:
                state.joining = .idle
                state.automaticJoin = nil
                if case .loading = state.listing {
                    state.listing = .loaded(state.invitations)
                }
                return .merge(
                    .cancel(id: CancelID.join),
                    .cancel(id: CancelID.listing),
                    state.invite == nil
                        ? .none
                        : .send(.invite(.stopped))
                )
            case .inviteOpened:
                guard state.invite == nil, let title = state.invitableTitle else {
                    return .none
                }
                state.invite = InviteFriendsFeature.State(
                    profile: state.profile,
                    titleID: title,
                    platform: "PS5"
                )
                return .send(.invite(.appeared))
            case .inviteClosed:
                guard state.invite != nil else {
                    return .none
                }
                state.invite = nil
                return .merge(
                    .cancel(id: InviteFriendsFeature.CancelID.session),
                    .cancel(id: InviteFriendsFeature.CancelID.friends),
                    .cancel(id: InviteFriendsFeature.CancelID.send),
                    .cancel(id: InviteFriendsFeature.CancelID.link)
                )
            case .invite:
                return .none
            case .join(let invitation):
                return join(invitation, state: &state)
            case let .joinFinished(operation, failure):
                guard case .joining(let invitation, operation) = state.joining else {
                    return .none
                }
                let automatic = state.automaticJoin == invitation
                state.automaticJoin = nil
                guard let failure else {
                    let notifications = state.invitations.first {
                        $0.id == invitation
                    }?.notificationIDs ?? []
                    state.joining = .joined(invitation)
                    state.listing = state.listing.removing(invitation)
                    return .merge(
                        .send(.delegate(.joined)),
                        clear(notifications, profile: state.profile)
                    )
                }
                state.joining = .failed(invitation: invitation, failure)
                return automatic
                    ? .send(.delegate(.automaticJoinFailed(failure)))
                    : .none
            case .delegate:
                return .none
            }
        }
        .ifLet(\.invite, action: \.invite) {
            InviteFriendsFeature()
        }
    }

    private func list(_ state: inout State) -> Effect<Action> {
        let operation = uuid()
        state.listing = .loading(operation, kept: state.invitations)
        let profile = state.profile
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                let invitations = try await client.invitations(profile)
                await send(.listed(operation, .success(invitations)))
            } catch {
                await send(.listed(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.listing, cancelInFlight: true)
    }

    private func clear(_ notifications: [String], profile: ProfileID) -> Effect<Action> {
        guard !notifications.isEmpty else {
            return .none
        }
        return .run { [client] _ in
            try? await client.dismissNotifications(profile, notifications)
        }
    }

    /// Whether an invitation joins through PSN's game intent rather than through the stream: a SessionManager
    /// session, whose id is a UUID, needs the cloud console's game-intent path, while an old PS4 NP session joins
    /// through the stream's INVITE deep link.
    ///
    /// - Parameter invitation: The invitation.
    /// - Returns: `true` for a SessionManager session.
    static func joinsByGameIntent(_ invitation: CloudGameInvitation) -> Bool {
        UUID(uuidString: invitation.id) != nil
    }

    private func join(_ invitation: String, state: inout State) -> Effect<Action> {
        guard !state.isJoining,
              let chosen = state.shown.first(where: { $0.id == invitation && $0.joining == .joinable })
        else {
            return .none
        }
        let operation = uuid()
        state.joining = .joining(invitation: invitation, operation: operation)
        let profile = state.profile
        guard Self.joinsByGameIntent(chosen) else {
            return .run { [client] send in
                guard !chosen.invitationID.isEmpty else {
                    await send(.joinFinished(operation, .cannotJoin))
                    return
                }
                let sent = await client.joinInvitation(chosen.invitationID, chosen.id)
                await send(.joinFinished(
                    operation,
                    sent
                        ? nil
                        : .failed
                ))
            }
            .cancellable(id: CancelID.join, cancelInFlight: true)
        }
        return .run { [client] send in
            do throws(CloudInvitationFailure) {
                try await client.joinOnCloud(profile, chosen.id)
                await send(.joinFinished(operation, nil))
            } catch {
                await send(.joinFinished(operation, error))
            }
        }
        .cancellable(id: CancelID.join, cancelInFlight: true)
    }
}

extension CloudInvitationsFeature.Listing {
    /// The listing without an invitation that has just been joined, so it leaves the list before PSN is read again.
    ///
    /// - Parameter invitation: The joined invitation's session id.
    /// - Returns: The same listing without that invitation.
    func removing(_ invitation: String) -> Self {
        switch self {
        case .loaded(let invitations):
            .loaded(invitations.filter {
                $0.id != invitation
            })
        case .loading(let operation, let invitations):
            .loading(operation, kept: invitations.filter {
                $0.id != invitation
            })
        case .idle, .failed:
            self
        }
    }
}

extension StreamFeature {
    /// The Invitations panel state a stream starts with: one for a cloud stream, and none otherwise. An old PS4
    /// session joins through the stream's INVITE deep link and a SessionManager session through PSN's game intent,
    /// as ``CloudInvitationsFeature/joinsByGameIntent(_:)`` decides.
    ///
    /// - Parameter source: The stream's source.
    /// - Returns: The panel state, or `nil`.
    static func invitations(for source: StreamSource) -> CloudInvitationsFeature.State? {
        guard case .cloud(let request) = source else {
            return nil
        }
        return CloudInvitationsFeature.State(
            profile: request.profile,
            product: request.title.product,
            otherVersion: request.title.otherVersion,
            pendingJoin: request.joining
        )
    }
}
