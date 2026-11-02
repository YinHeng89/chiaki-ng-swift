import ChiakiModels
import Foundation
import ComposableArchitecture

/// A remote guest who asked for a seat and has none yet.
public enum CouchRemoteWait: Equatable, Sendable {
    /// The guest waits for someone to choose their account.
    case choosingAccount(CouchRemoteInput)
    /// A seat was requested for the guest, with the chosen account if there is one.
    case joining(CouchRemoteInput, account: AccountProfile?)

    /// The guest who waits.
    public var remote: CouchRemoteInput {
        switch self {
        case .choosingAccount(let remote), .joining(let remote, _):
            remote
        }
    }

    /// The account chosen for the guest, if any.
    public var account: AccountProfile? {
        switch self {
        case .choosingAccount:
            nil
        case .joining(_, let account):
            account
        }
    }
}

/// A request for the remote play host about one of its guests.
public enum CouchRemoteRequest: Equatable, Sendable {
    /// Seat the guest with this controller type and account.
    case seat(CouchRemoteInput, controllerType: UInt8, accountID: Data?)
    /// The guest's request for a seat was declined.
    case declined(CouchRemoteInput)
    /// The guest left their seat or their wait.
    case removed(CouchRemoteInput)
}

/// Whose account is being chosen: a local seat's or a remote guest's.
public enum CouchAccountChoice: Equatable, Sendable {
    /// The input waiting on this pad.
    case pad(UInt8)
    /// This remote guest.
    case remote(KakusanGuestID)
}

extension CouchSeats {
    /// Whether a remote guest holds a pad without being ready yet.
    public func heldForRemote(_ pad: UInt8) -> Bool {
        if case .ready = self[pad] {
            return false
        }
        return self[pad].remote != nil
    }

    /// How many seats local controllers use, whatever their state.
    public var localCount: Int {
        Self.pads.filter { self[$0] != .open && self[$0].remote == nil }.count
    }

    /// How many seats remote guests use.
    public var remoteCount: Int {
        Self.pads.filter { self[$0].remote != nil }.count
    }

    /// The pad a remote guest holds, if any.
    public func pad(for guest: KakusanGuestID) -> UInt8? {
        Self.pads.first { self[$0].remote?.guest == guest }
    }

    /// The wait of a remote guest who has no seat yet.
    public func wait(for guest: KakusanGuestID) -> CouchRemoteWait? {
        waiting.first { $0.remote.guest == guest }
    }

    /// The seat or remote guest waiting for an account, local seats first.
    public var choosing: CouchAccountChoice? {
        if let pad = Self.pads.first(where: { choosesAccount($0) }) {
            return .pad(pad)
        }
        for case .choosingAccount(let remote) in waiting {
            return .remote(remote.guest)
        }
        return nil
    }

    private func choosesAccount(_ pad: UInt8) -> Bool {
        if case .choosingAccount = self[pad] {
            return true
        }
        return false
    }

    /// Queues a remote guest for a seat if an open seat is left for them.
    ///
    /// A PS4 seat is requested at once; on a PS5 the guest first waits for an account.
    /// Cloud streams take no guests.
    ///
    /// - Returns: Whether the guest was queued, and the requests for the host.
    public mutating func claimRemote(_ remote: CouchRemoteInput) -> (claimed: Bool, outcome: CouchOutcome) {
        let open = Self.pads.filter { self[$0] == .open }.count
        guard pad(for: remote.guest) == nil, wait(for: remote.guest) == nil, console != .cloud,
              open > waiting.count else {
            return (false, CouchOutcome())
        }
        guard console == .ps4 else {
            waiting.append(.choosingAccount(remote))
            return (true, CouchOutcome())
        }
        waiting.append(.joining(remote, account: nil))
        return (true, CouchOutcome(remote: [
            .seat(
                remote,
                controllerType: Self.controllerType(for: .remote(remote), on: console),
                accountID: nil
            )
        ]))
    }

    /// Chooses the account of a remote guest waiting for one and requests their seat.
    public mutating func chooseAccount(
        _ account: AccountProfile,
        forRemote guest: KakusanGuestID
    ) -> CouchOutcome {
        guard let index = waiting.firstIndex(where: { $0.remote.guest == guest }),
              case .choosingAccount(let remote) = waiting[index],
              availability(of: account, for: nil) == .available else {
            return CouchOutcome()
        }
        waiting[index] = .joining(remote, account: account)
        return CouchOutcome(remote: [
            .seat(
                remote,
                controllerType: Self.controllerType(for: .remote(remote), on: console),
                accountID: account.accountID.data
            )
        ])
    }

    /// Drops a waiting remote guest and tells the host whether the request was declined or the guest left.
    public mutating func cancelRemote(_ guest: KakusanGuestID) -> CouchOutcome {
        guard let index = waiting.firstIndex(where: { $0.remote.guest == guest }) else {
            return CouchOutcome()
        }
        let wait = waiting.remove(at: index)
        switch wait {
        case .choosingAccount(let remote):
            return CouchOutcome(remote: [.declined(remote)])
        case .joining(let remote, _):
            return CouchOutcome(remote: [.removed(remote)])
        }
    }

    /// Holds a pad for a remote guest while the console joins them, freeing any pad they held before.
    public mutating func reserveRemote(_ remote: CouchRemoteInput, at pad: UInt8) -> CouchOutcome {
        guard Self.pads.contains(pad), self.pad(for: remote.guest) != pad else {
            return CouchOutcome()
        }
        let (player, displaced) = move(remote, to: pad)
        seats[pad] = consolePasscodes.remove(pad) == nil
            ? .joining(player)
            : .passcode(player, retry: false)
        return CouchOutcome(commands: displaced)
    }

    /// Makes a remote guest ready on a pad, with the colour the console gave it, and announces the join.
    public mutating func seatRemote(_ remote: CouchRemoteInput, at pad: UInt8) -> CouchOutcome {
        guard Self.pads.contains(pad), self.pad(for: remote.guest) != pad || heldForRemote(pad) else {
            return CouchOutcome()
        }
        let (player, displaced) = move(remote, to: pad)
        let color = consoleColors.removeValue(forKey: pad)
        consolePasscodes.remove(pad)
        seats[pad] = .ready(player, color: color)
        return CouchOutcome(commands: displaced, notice: .joined(pad: pad, player: player, color: color))
    }

    private mutating func move(
        _ remote: CouchRemoteInput,
        to pad: UInt8
    ) -> (player: CouchPlayer, displaced: [CouchCommand]) {
        var account = wait(for: remote.guest)?.account
        waiting.removeAll { $0.remote.guest == remote.guest }
        if let previous = self.pad(for: remote.guest) {
            account = self[previous].player?.account
            seats[previous] = .open
        }
        let displaced = self[pad] != .open && self[pad].remote == nil
            ? unroute(pad)
            : []
        return (CouchPlayer(input: .remote(remote), account: account), displaced)
    }

    /// The controller type sent with a join; a remote guest is a DualShock 4 on a PS4, else a DualSense.
    public static func controllerType(for input: CouchInput, on console: CouchConsole) -> UInt8 {
        switch input {
        case .local(let device):
            controllerType(for: device)
        case .remote:
            console == .ps4
                ? 2
                : 6
        }
    }

    /// Forgets a remote guest and opens the pad they held.
    ///
    /// - Returns: The pad that opened, if any, and an empty outcome.
    public mutating func releaseRemote(_ guest: KakusanGuestID) -> (pad: UInt8?, outcome: CouchOutcome) {
        waiting.removeAll { $0.remote.guest == guest }
        guard let pad = pad(for: guest) else {
            return (nil, CouchOutcome())
        }
        seats[pad] = .open
        return (pad, CouchOutcome())
    }

    /// The command that stops a local controller's input to a pad; a remote guest's pad needs none.
    func unroute(_ pad: UInt8) -> [CouchCommand] {
        self[pad].remote == nil
            ? [.route(pad: pad, device: nil)]
            : []
    }

    /// Opens a pad and returns the command that stops its input.
    mutating func vacate(_ pad: UInt8) -> [CouchCommand] {
        let commands = unroute(pad)
        seats[pad] = .open
        return commands
    }
}

extension CouchReducer {
    /// What the couch tells its parent about remote guests and saved controls.
    public enum Delegate: Equatable, Sendable {
        /// A remote guest could not get a seat.
        case remoteJoinFailed(CouchRemoteInput)
        /// A remote guest left their seat.
        case remoteLeft(CouchRemoteInput)
        /// The host should seat a remote guest with this controller type and account.
        case seatRemote(CouchRemoteInput, controllerType: UInt8, accountID: Data?)
        /// A player's controls settings saved a configuration.
        case controlsCommitted(ControlsConfiguration)
    }

    /// Handles remote guests and posted notices while the seats are open.
    func reduceRemote(_ state: inout State, _ action: Action) -> Effect<Action> {
        guard state.active else {
            return .none
        }
        switch action {
        case .claimRemote(let remote):
            let (claimed, outcome) = state.seats.claimRemote(remote)
            guard claimed else {
                return .send(.delegate(.remoteJoinFailed(remote)))
            }
            return seat(outcome, in: &state)
        case let .chooseRemoteAccount(guest, id):
            guard let account = state.accounts.first(where: { $0.id == id }) else {
                return .none
            }
            return apply(state.seats.chooseAccount(account, forRemote: guest), to: &state)
        case .cancelRemote(let guest):
            return apply(state.seats.cancelRemote(guest), to: &state)
        case .reserveRemote, .seatRemote, .releaseRemote:
            return followCore(action, in: &state)
        case .post(let notice):
            return post(notice, in: &state)
        default:
            return .none
        }
    }

    private func followCore(_ action: Action, in state: inout State) -> Effect<Action> {
        switch action {
        case let .reserveRemote(remote, pad):
            settle(state.seats.pad(for: remote.guest), pad, in: &state) {
                $0.reserveRemote(remote, at: pad)
            }
        case let .seatRemote(remote, pad):
            settle(state.seats.pad(for: remote.guest), pad, in: &state) {
                $0.seatRemote(remote, at: pad)
            }
        case .releaseRemote(let guest):
            settle(state.seats.pad(for: guest), nil, in: &state) {
                $0.releaseRemote(guest).outcome
            }
        default:
            .none
        }
    }

    private func settle(
        _ previous: UInt8?,
        _ next: UInt8?,
        in state: inout State,
        _ change: (inout CouchSeats) -> CouchOutcome
    ) -> Effect<Action> {
        if let picking = state.picking, picking == previous || picking == next {
            state.picking = nil
        }
        return apply(change(&state.seats), to: &state)
    }

    /// The delegate action that passes a request about a remote guest to the parent.
    static func delegate(for request: CouchRemoteRequest) -> Delegate {
        switch request {
        case let .seat(remote, controllerType, accountID):
            .seatRemote(remote, controllerType: controllerType, accountID: accountID)
        case .declined(let remote):
            .remoteJoinFailed(remote)
        case .removed(let remote):
            .remoteLeft(remote)
        }
    }
}
