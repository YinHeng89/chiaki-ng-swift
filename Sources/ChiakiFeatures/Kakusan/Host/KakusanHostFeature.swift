import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation

/// Hosts a shared session on a console stream: arming, invitations, replies, verification, seats and naming
/// guests' devices.
///
/// The console stream forwards its lifecycle as ``Action/armed`` and ``Action/disarmed``; the feature arms
/// and disarms through `ChiakiClients/KakusanClient`. Events arrive only from the arming effect, which
/// disarming and re-arming cancel, so a finished stream's events never reach the next one.
///
/// Each guest is a `ChiakiModels/KakusanHostAttempt` machine; every answer carries the id of the operation
/// that asked. The invitation card and the naming card are ``Destination`` presentations. Seats are asked of the
/// couch through `Action/Delegate`.
@Reducer
public struct KakusanHostFeature {
    /// How long failed pairings are counted towards the cooldown.
    static let failureWindow: TimeInterval = 600
    /// How many failed pairings start the cooldown.
    static let failureLimit = 3
    /// How long invitations are refused after too many failed pairings.
    static let cooldown: TimeInterval = 300
    /// How many events are kept for a guest whose invitation has not come back yet.
    static let earlyEventLimit = 16

    /// Whether this device can host.
    public enum Hosting: Equatable, Sendable {
        /// Hosting works.
        case available
        /// Hosting failed and invitations are refused.
        case unavailable(KakusanError)
    }

    /// One guest's attempt and what is known about their device.
    public struct Guest: Equatable, Sendable, Identifiable {
        /// The attempt.
        public var attempt: KakusanHostAttempt
        /// The remembered device the host said the invitation is for.
        public var expected: String?
        /// How the guest's device was recognised.
        public var recognition: KakusanRecognition?
        /// The operation importing the guest's reply.
        public var replyOperation: UUID?

        /// Creates a guest entry.
        ///
        /// - Parameter attempt: The attempt.
        public init(attempt: KakusanHostAttempt) {
            self.attempt = attempt
        }

        /// The attempt's id.
        public var id: UUID {
            attempt.id
        }

        /// The device's remembered name.
        public var name: String? {
            recognition?.name
        }

        /// Whether the guest's verified device can be remembered.
        public var canRemember: Bool {
            guard attempt.peer != nil, attempt.milestone >= .verified else {
                return false
            }
            if case .recognised = recognition {
                return false
            }
            return true
        }
    }

    /// The host's state.
    @ObservableState
    public struct State: Equatable, Sendable {
        /// Whether hosting works.
        public internal(set) var hosting = Hosting.available
        /// Every guest's attempt.
        public internal(set) var guests: IdentifiedArrayOf<Guest> = []
        /// The card shown over the stream.
        @Presents public var destination: Destination.State?
        /// The seats the session last reported.
        public internal(set) var seats: KakusanSeatSnapshot?
        /// The seats local players hold.
        public var localSeats = 1
        /// The remembered devices.
        public internal(set) var peers: [KakusanPeer] = []
        /// When recent pairings failed.
        public internal(set) var pairingFailures: [Date] = []
        /// When invitations are allowed again after too many failed pairings.
        public internal(set) var cooldownUntil: Date?
        /// Events for guests whose invitation has not come back yet.
        public internal(set) var early: [KakusanGuestID: [KakusanHostEvent]] = [:]

        /// Creates an idle host.
        public init() {}

        /// The attempt whose invitation card is shown.
        public var presented: UUID? {
            guard case .invite(let invite) = destination else {
                return nil
            }
            return invite.guest
        }

        /// The guest whose invitation card is shown.
        public var presentedGuest: Guest? {
            presented.flatMap { guests[id: $0] }
        }

        /// The guest a pasted reply most likely answers: the shown one if it waits, else the first that waits.
        public var awaitingReply: Guest? {
            let waiting = guests.filter { guest in
                if case .invitation = guest.attempt.phase {
                    return true
                }
                return false
            }
            return waiting.first { $0.id == presented } ?? waiting.first
        }

        /// The seats remote players hold or have reserved.
        public var remoteReservations: Int {
            guard let seats else {
                return 0
            }
            return seats.remote + seats.reserved
        }

        /// The names the host can say an invitation is for; `nil` stands for a new device.
        public var expectations: [String?] {
            peers.isEmpty
                ? []
                : [nil] + peers.map(\.nickname)
        }

        /// Whether invitations are open: hosting works and no cooldown is running.
        public var invitesOpen: Bool {
            hosting == .available && cooldownUntil == nil
        }

        /// The guest an id in the shared session belongs to.
        ///
        /// - Parameter id: The guest's id in the session.
        /// - Returns: The guest, if any.
        public func guest(for id: KakusanGuestID) -> Guest? {
            guests.first { $0.attempt.guest == id }
        }

        /// Whether a new invitation can be created at a moment.
        ///
        /// - Parameter now: The moment.
        /// - Returns: `true` when hosting works and no cooldown runs at `now`.
        public func canInvite(now: Date) -> Bool {
            guard hosting == .available else {
                return false
            }
            guard let cooldownUntil else {
                return true
            }
            return now >= cooldownUntil
        }

        /// Shows the invitation card for its attempt's current phase, closing it when the attempt is gone.
        mutating func followPresented() {
            guard case .invite(var invite) = destination else {
                return
            }
            guard let guest = guests[id: invite.guest] else {
                destination = nil
                return
            }
            invite.follow(guest.attempt.phase, expectations: expectations)
            destination = .invite(invite)
        }
    }

    /// The cards the host shows.
    @Reducer
    public enum Destination {
        /// One guest's invitation card.
        case invite(KakusanInviteFeature)
        /// Naming a verified guest's device.
        case remember(KakusanRememberFeature)
    }

    /// Everything the host reacts to.
    public enum Action: Equatable, Sendable {
        /// The console stream started; arm hosting.
        case armed
        /// The console stream ended; disarm.
        case disarmed
        /// The armed host reported an event.
        case event(KakusanHostEvent)
        /// Create an invitation.
        case invite
        /// An invitation came back.
        case inviteResult(UUID, operation: UUID, Result<KakusanGuestID, KakusanError>)
        /// Show a guest's invitation card, or close it.
        case present(UUID?)
        /// Say which remembered device an invitation is for.
        case expect(UUID, String?)
        /// Import a reply for a guest.
        case submitReply(UUID, String)
        /// A reply was opened from a file.
        case replyOpened(String)
        /// A reply import came back.
        case replyResult(UUID, operation: UUID, Result<KakusanGuestID, KakusanError>)
        /// Approve a guest whose reply matched.
        case approve(UUID)
        /// An approval came back.
        case approvalResult(UUID, operation: UUID, KakusanCommandOutcome)
        /// Check a guest's code.
        case submitCode(UUID, String)
        /// A code check came back.
        case codeResult(UUID, operation: UUID, KakusanCommandOutcome)
        /// Cancel a guest's attempt.
        case cancel(UUID)
        /// Remove a guest the couch let go.
        case removeGuest(KakusanGuestID)
        /// Close a guest's card, dropping an ended attempt.
        case dismiss(UUID)
        /// A guest's invitation expired.
        case expire(UUID)
        /// A guest's device was recognised.
        case recognised(UUID, KakusanPublicKey, KakusanRecognition)
        /// The remembered devices were loaded.
        case peersLoaded([KakusanPeer])
        /// The couch could not seat a guest.
        case seatDeclined(KakusanGuestID)
        /// The couch seated a guest.
        case giveSeat(KakusanGuestID, controllerType: UInt8, accountID: Data?)
        /// The number of local players changed.
        case localSeatsChanged(Int)
        /// A command was refused.
        case commandFailed(KakusanHostCommand, KakusanError)
        /// The pairing cooldown ran out.
        case cooldownEnded
        /// Name a verified guest's device.
        case startRemembering(UUID)
        /// A presented card.
        case destination(PresentationAction<Destination.Action>)
        /// What the console stream is told.
        case delegate(Delegate)
    }

    /// What the host asks of the console stream's couch.
    public enum Delegate: Equatable, Sendable {
        /// Find a seat for a guest.
        case claimSeat(KakusanRemotePlayer)
        /// Hold a pad for a guest.
        case reserveSeat(KakusanRemotePlayer, pad: UInt8)
        /// Show a guest on a pad.
        case showSeat(KakusanRemotePlayer, pad: UInt8)
        /// Free a guest's seat.
        case releaseSeat(KakusanGuestID)
        /// Show a notice about remote players.
        case notice(KakusanHostNotice)
    }

    private enum CancelID: Hashable {
        case arming
        case cooldown
        case expiry(UUID)
    }

    @Dependency(\.kakusan) private var kakusan
    @Dependency(\.uuid) private var uuid
    @Dependency(\.date) private var date
    @Dependency(\.continuousClock) private var clock

    /// Creates the reducer.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            reduce(&state, action)
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination.body
        }
        Reduce { state, _ in
            state.followPresented()
            return .none
        }
    }

    private func reduce(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .armed:
            return arm(&state)
        case .disarmed:
            return disarm(&state)
        case .event(let event):
            return handle(event, in: &state)
        case .invite:
            return invite(&state)
        case let .inviteResult(id, operation, result):
            return invited(id, operation, result, in: &state)
        case .present(let id):
            return present(id, in: &state)
        case let .expect(id, name):
            return expect(id, name, in: &state)
        case let .submitReply(id, text):
            return submitReply(id, text, in: &state)
        case .replyOpened(let text):
            return replyOpened(text, in: &state)
        case let .replyResult(id, operation, result):
            return replyImported(id, operation, result, in: &state)
        case .approve(let id):
            return approve(id, in: &state)
        case let .approvalResult(id, operation, outcome):
            return approved(id, operation, outcome, in: &state)
        case let .giveSeat(guest, controllerType, accountID):
            return giveSeat(guest, controllerType: controllerType, accountID: accountID)
        case let .submitCode(id, text):
            return submitCode(id, text, in: &state)
        case let .codeResult(id, operation, outcome):
            return apply(.code(.result(operation, outcome.error)), to: id, in: &state)
        case .cancel(let id):
            return cancel(id, in: &state)
        case .removeGuest(let guest):
            return removeGuest(guest, in: &state)
        case .dismiss(let id):
            return dismiss(id, in: &state)
        case .expire(let id):
            return apply(.invitation(.expired), to: id, in: &state)
        case let .recognised(id, key, recognition):
            return recognised(id, key, recognition, in: &state)
        case .peersLoaded(let peers):
            return peersLoaded(peers, in: &state)
        case .seatDeclined(let guest):
            return seat(.consoleJoinFailed, for: guest, in: &state)
        case .localSeatsChanged(let count):
            return localSeatsChanged(count, in: &state)
        case let .commandFailed(command, error):
            return commandFailed(command, error, in: &state)
        case .cooldownEnded:
            return cooldownEnded(&state)
        case .startRemembering(let id):
            return startRemembering(id, in: &state)
        case let .destination(.presented(.invite(.delegate(request)))):
            return inviteRequested(request, in: &state)
        case let .destination(.presented(.remember(.delegate(.finished(saved))))):
            return remembered(saved, in: &state)
        case .destination, .delegate:
            return .none
        }
    }
}

extension KakusanHostFeature {
    private func giveSeat(_ guest: KakusanGuestID, controllerType: UInt8,
                          accountID: Data?) -> Effect<Action> {
        command(.giveSeat(
            guest,
            preferred: nil,
            controllerType: controllerType,
            accountID: accountID
        ))
    }

    private func peersLoaded(_ peers: [KakusanPeer], in state: inout State) -> Effect<Action> {
        state.peers = peers
        return .none
    }

    private func cooldownEnded(_ state: inout State) -> Effect<Action> {
        state.cooldownUntil = nil
        return .none
    }

    private func present(_ id: UUID?, in state: inout State) -> Effect<Action> {
        guard let id, state.guests[id: id] != nil else {
            state.destination = nil
            return .none
        }
        state.destination = .invite(KakusanInviteFeature.State(guest: id))
        return .none
    }

    private func replyOpened(_ text: String, in state: inout State) -> Effect<Action> {
        guard let guest = state.awaitingReply else {
            return .none
        }
        if state.presented != guest.id {
            state.destination = .invite(KakusanInviteFeature.State(guest: guest.id))
        }
        return submitReply(guest.id, text, in: &state)
    }

    private func approved(
        _ id: UUID,
        _ operation: UUID,
        _ outcome: KakusanCommandOutcome,
        in state: inout State
    ) -> Effect<Action> {
        let effect = apply(.approval(.result(operation, outcome.error)), to: id, in: &state)
        guard let guest = state.guests[id: id]?.attempt.guest else {
            return effect
        }
        return .merge(effect, requestSeat(guest, in: &state))
    }

    private func removeGuest(_ guest: KakusanGuestID, in state: inout State) -> Effect<Action> {
        guard let id = state.guest(for: guest)?.id else {
            return .none
        }
        return cancel(id, in: &state)
    }

    private func recognised(
        _ id: UUID,
        _ key: KakusanPublicKey,
        _ recognition: KakusanRecognition,
        in state: inout State
    ) -> Effect<Action> {
        guard state.guests[id: id]?.attempt.peer?.publicKey == key else {
            return .none
        }
        state.guests[id: id]?.recognition = recognition
        return .none
    }

    /// Arms hosting for a console stream that has started.
    ///
    /// The stream calls this directly when its session starts, so hosting is armed in the same reduction.
    ///
    /// - Parameter state: The host's state.
    /// - Returns: The effect that arms the native host and forwards its events.
    public func arm(_ state: inout State) -> Effect<Action> {
        let ended = reset(&state)
        let configuration = KakusanHostConfiguration(
            capacity: KakusanHostAttempt.capacity,
            localSeats: state.localSeats
        )
        return .merge(
            ended,
            .run { [kakusan] send in
                let (events, feed) = AsyncStream.makeStream(of: KakusanHostEvent.self)
                await kakusan.arm(configuration) { event in
                    feed.yield(event)
                }
                let own = (try? await kakusan.loadSettings().stunServers) ?? []
                if case .failure(let error) = await kakusan.useStunServers(own) {
                    await send(.event(.unavailable(error)))
                }
                for await event in events {
                    await send(.event(event))
                }
            }
            .cancellable(id: CancelID.arming, cancelInFlight: true)
        )
    }

    /// Disarms hosting for a console stream that has ended.
    ///
    /// - Parameter state: The host's state.
    /// - Returns: The effect that ends any guests and disarms the native host.
    public func disarm(_ state: inout State) -> Effect<Action> {
        let ended = reset(&state)
        return .merge(ended, .cancel(id: CancelID.arming), .run { [kakusan] _ in
            await kakusan.disarm()
        })
    }

    private func reset(_ state: inout State) -> Effect<Action> {
        let timers = state.guests.ids.map { Effect<Action>.cancel(id: CancelID.expiry($0)) }
        state = State()
        return .merge(timers + [.cancel(id: CancelID.cooldown)])
    }

    private func inviteRequested(_ request: KakusanInviteFeature.Action.Delegate,
                                 in state: inout State) -> Effect<Action> {
        guard let id = state.presented else {
            return .none
        }
        switch request {
        case .expect(let name):
            return expect(id, name, in: &state)
        case .submitReply(let text):
            return submitReply(id, text, in: &state)
        case .submitCode(let text):
            return submitCode(id, text, in: &state)
        case .cancel:
            return cancel(id, in: &state)
        case .close:
            return dismiss(id, in: &state)
        case .createNew:
            guard state.canInvite(now: date.now) else {
                return .none
            }
            let dismissed = dismiss(id, in: &state)
            return .merge(dismissed, invite(&state))
        }
    }

    private func startRemembering(_ id: UUID, in state: inout State) -> Effect<Action> {
        guard let guest = state.guests[id: id], let peer = guest.attempt.peer, guest.canRemember else {
            return .none
        }
        let name = guest.expected ?? ""
        state.destination = .remember(KakusanRememberFeature.State(
            subject: .verified(peer),
            name: name,
            normalised: kakusan.nickname(name)
        ))
        return .none
    }

    private func remembered(_ saved: KakusanPeer?, in state: inout State) -> Effect<Action> {
        state.destination = nil
        guard let saved else {
            return .none
        }
        for guest in state.guests where guest.attempt.peer?.publicKey == saved.publicKey {
            state.guests[id: guest.id]?.recognition = .recognised(saved)
        }
        return loadPeers()
    }

    private func loadPeers() -> Effect<Action> {
        .run { [kakusan] send in
            await send(.peersLoaded((try? await kakusan.peers()) ?? []))
        }
    }

    private func command(_ command: KakusanHostCommand) -> Effect<Action> {
        .run { [kakusan] send in
            if case .rejected(let error) = await kakusan.send(command) {
                await send(.commandFailed(command, error))
            }
        }
    }

    private func quietCommand(_ command: KakusanHostCommand) -> Effect<Action> {
        .run { [kakusan] _ in
            _ = await kakusan.send(command)
        }
    }

    private func invite(_ state: inout State) -> Effect<Action> {
        guard state.canInvite(now: date.now) else {
            return .none
        }
        let id = uuid()
        let operation = uuid()
        let localSeats = state.localSeats
        state.guests.append(Guest(attempt: KakusanHostAttempt(id: id, operation: operation)))
        state.destination = .invite(KakusanInviteFeature.State(guest: id))
        return .run { [kakusan] send in
            await send(.peersLoaded((try? await kakusan.peers()) ?? []))
            let tuning = ((try? await kakusan.loadSettings()) ?? KakusanSettings()).tuning.clamped()
            _ = await kakusan.send(.setTuning(tuning))
            if case .rejected(let error) = await kakusan.send(.setLocalSeats(localSeats)) {
                await send(.inviteResult(id, operation: operation, .failure(error)))
                return
            }
            await send(.inviteResult(id, operation: operation, await kakusan.invite()))
        }
    }

    private func invited(
        _ id: UUID,
        _ operation: UUID,
        _ result: Result<KakusanGuestID, KakusanError>,
        in state: inout State
    ) -> Effect<Action> {
        switch result {
        case .success(let guest):
            let (transition, effect) = transition(.invitation(.invited(operation, guest)), to: id, in: &state)
            guard transition == .accepted else {
                return .merge(effect, quietCommand(.remove(guest)))
            }
            let replay = state.early.removeValue(forKey: guest) ?? []
            return .merge([effect] + replay.map { handle($0, in: &state) })
        case .failure(let error):
            return apply(.invitation(.failed(operation, error)), to: id, in: &state)
        }
    }

    private func expect(_ id: UUID, _ name: String?, in state: inout State) -> Effect<Action> {
        guard state.guests[id: id] != nil else {
            return .none
        }
        state.guests[id: id]?.expected = name.flatMap(kakusan.nickname)
        return recognize(id, in: state)
    }

    private func recognize(_ id: UUID, in state: State) -> Effect<Action> {
        guard let guest = state.guests[id: id], let key = guest.attempt.peer?.publicKey else {
            return .none
        }
        let expected = guest.expected
        return .run { [kakusan] send in
            let recognition = (try? await kakusan.recognize(key, expected)) ?? .unknown
            await send(.recognised(id, key, recognition))
        }
    }

    private func submitReply(_ id: UUID, _ text: String, in state: inout State) -> Effect<Action> {
        let operation = uuid()
        let (transition, effect) = transition(.reply(.submit(operation)), to: id, in: &state)
        guard transition == .accepted else {
            return effect
        }
        guard let block = KakusanBlock(pasted: text) else {
            return apply(.reply(.rejected(operation, .invalidBlock)), to: id, in: &state)
        }
        state.guests[id: id]?.replyOperation = operation
        return .run { [kakusan] send in
            await send(.replyResult(id, operation: operation, await kakusan.importReply(block)))
        }
    }

    private func approve(_ id: UUID, in state: inout State) -> Effect<Action> {
        guard let guest = state.guests[id: id], guest.attempt.approval == .pending,
              guest.attempt.guest != nil else {
            return .none
        }
        let operation = uuid()
        let (transition, effect) = transition(.approval(.request(operation)), to: id, in: &state)
        guard transition == .accepted else {
            return effect
        }
        return .merge(effect, .send(.approvalResult(id, operation: operation, .accepted)))
    }

    private func submitCode(_ id: UUID, _ text: String, in state: inout State) -> Effect<Action> {
        guard let code = KakusanCode(text), let target = state.guests[id: id]?.attempt.guest else {
            return .none
        }
        let operation = uuid()
        let (transition, effect) = transition(.code(.submit(operation)), to: id, in: &state)
        guard transition == .accepted else {
            return effect
        }
        return .merge(effect, .run { [kakusan] send in
            await send(.codeResult(id, operation: operation, await kakusan.send(.enterCode(target, code))))
        })
    }

    private func cancel(_ id: UUID, in state: inout State) -> Effect<Action> {
        guard let target = state.guests[id: id]?.attempt.guest else {
            state.guests.remove(id: id)
            closeCard(of: id, in: &state)
            return .cancel(id: CancelID.expiry(id))
        }
        let (transition, effect) = transition(.cancel, to: id, in: &state)
        state.guests.remove(id: id)
        closeCard(of: id, in: &state)
        guard transition == .accepted else {
            return effect
        }
        return .merge(effect, quietCommand(.remove(target)))
    }

    private func dismiss(_ id: UUID, in state: inout State) -> Effect<Action> {
        closeCard(of: id, in: &state)
        if state.guests[id: id]?.attempt.outcome != nil {
            state.guests.remove(id: id)
        }
        return .none
    }

    private func closeCard(of id: UUID, in state: inout State) {
        if state.presented == id {
            state.destination = nil
        }
    }

    private func seat(
        _ input: KakusanHostInput.Seat,
        for guest: KakusanGuestID,
        in state: inout State
    ) -> Effect<Action> {
        guard let id = state.guest(for: guest)?.id else {
            return .none
        }
        return apply(.seat(input), to: id, in: &state)
    }

    private func commandFailed(
        _ command: KakusanHostCommand,
        _ error: KakusanError,
        in state: inout State
    ) -> Effect<Action> {
        switch command {
        case .setLocalSeats where error == .noCapacity:
            return .send(.delegate(.notice(.noFreeSeat)))
        case .giveSeat(let guest, _, _, _):
            let effect = seat(.consoleJoinFailed, for: guest, in: &state)
            return .merge(effect, .send(.delegate(.notice(.commandFailed(error)))))
        default:
            return .send(.delegate(.notice(.commandFailed(error))))
        }
    }

    private func localSeatsChanged(_ count: Int, in state: inout State) -> Effect<Action> {
        guard count != state.localSeats else {
            return .none
        }
        state.localSeats = count
        guard state.hosting == .available else {
            return .none
        }
        return command(.setLocalSeats(count))
    }

    private func handle(_ event: KakusanHostEvent, in state: inout State) -> Effect<Action> {
        switch event {
        case let .invitationReady(guest, block, expiresAt):
            let invitation = KakusanInvitation(block: block, expiresAt: expiresAt)
            return route(guest, event, .invitation(.ready(invitation)), in: &state)
        case let .replyBound(guest, key, fingerprint):
            let peer = KakusanIdentity(publicKey: key, fingerprint: fingerprint)
            return route(guest, event, .reply(.bound(peer)), in: &state)
        case let .codeReady(guest, code):
            return route(guest, event, .code(.ready(code)), in: &state)
        case let .stateChanged(guest, change):
            let effect = route(guest, event, .state(change), in: &state)
            return .merge(effect, requestSeat(guest, in: &state))
        case let .consoleSeated(guest, pad):
            return seat(.consoleJoined(pad: pad), for: guest, in: &state)
        case let .consoleUnseated(guest, pad):
            return seat(.consoleLeft(pad: pad), for: guest, in: &state)
        case .seatsChanged(let snapshot):
            state.seats = snapshot
            return .none
        case .unavailable(let error):
            state.hosting = .unavailable(error)
            let change = KakusanStateChange(state: .closed, error: error)
            let effects = state.guests.ids.map { transition(.state(change), to: $0, in: &state).1 }
            return .merge(effects)
        }
    }

    private func route(
        _ guest: KakusanGuestID,
        _ event: KakusanHostEvent,
        _ input: KakusanHostInput,
        in state: inout State
    ) -> Effect<Action> {
        guard let id = state.guest(for: guest)?.id else {
            buffer(event, for: guest, in: &state)
            return .none
        }
        return transition(input, to: id, in: &state).1
    }

    private func buffer(_ event: KakusanHostEvent, for guest: KakusanGuestID, in state: inout State) {
        let preparing = state.guests.contains { $0.attempt.guest == nil && $0.attempt.outcome == nil }
        guard preparing, state.early.count < Self.earlyEventLimit || state.early[guest] != nil else {
            return
        }
        var events = state.early[guest] ?? []
        guard events.count < Self.earlyEventLimit else {
            return
        }
        events.append(event)
        state.early[guest] = events
    }

    private func requestSeat(_ guest: KakusanGuestID, in state: inout State) -> Effect<Action> {
        guard let current = state.guest(for: guest), current.attempt.phase == .admitting(.awaitingSeat),
              current.attempt.approval != .pending
        else {
            return .none
        }
        let (transition, effect) = transition(.seat(.joinRequested), to: current.id, in: &state)
        guard transition == .accepted else {
            return effect
        }
        let remote = KakusanRemotePlayer(guest: guest, name: current.name)
        return .merge(effect, .send(.delegate(.claimSeat(remote))))
    }

    private func replyImported(
        _ id: UUID,
        _ operation: UUID,
        _ result: Result<KakusanGuestID, KakusanError>,
        in state: inout State
    ) -> Effect<Action> {
        guard state.guests[id: id]?.replyOperation == operation else {
            return .none
        }
        state.guests[id: id]?.replyOperation = nil
        switch result {
        case .failure(let error):
            return transition(.reply(.rejected(operation, error)), to: id, in: &state).1
        case .success(let guest) where state.guests[id: id]?.attempt.guest == guest:
            let effect = transition(.reply(.imported(operation)), to: id, in: &state).1
            return .merge(effect, approve(id, in: &state))
        case .success(let guest):
            let redirect = transition(.reply(.redirected(operation)), to: id, in: &state).1
            guard let other = state.guest(for: guest)?.id else {
                return redirect
            }
            let (accepted, effect) = transition(.reply(.imported(nil)), to: other, in: &state)
            if accepted == .accepted {
                state.destination = .invite(KakusanInviteFeature.State(guest: other))
            }
            return .merge(redirect, effect, approve(other, in: &state))
        }
    }

    private func apply(_ input: KakusanHostInput, to id: UUID, in state: inout State) -> Effect<Action> {
        transition(input, to: id, in: &state).1
    }

    private func transition(
        _ input: KakusanHostInput,
        to id: UUID,
        in state: inout State
    ) -> (KakusanTransition, Effect<Action>) {
        guard var guest = state.guests[id: id] else {
            return (.ignored, .none)
        }
        let before = guest.attempt
        let result = guest.attempt.apply(input)
        state.guests[id: id] = guest
        guard result == .accepted else {
            return (result, .none)
        }
        var effects = progress(id, from: before, in: &state)
        if before.outcome == nil, let outcome = guest.attempt.outcome {
            effects.append(finish(id, before: before, outcome: outcome, input: input, in: &state))
        }
        return (result, .merge(effects))
    }

    private func progress(_ id: UUID, from before: KakusanHostAttempt,
                          in state: inout State) -> [Effect<Action>] {
        guard let guest = state.guests[id: id] else {
            return []
        }
        let after = guest.attempt
        var effects: [Effect<Action>] = []
        if case .preparing = before.phase, case .invitation(let invitation, _) = after.phase {
            effects.append(expiry(id, at: invitation.expiresAt))
        }
        if case .invitation = before.phase, after.outcome == nil, !Self.inviting(after.phase) {
            effects.append(.cancel(id: CancelID.expiry(id)))
        }
        if before.peer == nil, after.peer != nil {
            effects.append(recognize(id, in: state))
        }
        if before.milestone < .verified, after.milestone >= .verified, after.outcome == nil {
            closeCard(of: id, in: &state)
        }
        guard let target = after.guest else {
            return effects
        }
        if before.seatRequested, !after.seatRequested {
            effects.append(.send(.delegate(.releaseSeat(target))))
        }
        let remote = KakusanRemotePlayer(guest: target, name: guest.name)
        if let pad = after.reservedPad, pad != before.reservedPad {
            effects.append(.send(.delegate(.reserveSeat(remote, pad: pad))))
        }
        if let pad = after.pad, pad != before.pad {
            effects.append(.send(.delegate(.showSeat(remote, pad: pad))))
        }
        return effects
    }

    private static func inviting(_ phase: KakusanHostPhase) -> Bool {
        if case .invitation = phase {
            return true
        }
        return false
    }

    private func expiry(_ id: UUID, at deadline: Date) -> Effect<Action> {
        let delay = max(0, deadline.timeIntervalSince(date.now))
        return .run { [clock] send in
            try await clock.sleep(for: .milliseconds(Int((delay * 1000).rounded(.up))))
            await send(.expire(id))
        }
        .cancellable(id: CancelID.expiry(id), cancelInFlight: true)
    }

    private func finish(
        _ id: UUID,
        before: KakusanHostAttempt,
        outcome: KakusanAttemptOutcome,
        input: KakusanHostInput,
        in state: inout State
    ) -> Effect<Action> {
        var effects: [Effect<Action>] = [.cancel(id: CancelID.expiry(id))]
        if outcome == .failed(.pairingFailed) {
            effects.append(recordPairingFailure(&state))
        }
        let target = state.guests[id: id]?.attempt.guest
        if let target, Self.locallyDecided(input) {
            effects.append(quietCommand(.remove(target)))
        }
        guard state.presented != id, let guest = state.guests[id: id] else {
            return .merge(effects)
        }
        state.guests.remove(id: id)
        guard outcome != .cancelled else {
            return .merge(effects)
        }
        let notice: KakusanHostNotice = guest.attempt.milestone == .inviting
            ? .invitationEnded(outcome)
            : .ended(name: guest.name, outcome)
        effects.append(.send(.delegate(.notice(notice))))
        return .merge(effects)
    }

    private static func locallyDecided(_ input: KakusanHostInput) -> Bool {
        switch input {
        case .state, .hostingEnded, .cancel:
            false
        case .invitation, .reply, .approval, .code, .seat:
            true
        }
    }

    private func recordPairingFailure(_ state: inout State) -> Effect<Action> {
        let now = date.now
        var failures = state.pairingFailures.filter { now.timeIntervalSince($0) < Self.failureWindow }
        failures.append(now)
        guard failures.count >= Self.failureLimit else {
            state.pairingFailures = failures
            return .none
        }
        state.pairingFailures = []
        state.cooldownUntil = now.addingTimeInterval(Self.cooldown)
        return .run { [clock] send in
            try await clock.sleep(for: .seconds(Self.cooldown))
            await send(.cooldownEnded)
        }
        .cancellable(id: CancelID.cooldown, cancelInFlight: true)
    }
}

extension KakusanHostFeature.Destination.State: Equatable, Sendable {}
extension KakusanHostFeature.Destination.Action: Equatable, Sendable {}
