import ChiakiModels
import Foundation

/// What the stream plays from, which decides how extra players join.
public enum CouchConsole: Equatable, Sendable {
    /// A PS4, a PS5 or a cloud stream.
    case ps4, ps5, cloud
}

/// One extra player's seat as it moves from open through joining to ready.
public enum CouchSeat: Equatable, Sendable {
    /// Nobody uses the seat.
    case open
    /// The input waits for someone to choose the account it joins with.
    case choosingAccount(CouchInput)
    /// The join was sent and the console has not answered yet.
    case joining(CouchPlayer)
    /// The PS4 asks the player to choose a user on the TV.
    case pickingOnConsole(CouchPlayer)
    /// The console asks for the account's passcode; `retry` is set after a wrong one.
    case passcode(CouchPlayer, retry: Bool)
    /// The player is in the game, with the light colour the console gave them, if known.
    case ready(CouchPlayer, color: UInt32?)

    /// The local controller in the seat, if any.
    public var device: ControllerDevice? {
        switch self {
        case .open:
            nil
        case .choosingAccount(let input):
            input.device
        case .joining(let player), .pickingOnConsole(let player), .passcode(let player, _),
             .ready(let player, _):
            player.device
        }
    }

    /// The remote guest in the seat, if any.
    public var remote: CouchRemoteInput? {
        switch self {
        case .open:
            nil
        case .choosingAccount(let input):
            input.remote
        case .joining(let player), .pickingOnConsole(let player), .passcode(let player, _),
             .ready(let player, _):
            player.remote
        }
    }

    /// The player in the seat, or `nil` while it is open or still choosing an account.
    public var player: CouchPlayer? {
        switch self {
        case .open, .choosingAccount:
            nil
        case .joining(let player), .pickingOnConsole(let player), .passcode(let player, _),
             .ready(let player, _):
            player
        }
    }
}

/// What a seat change asks for: commands for the stream, a notice and requests for the remote play host.
public struct CouchOutcome: Equatable, Sendable {
    /// The commands to send to the stream, in order.
    public var commands: [CouchCommand] = []
    /// The notice to show, if any.
    public var notice: CouchNotice?
    /// The requests for the remote play host about its guests.
    public var remote: [CouchRemoteRequest] = []
}

/// Whether an account can be chosen for a seat, and if not, why.
public enum CouchAccountAvailability: Equatable, Sendable {
    /// The account can join.
    case available
    /// Player 1 plays with the account.
    case host
    /// The account already plays on another pad.
    case seated(UInt8)
    /// A remote guest is joining with the account.
    case joiningRemote
    /// The console did not recognise the account earlier in this stream.
    case unrecognised
}

/// The extra players' seats on pads 1 to 3, with the rules for joining, swapping and leaving them.
///
/// Every change returns a ``CouchOutcome`` with the commands and notice that follow from it.
public struct CouchSeats: Equatable, Sendable {
    /// The pads extra players can take; pad 0 is player 1.
    public static let pads: [UInt8] = [1, 2, 3]
    /// What the stream plays from.
    public let console: CouchConsole
    /// The account player 1 plays with, which no seat may use.
    public let hostAccount: UUID?
    /// The controller player 1 uses, which no seat may claim.
    public var primaryDevice: UInt32?
    /// The seat on each pad.
    public internal(set) var seats: [UInt8: CouchSeat]
    /// The account IDs the console rejected in this stream, so they are not offered again.
    public private(set) var unrecognisedAccounts: Set<Data> = []
    /// How many open seats are kept back for remote guests who have not asked for one yet.
    public var heldForRemote = 0
    /// The remote guests waiting for an account or a pad, in the order they asked.
    public internal(set) var waiting: [CouchRemoteWait] = []
    /// The light colours the console confirmed for pads before their player became ready.
    var consoleColors: [UInt8: UInt32] = [:]
    /// The pads the console asked a passcode for before their player was seated.
    var consolePasscodes: Set<UInt8> = []

    /// Creates seats that are all open.
    ///
    /// - Parameters:
    ///   - console: What the stream plays from.
    ///   - hostAccount: The account player 1 plays with.
    ///   - primaryDevice: The controller player 1 uses.
    public init(console: CouchConsole, hostAccount: UUID? = nil, primaryDevice: UInt32? = nil) {
        self.console = console
        self.hostAccount = hostAccount
        self.primaryDevice = primaryDevice
        seats = Dictionary(uniqueKeysWithValues: Self.pads.map { ($0, CouchSeat.open) })
    }

    /// The seat on a pad; a pad outside the seats reads as open.
    public subscript(pad: UInt8) -> CouchSeat {
        seats[pad] ?? .open
    }

    /// How many seats are not open.
    public var takenCount: Int {
        seats.values.filter { $0 != .open }.count
    }

    /// The pad whose seat uses the controller with this identifier.
    public func pad(for device: UInt32) -> UInt8? {
        Self.pads.first { self[$0].device?.id == device }
    }

    /// Whether a pad waits for a passcode, including one the console asked about before anyone was seated.
    public func awaitsPasscode(_ pad: UInt8) -> Bool {
        if case .passcode = self[pad] {
            return true
        }
        return consolePasscodes.contains(pad)
    }

    /// The lowest open pad a local player may take once seats are kept back for remote guests.
    public var lowestOpenPad: UInt8? {
        let open = Self.pads.filter { self[$0] == .open }
        return open.dropLast(min(heldForRemote, open.count)).first
    }

    /// Whether an account can join, checking player 1, earlier rejections, the other seats and remote guests.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - pad: The pad it would join on, or `nil` for a remote guest.
    public func availability(of account: AccountProfile, for pad: UInt8?) -> CouchAccountAvailability {
        if account.id == hostAccount {
            return .host
        }
        if unrecognisedAccounts.contains(account.accountID.data) {
            return .unrecognised
        }
        if let other = Self.pads.first(where: { $0 != pad && self[$0].player?.account?.id == account.id }) {
            return .seated(other)
        }
        if waiting.contains(where: { $0.account?.id == account.id }) {
            return .joiningRemote
        }
        return .available
    }

    /// The controller type sent with a join: 6 for a DualSense, 2 for other PlayStation pads, else 0.
    public static func controllerType(for device: ControllerDevice) -> UInt8 {
        guard device.family == .playStation else {
            return 0
        }
        if device.adaptiveTriggers || device.name.localizedCaseInsensitiveContains("DualSense") {
            return 6
        }
        return 2
    }

    /// Takes the lowest open pad for a controller and starts its join the way the console expects.
    ///
    /// On a PS5 the seat first waits for an account, a PS4 is asked to join at once, and a cloud
    /// stream seats the player straight away. The outcome is empty when the controller is player 1's,
    /// already seated, or no pad is open.
    public mutating func claim(_ device: ControllerDevice) -> CouchOutcome {
        guard device.id != primaryDevice, pad(for: device.id) == nil, let pad = lowestOpenPad else {
            return CouchOutcome()
        }
        switch console {
        case .ps5:
            seats[pad] = .choosingAccount(.local(device))
            return CouchOutcome()
        case .ps4:
            seats[pad] = .joining(CouchPlayer(device: device))
            return CouchOutcome(commands: [
                .route(pad: pad, device: device),
                .join(pad: pad, controllerType: Self.controllerType(for: device), accountID: nil)
            ])
        case .cloud:
            let player = CouchPlayer(device: device)
            seats[pad] = .ready(player, color: nil)
            return CouchOutcome(
                commands: [
                    .route(pad: pad, device: device),
                    .join(pad: pad, controllerType: Self.controllerType(for: device), accountID: nil)
                ],
                notice: .joined(pad: pad, player: player, color: nil)
            )
        }
    }

    /// The ready players who use local controllers, by pad.
    public var seatedLocally: [UInt8: CouchPlayer] {
        var players: [UInt8: CouchPlayer] = [:]
        for pad in Self.pads {
            if case .ready(let player, _) = self[pad], player.remote == nil {
                players[pad] = player
            }
        }
        return players
    }

    /// Starts the join again for each remembered local player whose pad is open, after a reconnect.
    public mutating func reseat(_ players: [UInt8: CouchPlayer]) -> CouchOutcome {
        var outcome = CouchOutcome()
        for pad in Self.pads {
            guard let player = players[pad], self[pad] == .open, let device = player.device else {
                continue
            }
            seats[pad] = .joining(player)
            outcome.commands += [
                .route(pad: pad, device: device),
                .join(
                    pad: pad, controllerType: Self.controllerType(for: player.input, on: console),
                    accountID: player.account?.accountID.data
                )
            ]
        }
        return outcome
    }

    /// Starts the join of the input choosing an account on a pad, if the account is available.
    public mutating func chooseAccount(_ account: AccountProfile, for pad: UInt8) -> CouchOutcome {
        guard case .choosingAccount(let input) = self[pad], availability(of: account, for: pad) == .available
        else {
            return CouchOutcome()
        }
        seats[pad] = .joining(CouchPlayer(input: input, account: account))
        return CouchOutcome(commands: [
            .join(
                pad: pad,
                controllerType: Self.controllerType(for: input, on: console),
                accountID: account.accountID.data
            )
        ])
    }

    /// Moves a ready local player onto a controller no other seat holds, keeping their account and colour.
    public mutating func replaceController(_ pad: UInt8, with device: ControllerDevice) -> CouchOutcome {
        let holder = self.pad(for: device.id)
        guard device.id != primaryDevice, holder == nil || holder == pad,
              case .ready(let player, let color) = self[pad], player.remote == nil else {
            return CouchOutcome()
        }
        seats[pad] = .ready(CouchPlayer(device: device, account: player.account), color: color)
        return CouchOutcome(commands: [.route(pad: pad, device: device)])
    }

    /// Changes a ready local player's controller without sending any command.
    ///
    /// - Returns: Whether the pad held a ready local player.
    public mutating func setController(_ pad: UInt8, to device: ControllerDevice) -> Bool {
        guard case .ready(let player, let color) = self[pad], player.remote == nil else {
            return false
        }
        seats[pad] = .ready(CouchPlayer(device: device, account: player.account), color: color)
        return true
    }

    /// Opens a pad, asking the console to remove a local player or telling the host that a remote guest left.
    public mutating func cancel(_ pad: UInt8) -> CouchOutcome {
        switch self[pad] {
        case .open:
            consolePasscodes.remove(pad)
            return CouchOutcome()
        case .choosingAccount:
            seats[pad] = .open
            return CouchOutcome()
        case .joining, .pickingOnConsole, .passcode, .ready:
            let remote = self[pad].remote
            seats[pad] = .open
            guard let remote else {
                return CouchOutcome(commands: [.remove(pad: pad), .route(pad: pad, device: nil)])
            }
            return CouchOutcome(remote: [.removed(remote)])
        }
    }
}

extension CouchSeats {
    /// Updates the seats for an event from the stream session and returns what follows from it.
    public mutating func apply(_ event: CouchSessionEvent) -> CouchOutcome {
        switch event {
        case .announced(let pad):
            return announce(pad)
        case let .confirmed(pad, color):
            return confirm(pad, color: color)
        case let .passcodeRequested(pad, retry):
            return requestPasscode(pad, retry: retry)
        case let .joinFailed(pad, failure):
            return failJoin(pad, failure: failure)
        case .dropped(let pad):
            return drop(pad)
        case .accountUnresolvable(let pad):
            return rejectAccount(pad)
        case .controllerConnected:
            return CouchOutcome()
        case .controllerClaimed(let device):
            return claim(device)
        case .controllerRemoved(let id):
            return removeController(id)
        case .playerOneChanged:
            return CouchOutcome()
        }
    }

    private mutating func announce(_ pad: UInt8) -> CouchOutcome {
        guard case .joining(let player) = self[pad], console == .ps4 else {
            return CouchOutcome()
        }
        seats[pad] = .pickingOnConsole(player)
        return CouchOutcome()
    }

    private mutating func requestPasscode(_ pad: UInt8, retry: Bool) -> CouchOutcome {
        switch self[pad] {
        case .joining(let player), .passcode(let player, _):
            seats[pad] = .passcode(player, retry: retry)
        case .open:
            consolePasscodes.insert(pad)
        case .choosingAccount, .pickingOnConsole, .ready:
            break
        }
        return CouchOutcome()
    }

    private mutating func failJoin(_ pad: UInt8, failure: CouchFailure) -> CouchOutcome {
        forgetConsole(pad)
        guard let player = self[pad].player else {
            return CouchOutcome()
        }
        guard player.remote == nil else {
            return refuseReserved(pad, player: player, failure: failure)
        }
        return CouchOutcome(
            commands: vacate(pad),
            notice: .joinFailed(pad: pad, failure: failure)
        )
    }

    private mutating func refuseReserved(
        _ pad: UInt8,
        player: CouchPlayer,
        failure: CouchFailure
    ) -> CouchOutcome {
        guard heldForRemote(pad) else {
            return CouchOutcome()
        }
        seats[pad] = .joining(player)
        return CouchOutcome(notice: .joinFailed(pad: pad, failure: failure))
    }

    private mutating func forgetConsole(_ pad: UInt8) {
        consoleColors[pad] = nil
        consolePasscodes.remove(pad)
    }

    private mutating func drop(_ pad: UInt8) -> CouchOutcome {
        forgetConsole(pad)
        guard self[pad].player != nil, self[pad].remote == nil else {
            return CouchOutcome()
        }
        return CouchOutcome(commands: vacate(pad), notice: .released(pad: pad))
    }

    private mutating func rejectAccount(_ pad: UInt8) -> CouchOutcome {
        guard let player = self[pad].player, player.remote == nil || heldForRemote(pad) else {
            return CouchOutcome()
        }
        if let account = player.account {
            unrecognisedAccounts.insert(account.accountID.data)
        }
        guard player.remote == nil else {
            return refuseReserved(pad, player: player, failure: .accountUnresolvable)
        }
        return CouchOutcome(
            commands: vacate(pad),
            notice: .joinFailed(pad: pad, failure: .accountUnresolvable)
        )
    }

    private mutating func removeController(_ id: UInt32) -> CouchOutcome {
        guard let pad = pad(for: id) else {
            return CouchOutcome()
        }
        var outcome = cancel(pad)
        outcome.notice = .disconnected(pad: pad)
        return outcome
    }

    private mutating func confirm(_ pad: UInt8, color: UInt32) -> CouchOutcome {
        switch self[pad] {
        case .joining(let player), .pickingOnConsole(let player), .passcode(let player, _):
            guard player.remote == nil else {
                consoleColors[pad] = color
                seats[pad] = .joining(player)
                return CouchOutcome()
            }
            seats[pad] = .ready(player, color: color)
            return CouchOutcome(
                commands: player.device.map { [.route(pad: pad, device: $0)] } ?? [],
                notice: .joined(pad: pad, player: player, color: color)
            )
        case .ready(let player, _):
            seats[pad] = .ready(player, color: color)
            return CouchOutcome()
        case .open:
            consoleColors[pad] = color
            consolePasscodes.remove(pad)
            return CouchOutcome()
        case .choosingAccount:
            return CouchOutcome()
        }
    }
}
