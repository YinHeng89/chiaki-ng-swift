import ChiakiModels
import Foundation
import ChiakiClients
import ComposableArchitecture

/// The extra players on the couch during a stream: their seats, controllers, accounts and notices.
///
/// It joins and removes players through `ChiakiClients/StreamSessionClient`, presents one overlay at a time
/// and hands menu navigation to the controller that the open overlay or waiting seat belongs to.
@Reducer
public struct CouchReducer {
    /// What the couch presents over the stream, one at a time.
    @Reducer
    public enum Overlay {
        /// A controller connected and is offered to a player.
        case newController(CouchNewControllerPrompt)
        /// A player's controller or keyboard settings.
        case controls(CouchControlsFeature)
    }

    /// The seats, controllers, notices and overlay of the current stream.
    @ObservableState public struct State: Equatable {
        /// The extra players' seats.
        public var seats = CouchSeats(console: .ps5)
        /// The saved accounts offered when someone chooses who joins.
        public var accounts: [AccountProfile] = []
        /// The notices shown over the stream, oldest first.
        public var notices: [CouchNoticeItem] = []
        /// The controller menu navigation was last handed to, or `nil` for player 1's.
        public var navigationOwner: UInt32?
        /// Whether a stream session has opened the seats.
        public var active = false
        /// The overlay presented over the stream, if any.
        @Presents public var overlay: Overlay.State?
        /// The pad whose controller is being chosen in the picker.
        public var picking: UInt8?
        /// The connected controllers, read when the picker opens and after each change.
        public var inventory = CouchInventory()
        /// The controller light colours.
        public var lights = CouchLights()
        /// The ready local players remembered while the stream reconnects, by pad.
        public var reseat: [UInt8: CouchPlayer] = [:]
        /// Whether remembered players are still joining again after a reconnect.
        public var reseating = false
        /// Creates closed seats.
        public init() {
        }
        /// The stream session the seats belong to; every couch effect carries it back.
        public private(set) var session: StreamSessionID?

        /// Opens the seats for a stream session.
        ///
        /// - Parameters:
        ///   - console: The console generation, or cloud.
        ///   - hostAccount: The account playing as player 1.
        ///   - lights: The controller light colours to start from.
        ///   - session: The stream session the seats belong to.
        public mutating func begin(
            _ console: CouchConsole,
            hostAccount: UUID?,
            lights: CouchLights = CouchLights(),
            session: StreamSessionID? = nil
        ) {
            seats = CouchSeats(console: console, hostAccount: hostAccount)
            notices = []
            self.lights = lights
            self.session = session
            active = true
        }

        /// Closes the seats when the stream session ends.
        public mutating func end() {
            session = nil
            seats = CouchSeats(console: seats.console, hostAccount: seats.hostAccount)
            notices = []
            navigationOwner = nil
            active = false
            overlay = nil
            picking = nil
            inventory = CouchInventory()
            lights = CouchLights()
            reseat = [:]
            reseating = false
        }
        /// The open controls settings, if any.
        public var controls: ControlsSettingsFeature.State? {
            overlay?.controls?.settings
        }

        /// The pad whose controls settings are open, or `nil` once they closed and only a save still runs.
        public var controlsPad: UInt8? {
            guard let controls = overlay?.controls, controls.phase == .editing else {
                return nil
            }
            return controls.pad
        }

        /// Whether the open controls settings show the keyboard.
        public var controlsKeyboard: Bool {
            overlay?.controls?.keyboard ?? false
        }

        /// The controller offered to a player, while the prompt is open.
        public var newController: ControllerDevice? {
            overlay?.newController?.device
        }

        /// The input whose settings are open: the pad player's keyboard or controller.
        public var controlsDevice: ControllerDevice? {
            guard let pad = controlsPad else {
                return nil
            }
            let owned = devices(of: pad)
            if controlsKeyboard {
                return owned.first(where: \.isKeyboard)
            }
            return owned.first
        }
        /// The inputs a pad's player uses.
        ///
        /// Player 1 has their controller and, unless a seat holds it, the keyboard; a ready seat has its own.
        public func devices(of pad: UInt8) -> [ControllerDevice] {
            if pad == 0 {
                return [inventory.playerOne, keyboardSeat == nil
                    ? ControllerDevice.keyboard
                    : nil].compactMap { $0 }
            }
            guard case .ready(let player, _) = seats[pad], let device = player.device else {
                return []
            }
            return [device]
        }
        /// The 0xRRGGBB light colour of a pad's player, if known.
        public func lightColor(for pad: UInt8) -> UInt32? {
            if pad == 0 {
                return lights.playerOne
            }
            guard case .ready(let player, let color) = seats[pad] else {
                return nil
            }
            return lights.lightbars.color(for: player.device, game: color)
        }
        /// The account name of the player on a pad.
        public func accountName(for pad: UInt8) -> String? {
            seats[pad].player?.account?.name
        }
        /// The seat or remote guest waiting for an account.
        public var choosing: CouchAccountChoice? {
            seats.choosing
        }
        /// The controller that should drive menu navigation now; the keyboard never takes it over.
        var expectedNavigationOwner: UInt32? {
            guard let owner = navigationCandidate, owner != ControllerDevice.keyboardID else {
                return nil
            }
            return owner
        }
        /// The pad whose player uses the keyboard, if a seat holds it.
        public var keyboardSeat: UInt8? {
            seats.pad(for: ControllerDevice.keyboardID)
        }
        /// Whether the controller picker can open for a pad: player 1, a ready local seat or the next open.
        public func canPick(for pad: UInt8) -> Bool {
            if pad == 0 {
                return true
            }
            if case .ready = seats[pad] {
                return seats[pad].remote == nil
            }
            return seats.lowestOpenPad == pad
        }
        /// Who holds a device; the keyboard and player 1's controller go to player 1 unless a seat has them.
        public func holder(of device: ControllerDevice) -> CouchHolder? {
            if let pad = seats.pad(for: device.id) {
                return .seat(pad)
            }
            if device.isKeyboard || inventory.playerOne?.id == device.id {
                return .playerOne
            }
            return nil
        }
        /// The controllers offered for a pad, keyboard first, leaving out the one it already uses.
        public func controllerOptions(for pad: UInt8) -> [CouchControllerOption] {
            let devices = [ControllerDevice.keyboard] + inventory.controllers.filter { !$0.isKeyboard }
            return devices.compactMap { option(for: $0, pad: pad) }
        }
        /// The picker option for a device on a pad, or `nil` when the pad already uses it.
        public func option(for device: ControllerDevice, pad: UInt8) -> CouchControllerOption? {
            let current = pad == 0
                ? inventory.playerOne ?? .keyboard
                : seats[pad].device
            guard device.id != current?.id else {
                return nil
            }
            let holder = holder(of: device)
            return CouchControllerOption(
                device: device,
                holder: holder,
                available: available(device, holder: holder, for: pad)
            )
        }
        private func available(_ device: ControllerDevice, holder: CouchHolder?, for pad: UInt8) -> Bool {
            let open = pad != 0 && seats[pad] == .open
            switch holder {
            case nil:
                return true
            case .playerOne:
                if device.isKeyboard {
                    return inventory.playerOne != nil || !open
                }
                return !open || keyboardSeat == nil
            case .seat(let other):
                guard !open, case .ready = seats[other] else {
                    return false
                }
                if pad != 0 {
                    return true
                }
                return device.isKeyboard
                    ? inventory.playerOne != nil
                    : inventory.playerOne != nil || keyboardSeat == nil
            }
        }
        /// The input that drives the open overlay or the seat waiting for input, if any.
        var navigationCandidate: UInt32? {
            if let device = controlsDevice {
                return device.id
            }
            if let newController {
                return newController.id
            }
            switch choosing {
            case .pad(let pad):
                return seats[pad].device?.id
            case .remote:
                return nil
            case nil:
                break
            }
            for pad in CouchSeats.pads {
                if case .passcode(let player, _) = seats[pad], let device = player.device {
                    return device.id
                }
            }
            return nil
        }
    }
    /// What happens on the couch.
    public enum Action: Equatable, Sendable {
        /// The saved accounts loaded.
        case accountsLoaded([AccountProfile])
        /// The stream session reported a couch event.
        case event(CouchSessionEvent)
        /// The stream is reconnecting, so the ready local players are remembered.
        case sessionReconnecting
        /// The stream reconnected, so the remembered players join again.
        case sessionReconnected
        /// The controller light colours changed.
        case lightsChanged(CouchLights)
        /// Someone chose the account the input on a pad joins with.
        case chooseAccount(pad: UInt8, account: UUID)
        /// Cancels a pad's join or removes its player.
        case cancel(pad: UInt8)
        /// The stream refused a command sent during a session.
        case commandRefused(StreamSessionID?, CouchCommand)
        /// Removes a notice.
        case dismissNotice(UUID)
        /// Someone answered who uses the controller that connected.
        case newController(CouchNewControllerChoice)
        /// Opens the controller picker for a pad.
        case pickController(pad: UInt8)
        /// Closes the controller picker.
        case cancelPicking
        /// A controller was chosen for a pad in the picker.
        case choose(pad: UInt8, device: ControllerDevice)
        /// Reads the connected controllers again.
        case loadInventory
        /// The connected controllers were read during a session.
        case inventoryLoaded(StreamSessionID?, CouchInventory)
        /// The stream ended, so the seats close.
        case sessionEnded
        /// Opens a pad player's controls settings.
        case openControls(pad: UInt8)
        /// Switches the open settings between the keyboard and the controller.
        case showKeyboardControls(Bool)
        /// Closes the settings once any save in progress finishes.
        case finishControls
        /// Closes the settings at once.
        case discardControls
        /// The presented overlay's actions.
        case overlay(PresentationAction<Overlay.Action>)
        /// A remote guest asked for a seat.
        case claimRemote(CouchRemoteInput)
        /// Someone chose the account a remote guest joins with.
        case chooseRemoteAccount(guest: KakusanGuestID, account: UUID)
        /// Cancels a remote guest's wait.
        case cancelRemote(KakusanGuestID)
        /// The host is joining a remote guest on a pad.
        case reserveRemote(CouchRemoteInput, pad: UInt8)
        /// The host seated a remote guest on a pad.
        case seatRemote(CouchRemoteInput, pad: UInt8)
        /// The host released a remote guest.
        case releaseRemote(KakusanGuestID)
        /// Shows a notice.
        case post(CouchNotice)
        /// Tells the parent about remote guests and saved controls.
        case delegate(Delegate)
    }
    /// Reaches the running stream.
    @Dependency(\.streamSession) var couch
    /// Loads the saved accounts.
    @Dependency(\.accounts) var accountsClient
    /// Identifies notices.
    @Dependency(\.uuid) var uuid
    /// Times how long notices stay.
    @Dependency(\.continuousClock) var clock
    /// How long a notice stays before it dismisses itself.
    static let noticeLifetime = Duration.seconds(6)
    /// Creates the couch.
    public init() {
    }
    public var body: some ReducerOf<Self> {
        CombineReducers {
            Reduce { state, action in
                reduceControls(&state, action)
            }
            Reduce(reduceRemote)
            Reduce { state, action in
                var effect = reduce(&state, action)
                if state.controlsPad != nil, state.controlsDevice == nil {
                    effect = .merge(effect, closeControls(&state, flushing: false))
                }
                let owner = state.active
                    ? state.expectedNavigationOwner
                    : nil
                guard owner != state.navigationOwner else {
                    return effect
                }
                state.navigationOwner = owner
                return .merge(effect, .run { [couch] _ in await couch.handNavigation(owner) })
            }
        }
        .ifLet(\.$overlay, action: \.overlay)
    }
}

extension CouchReducer.Overlay.State: Equatable {}

extension CouchReducer.Overlay.Action: Equatable, Sendable {}

extension CouchReducer {
    /// Identifies effects that are cancelled when the stream session ends.
    enum CancelID {
        /// The effects of the current stream session.
        case session
    }

    /// Handles seating, reconnection, light colours, the controller picker and notices.
    func reduce(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .accountsLoaded, .event, .newController, .chooseAccount, .cancel, .commandRefused:
            return reduceSeating(&state, action)
        case .sessionEnded:
            state.end()
            return .cancel(id: CancelID.session)
        case .sessionReconnecting:
            guard state.active, !state.reseating else {
                return .none
            }
            state.reseat = state.seats.seatedLocally
            return .none
        case .sessionReconnected:
            guard state.active else {
                return .none
            }
            state.reseating = true
            return reseat(&state)
        case .lightsChanged(let lights):
            guard state.active, lights.revision >= state.lights.revision else {
                return .none
            }
            state.lights = lights
            return .none
        case .pickController, .cancelPicking, .choose, .loadInventory, .inventoryLoaded, .dismissNotice:
            return reducePicking(&state, action)
        case .openControls, .showKeyboardControls, .finishControls, .discardControls, .overlay, .delegate,
             .claimRemote, .chooseRemoteAccount, .cancelRemote, .reserveRemote, .seatRemote, .releaseRemote,
             .post:
            return .none
        }
    }

    private func reduceSeating(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .accountsLoaded(let accounts):
            state.accounts = accounts
            return .none
        case .event(let event):
            let handled = handle(event, in: &state)
            guard state.reseating, case .dropped = event else {
                return handled
            }
            return .merge(handled, reseat(&state))
        case .newController(let choice):
            return answerNewController(choice, in: &state)
        case let .chooseAccount(pad, id):
            guard state.active, let account = state.accounts.first(where: { $0.id == id }) else {
                return .none
            }
            return apply(state.seats.chooseAccount(account, for: pad), to: &state)
        case .cancel(let pad):
            return cancelSeat(pad, in: &state)
        case let .commandRefused(session, command):
            guard state.active, session == state.session, case .join(let pad, _, _) = command else {
                return .none
            }
            return .send(.event(.joinFailed(pad: pad, failure: .notSent(nil))))
        default:
            return .none
        }
    }

    private func reducePicking(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .pickController(let pad):
            guard state.active, state.canPick(for: pad) else {
                return .none
            }
            state.picking = pad
            return refreshInventory(state, always: true)
        case .cancelPicking:
            state.picking = nil
            return .none
        case let .choose(pad, device):
            guard state.active, state.canPick(for: pad) else {
                return .none
            }
            return choose(device, for: pad, in: &state)
        case .loadInventory:
            return state.active
                ? refreshInventory(state, always: true)
                : .none
        case let .inventoryLoaded(session, inventory):
            guard state.active, session == state.session else {
                return .none
            }
            state.inventory = inventory
            return .none
        case .dismissNotice(let id):
            state.notices.removeAll { $0.id == id }
            return .none
        default:
            return .none
        }
    }

    private func handle(_ event: CouchSessionEvent, in state: inout State) -> Effect<Action> {
        guard state.active else {
            return .none
        }
        switch event {
        case .controllerConnected(let device):
            if state.picking == nil, state.overlay == nil, state.seats.pad(for: device.id) == nil {
                state.overlay = .newController(CouchNewControllerPrompt.State(device: device))
            }
            return refreshInventory(state)
        case .controllerRemoved(let id) where state.newController?.id == id:
            state.overlay = nil
        case .playerOneChanged(let id) where id != nil && state.newController?.id == id:
            state.overlay = nil
        case .controllerClaimed(let device) where state.picking != nil:
            guard let pad = state.picking, state.holder(of: device) == nil else {
                return .none
            }
            return choose(device, for: pad, in: &state)
        default:
            break
        }
        if case .controllerRemoved(let id) = event {
            return removeController(id, event: event, in: &state)
        }
        return seat(state.seats.apply(event), in: &state)
    }

    private func removeController(
        _ id: UInt32,
        event: CouchSessionEvent,
        in state: inout State
    ) -> Effect<Action> {
        if let pad = state.picking, pad != 0, state.seats.pad(for: id) == pad {
            state.picking = nil
        }
        let effect = seat(state.seats.apply(event), in: &state)
        return .merge(effect, refreshInventory(state))
    }

    private func answerNewController(_ choice: CouchNewControllerChoice,
                                     in state: inout State) -> Effect<Action> {
        guard state.active, let device = state.newController else {
            return .none
        }
        state.overlay = nil
        switch choice {
        case .playerOne:
            return choose(device, for: 0, in: &state)
        case .newPlayer:
            if let pad = state.picking, pad != 0 {
                return choose(device, for: pad, in: &state)
            }
            return seat(state.seats.claim(device, reserved: reservedPads(in: state)), in: &state)
        case .notNow:
            return .none
        }
    }

    private func reservedPads(in state: State) -> [UInt8: String] {
        state.inventory.chosenControllers.filter { pad, key in
            guard let device = state.inventory.controllers.first(where: { $0.preferenceKey == key }) else {
                return false
            }
            let holder = state.seats.pad(for: device.id)
            return device.id != state.inventory.playerOne?.id && (holder == nil || holder == pad)
        }
    }

    private func cancelSeat(_ pad: UInt8, in state: inout State) -> Effect<Action> {
        guard state.active else {
            return .none
        }
        let seated: Bool
        if case .ready = state.seats[pad] {
            seated = true
        } else {
            seated = false
        }
        var outcome = state.seats.cancel(pad)
        if seated {
            outcome.notice = .left(pad: pad)
        }
        if state.picking == pad {
            state.picking = nil
        }
        return apply(outcome, to: &state)
    }

    /// Handles the controls settings overlay and passes its saves on.
    func reduceControls(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .openControls(let pad):
            guard state.active, state.controls == nil, !state.devices(of: pad).isEmpty else {
                return .none
            }
            state.overlay = .controls(CouchControlsFeature.State(pad: pad))
            return .send(.overlay(.presented(.controls(.settings(.appeared)))))
        case .finishControls:
            return closeControls(&state, flushing: true)
        case .discardControls:
            return closeControls(&state, flushing: false)
        case let .overlay(.presented(.controls(.settings(.delegate(.committed(configuration)))))):
            return controlsSaved(configuration, in: &state)
        case .showKeyboardControls(let keyboard):
            guard let pad = state.controlsPad, state.devices(of: pad).count > 1,
                  state.controlsKeyboard != keyboard else {
                return .none
            }
            state.overlay?.modify(\.controls) {
                $0.keyboard = keyboard
            }
            return .send(.overlay(.presented(.controls(.settings(.cancelCapture)))))
        case .overlay(.presented(.controls(.settings(.delegate(.commitFailed))))):
            if state.overlay?.controls?.phase == .closing, state.controls?.setting.isBusy != true {
                state.overlay = nil
            }
            return .none
        default:
            return .none
        }
    }

    /// Closes the open controls settings without cancelling a save under way.
    ///
    /// With nothing saving the overlay is dismissed at once. Otherwise it moves to
    /// ``CouchControlsFeature/Phase/closing``, which hides it and keeps the presentation, and so the save's
    /// effect, alive until the save reports back.
    ///
    /// - Parameters:
    ///   - state: The couch.
    ///   - flushing: Whether a change still being made, such as a capture, is committed first.
    /// - Returns: The effect that commits the pending change, or none.
    func closeControls(_ state: inout State, flushing: Bool) -> Effect<Action> {
        guard let controls = state.overlay?.controls, controls.phase == .editing else {
            return .none
        }
        guard controls.settings.setting.isBusy else {
            state.overlay = nil
            return .none
        }
        state.overlay?.modify(\.controls) {
            $0.phase = .closing
        }
        return flushing
            ? .send(.overlay(.presented(.controls(.settings(.stop)))))
            : .none
    }

    private func controlsSaved(_ configuration: ControlsConfiguration,
                               in state: inout State) -> Effect<Action> {
        if state.overlay?.controls?.phase == .closing, state.controls?.setting.isBusy != true {
            state.overlay = nil
        }
        return .merge(
            .send(.delegate(.controlsCommitted(configuration))),
            .run { [couch] _ in
                await couch.reloadControls(configuration)
            }
        )
    }

    private func refreshInventory(_ state: State, always: Bool = false) -> Effect<Action> {
        guard always || state.picking != nil else {
            return .none
        }
        let session = state.session
        return .run { [couch] send in
            await send(.inventoryLoaded(session, await couch.couchInventory()))
        }
        .cancellable(id: CancelID.session)
    }

    private func choose(_ device: ControllerDevice, for pad: UInt8, in state: inout State) -> Effect<Action> {
        guard let option = state.option(for: device, pad: pad), option.available else {
            return .none
        }
        state.picking = nil
        guard pad != 0 else {
            return chooseForPlayerOne(device, option: option, in: &state)
        }
        guard let current = state.seats[pad].device else {
            var commands: [CouchCommand] = []
            if option.holder == .playerOne, !device.isKeyboard {
                commands.append(.assignPlayerOne(.keyboard))
                state.inventory.playerOne = nil
            }
            var outcome = state.seats.claim(device)
            outcome.commands = commands + outcome.commands
            return seat(outcome, in: &state)
        }
        return swap(device, into: pad, replacing: current, option: option, in: &state)
    }

    private func chooseForPlayerOne(
        _ device: ControllerDevice,
        option: CouchControllerOption,
        in state: inout State
    ) -> Effect<Action> {
        var commands: [CouchCommand] = []
        var notices: [CouchNotice] = []
        switch option.holder {
        case nil, .playerOne:
            commands = [.assignPlayerOne(device)]
        case .seat(let other):
            let given = state.inventory.playerOne ?? .keyboard
            _ = state.seats.setController(other, to: given)
            commands = [.route(pad: other, device: nil), .assignPlayerOne(device),
                        .route(pad: other, device: given)]
            notices.append(.switched(pad: other, device: given))
        }
        notices.insert(.switched(pad: 0, device: device), at: 0)
        state.inventory.playerOne = device.isKeyboard
            ? nil
            : device
        return run(commands, notices: notices, in: &state)
    }

    private func swap(
        _ device: ControllerDevice,
        into pad: UInt8,
        replacing current: ControllerDevice,
        option: CouchControllerOption,
        in state: inout State
    ) -> Effect<Action> {
        let commands: [CouchCommand]
        var notices: [CouchNotice] = []
        _ = state.seats.setController(pad, to: device)
        notices.append(.switched(pad: pad, device: device))
        switch option.holder {
        case nil:
            commands = [.route(pad: pad, device: device)]
        case .seat(let other):
            _ = state.seats.setController(other, to: current)
            commands = [.route(pad: other, device: nil), .route(pad: pad, device: nil),
                        .route(pad: pad, device: device), .route(pad: other, device: current)]
            notices.append(.switched(pad: other, device: current))
        case .playerOne:
            if device.isKeyboard, state.inventory.playerOne != nil {
                commands = [.route(pad: pad, device: device)]
            } else {
                commands = [.route(pad: pad, device: nil), .assignPlayerOne(current),
                            .route(pad: pad, device: device)]
                notices.append(.switched(pad: 0, device: current))
                state.inventory.playerOne = current.isKeyboard
                    ? nil
                    : current
            }
        }
        return run(commands, notices: notices, in: &state)
    }

    private func run(_ commands: [CouchCommand], notices: [CouchNotice],
                     in state: inout State) -> Effect<Action> {
        var effects = notices.map { post($0, in: &state) }
        let session = state.session
        effects.append(.run { [couch] send in
            for command in commands {
                _ = await couch.runCouchCommand(command)
            }
            await send(.inventoryLoaded(session, await couch.couchInventory()))
        }
        .cancellable(id: CancelID.session))
        return .merge(effects)
    }

    /// Shows a notice and dismisses it after the notice lifetime.
    func post(_ notice: CouchNotice, in state: inout State) -> Effect<Action> {
        let id = uuid()
        state.notices.append(CouchNoticeItem(id: id, notice: notice))
        return .run { [clock] send in
            try await clock.sleep(for: Self.noticeLifetime)
            await send(.dismissNotice(id))
        }
    }

    /// Applies an outcome and loads the saved accounts when a seat starts waiting for one.
    func seat(_ outcome: CouchOutcome, in state: inout State) -> Effect<Action> {
        let effect = apply(outcome, to: &state)
        guard state.choosing != nil, state.accounts.isEmpty else {
            return effect
        }
        return .merge(effect, .run { [accountsClient] send in
            let accounts = (try? await accountsClient.load().get()) ?? []
            await send(.accountsLoaded(accounts))
        }
        .cancellable(id: CancelID.session))
    }

    /// Starts the join again for remembered players whose pads are open, and stops once all are back.
    func reseat(_ state: inout State) -> Effect<Action> {
        let outcome = state.seats.reseat(state.reseat)
        for case .join(let pad, _, _) in outcome.commands {
            state.reseat[pad] = nil
        }
        if state.reseat.isEmpty {
            state.reseating = false
        }
        return apply(outcome, to: &state)
    }

    /// Sends an outcome's commands, delegate actions and notice.
    ///
    /// A command the stream refuses comes back as `commandRefused`.
    func apply(_ outcome: CouchOutcome, to state: inout State) -> Effect<Action> {
        var effects: [Effect<Action>] = outcome.remote.map { .send(.delegate(Self.delegate(for: $0))) }
        let commands = outcome.commands
        if !commands.isEmpty {
            let session = state.session
            effects.append(.run { [couch] send in
                for command in commands {
                    let accepted = await couch.runCouchCommand(command)
                    if !accepted {
                        await send(.commandRefused(session, command))
                    }
                }
            }
            .cancellable(id: CancelID.session))
        }
        if let notice = outcome.notice {
            effects.append(post(notice, in: &state))
        }
        return .merge(effects)
    }
}

/// The question shown when a controller connects during a stream: who is going to use it.
///
/// The answer is a `CouchReducer/Action/newController(_:)` intent on the couch, which owns the seats.
@Reducer
public struct CouchNewControllerPrompt {
    /// The prompt's state.
    @ObservableState
    public struct State: Equatable {
        /// The controller that connected.
        public let device: ControllerDevice

        /// Asks about a controller.
        ///
        /// - Parameter device: The controller that connected.
        public init(device: ControllerDevice) {
            self.device = device
        }
    }

    /// The prompt has no actions of its own.
    public enum Action: Equatable, Sendable {}

    /// Creates the prompt.
    public init() {
    }

    /// The reducer.
    public var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

/// One player's controller or keyboard settings, presented over the stream.
///
/// The settings themselves are the Controls pane's ``ControlsSettingsFeature``; this feature adds which pad
/// they belong to, whether the keyboard or the controller is shown, and whether closing waits for a save.
@Reducer
public struct CouchControlsFeature {
    /// Whether the settings are open or closing.
    public enum Phase: Equatable, Sendable {
        /// The player edits the settings.
        case editing
        /// The settings are closed and no longer shown; the presentation stays only until the save under way
        /// finishes.
        case closing
    }

    /// The settings' state.
    @ObservableState
    public struct State: Equatable {
        /// The pad whose player the settings belong to.
        public let pad: UInt8
        /// Whether the keyboard's bindings are shown instead of the controller's.
        public var keyboard = false
        /// Whether the settings are open or closing.
        public var phase = Phase.editing
        /// The Controls pane's state.
        public var settings = ControlsSettingsFeature.State()

        /// Opens the settings for a pad.
        ///
        /// - Parameters:
        ///   - pad: The pad.
        ///   - keyboard: Whether the keyboard's bindings are shown.
        ///   - settings: The Controls pane's state to start from.
        public init(
            pad: UInt8,
            keyboard: Bool = false,
            settings: ControlsSettingsFeature.State = ControlsSettingsFeature.State()
        ) {
            self.pad = pad
            self.keyboard = keyboard
            self.settings = settings
        }
    }

    /// What happens in the settings.
    public enum Action: Equatable, Sendable {
        /// The Controls pane's actions.
        case settings(ControlsSettingsFeature.Action)
    }

    /// Creates the feature.
    public init() {}

    /// The reducer.
    public var body: some ReducerOf<Self> {
        Scope(state: \.settings, action: \.settings) {
            ControlsSettingsFeature()
        }
    }
}
