import ChiakiModels
import ChiakiClients
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

private let reducerGuest = ControllerDevice(
    id: 9, preferenceKey: "unit:9", name: "DualShock 4", transport: "USB", individual: true,
    rumble: true, lights: true, motion: true, touchpad: true
)

private func activeState(_ console: CouchConsole) -> CouchReducer.State {
    var state = CouchReducer.State()
    state.begin(console, hostAccount: nil)
    return state
}

@MainActor @Test func refusedJoinFreesTheSeatAndExplainsWhy() async {
    let clock = TestClock()
    let id = UUID()
    let store = TestStore(initialState: activeState(.ps4)) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.continuousClock = clock
        $0.streamSession.runCouchCommand = { command in
            if case .join = command {
                return false
            }
            return true
        }
    }
    await store.send(.event(.controllerClaimed(reducerGuest))) {
        _ = $0.seats.claim(reducerGuest)
    }
    await store.receive(.commandRefused(nil, .join(pad: 1, controllerType: 2, accountID: nil)))
    await store.receive(.event(.joinFailed(pad: 1, failure: .notSent(nil)))) {
        _ = $0.seats.apply(.joinFailed(pad: 1, failure: .notSent(nil)))
        $0.notices = [CouchNoticeItem(id: id, notice: .joinFailed(pad: 1, failure: .notSent(nil)))]
    }
    await clock.advance(by: CouchReducer.noticeLifetime)
    await store.receive(.dismissNotice(id)) {
        $0.notices = []
    }
}

@MainActor @Test func playerControlsSaveReloadsInputAndCloses() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(reducerGuest)
    let reloaded = LockIsolated<[ControlsConfiguration]>([])
    var saved = ControlsConfiguration()
    saved.controllers[reducerGuest.preferenceKey] = {
        var preferences = ControllerPreferences()
        preferences.invertRightY = true
        return preferences
    }()
    let saveID = UUID()
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .constant(saveID)
        $0.streamSession.reloadControls = { configuration in
            reloaded.withValue { $0.append(configuration) }
        }
        $0.settings = .inMemory()
        $0.controllers = .testValue
    }
    store.exhaustivity = .off
    await store.send(.openControls(pad: 1)) {
        $0.overlay = .controls(CouchControlsFeature.State(pad: 1))
        $0.navigationOwner = 9
    }
    await store.receive(\.overlay.presented.controls.settings.loaded)
    await store.send(.overlay(.presented(.controls(.settings(.edit(saved))))))
    await store.receive(\.overlay.presented.controls.settings.delegate.committed)
    await store.send(.finishControls) {
        $0.overlay = nil
    }
    #expect(reloaded.value.last?.controllers[reducerGuest.preferenceKey]?.invertRightY == true)
}

@MainActor @Test func controlsCloseWhenTheirPlayerLeaves() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(reducerGuest)
    initial.overlay = .controls(CouchControlsFeature.State(pad: 1))
    initial.navigationOwner = 9
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
    }
    store.exhaustivity = .off
    await store.send(.event(.controllerRemoved(9))) {
        $0.overlay = nil
        $0.navigationOwner = nil
    }
    #expect(store.state.seats[1] == .open)
}

private let reducerHostPad = ControllerDevice(
    id: 4, preferenceKey: "unit:4", name: "DualSense Wireless Controller", transport: "USB",
    individual: true, rumble: true, lights: true, motion: true, touchpad: true
)

private let reducerOther = ControllerDevice(
    id: 12, preferenceKey: "unit:12", name: "Xbox Wireless Controller", transport: "Bluetooth",
    individual: true, rumble: true, lights: false, motion: false, touchpad: false, family: .xbox
)

@MainActor private func recordingStore(
    _ initial: CouchReducer.State,
    inventory: CouchInventory,
    commands: LockIsolated<[CouchCommand]>
) -> TestStoreOf<CouchReducer> {
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.streamSession.runCouchCommand = { command in
            commands.withValue { $0.append(command) }
            return true
        }
        $0.streamSession.couchInventory = {
            inventory
        }
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func newControllerAsksWhoIsUsingIt() async {
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(activeState(.ps4), inventory: CouchInventory(), commands: commands)
    await store.send(.event(.controllerConnected(reducerGuest))) {
        $0.overlay = .newController(CouchNewControllerPrompt.State(device: reducerGuest))
        $0.navigationOwner = 9
    }
    await store.send(.newController(.playerOne)) {
        $0.overlay = nil
        $0.navigationOwner = nil
    }
    await store.finish()
    #expect(commands.value == [.assignPlayerOne(reducerGuest)])
    await store.send(.event(.controllerConnected(reducerGuest))) {
        $0.overlay = .newController(CouchNewControllerPrompt.State(device: reducerGuest))
    }
    await store.send(.newController(.newPlayer)) {
        $0.overlay = nil
    }
    #expect(store.state.seats.pad(for: reducerGuest.id) == 1)
}

@MainActor @Test func newControllerPromptClosesWhenItUnplugsOrIsDeclined() async {
    let store = TestStore(initialState: activeState(.cloud)) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
    }
    await store.send(.event(.controllerConnected(reducerGuest))) {
        $0.overlay = .newController(CouchNewControllerPrompt.State(device: reducerGuest))
        $0.navigationOwner = 9
    }
    await store.send(.event(.controllerRemoved(9))) {
        $0.overlay = nil
        $0.navigationOwner = nil
    }
    await store.send(.event(.controllerConnected(reducerGuest))) {
        $0.overlay = .newController(CouchNewControllerPrompt.State(device: reducerGuest))
        $0.navigationOwner = 9
    }
    await store.send(.newController(.notNow)) {
        $0.overlay = nil
        $0.navigationOwner = nil
    }
    #expect(store.state.seats[1] == .open)
}

@MainActor @Test func pickingAnotherSeatsControllerSwapsThem() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(reducerGuest)
    _ = initial.seats.claim(reducerOther)
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(
        initial,
        inventory: CouchInventory(
            controllers: [reducerHostPad, reducerGuest, reducerOther],
            playerOne: reducerHostPad
        ),
        commands: commands
    )
    await store.send(.pickController(pad: 1)) {
        $0.picking = 1
    }
    await store.receive(\.inventoryLoaded)
    let option = store.state.controllerOptions(for: 1).first { $0.id == reducerOther.id }
    #expect(option?.holder == .seat(2))
    #expect(option?.available == true)
    await store.send(.choose(pad: 1, device: reducerOther)) {
        $0.picking = nil
    }
    await store.finish()
    #expect(store.state.seats[1].device == reducerOther)
    #expect(store.state.seats[2].device == reducerGuest)
    #expect(commands.value == [
        .route(pad: 2, device: nil), .route(pad: 1, device: nil),
        .route(pad: 1, device: reducerOther), .route(pad: 2, device: reducerGuest)
    ])
}

@MainActor @Test func pickingPlayerOnesControllerHandsPlayerOneTheOldOne() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(reducerGuest)
    initial.inventory = CouchInventory(controllers: [reducerHostPad, reducerGuest], playerOne: reducerHostPad)
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(initial, inventory: initial.inventory, commands: commands)
    await store.send(.choose(pad: 1, device: reducerHostPad))
    await store.finish()
    #expect(store.state.seats[1].device == reducerHostPad)
    #expect(commands.value == [
        .route(pad: 1, device: nil), .assignPlayerOne(reducerGuest), .route(pad: 1, device: reducerHostPad)
    ])
    #expect(store.state.notices.map(\.notice) == [
        .switched(pad: 1, device: reducerHostPad), .switched(pad: 0, device: reducerGuest)
    ])
}

@MainActor @Test func anOptionsPressWhilePickingTakesTheSeat() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(reducerGuest)
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(initial, inventory: CouchInventory(), commands: commands)
    await store.send(.pickController(pad: 1))
    await store.send(.event(.controllerClaimed(reducerOther)))
    await store.finish()
    #expect(store.state.picking == nil)
    #expect(store.state.seats[1].device == reducerOther)
    #expect(commands.value == [.route(pad: 1, device: reducerOther)])
    #expect(store.state.seats.takenCount == 1)
}

@MainActor @Test func addingAPlayerWithPlayerOnesControllerMovesPlayerOneToTheKeyboard() async {
    var initial = activeState(.cloud)
    initial.inventory = CouchInventory(controllers: [reducerHostPad], playerOne: reducerHostPad)
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(initial, inventory: initial.inventory, commands: commands)
    let option = store.state.controllerOptions(for: 1).first { $0.id == reducerHostPad.id }
    #expect(option?.available == true)
    await store.send(.choose(pad: 1, device: reducerHostPad))
    await store.finish()
    #expect(store.state.seats[1].device == reducerHostPad)
    #expect(commands.value == [
        .assignPlayerOne(.keyboard), .route(pad: 1, device: reducerHostPad),
        .join(pad: 1, controllerType: 6, accountID: nil)
    ])
}

@MainActor @Test func playerOneTakingTheKeyboardBackGivesTheSeatTheirController() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(.keyboard)
    initial.inventory = CouchInventory(controllers: [reducerHostPad], playerOne: reducerHostPad)
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(initial, inventory: initial.inventory, commands: commands)
    await store.send(.choose(pad: 0, device: .keyboard))
    await store.finish()
    #expect(store.state.seats[1].device == reducerHostPad)
    #expect(commands.value == [
        .route(pad: 1, device: nil), .assignPlayerOne(.keyboard), .route(pad: 1, device: reducerHostPad)
    ])
}

@MainActor @Test func aSeatThatIsStillJoiningCannotBeSwappedWith() {
    var state = activeState(.ps5)
    _ = state.seats.claim(reducerGuest)
    _ = state.seats.claim(.keyboard)
    _ = state.seats.chooseAccount(
        AccountProfile(
            id: UUID(),
            name: "Mika",
            method: .npsso,
            accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(2))
        ),
        for: 2
    )
    _ = state.seats.apply(.confirmed(pad: 2, color: 0))
    #expect(state.option(for: reducerGuest, pad: 2)?.available == false)
}

@MainActor @Test func removingAPlayerSaysTheyLeft() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(reducerGuest)
    let commands = LockIsolated<[CouchCommand]>([])
    let store = recordingStore(initial, inventory: CouchInventory(), commands: commands)
    await store.send(.cancel(pad: 1))
    #expect(store.state.notices.map(\.notice) == [.left(pad: 1)])
    await store.finish()
    #expect(commands.value == [.remove(pad: 1), .route(pad: 1, device: nil)])
}

@MainActor @Test func playerOneCanOpenControlsForTheirControllerAndKeyboard() async {
    var initial = activeState(.cloud)
    initial.inventory = CouchInventory(controllers: [reducerHostPad], playerOne: reducerHostPad)
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory()
        $0.controllers = .testValue
    }
    store.exhaustivity = .off
    await store.send(.openControls(pad: 0)) {
        $0.overlay = .controls(CouchControlsFeature.State(pad: 0))
    }
    #expect(store.state.controlsDevice == reducerHostPad)
    await store.send(.showKeyboardControls(true)) {
        $0.overlay?.modify(\.controls) {
            $0.keyboard = true
        }
    }
    #expect(store.state.controlsDevice == .keyboard)
    await store.send(.discardControls) {
        $0.overlay = nil
    }
}

@MainActor @Test func aKeyboardSeatCanOpenControlsButPlayerOneLosesTheKeyboardTab() async {
    var initial = activeState(.cloud)
    _ = initial.seats.claim(.keyboard)
    initial.inventory = CouchInventory(controllers: [reducerHostPad], playerOne: reducerHostPad)
    #expect(initial.devices(of: 0) == [reducerHostPad])
    #expect(StreamPlayersPanel.controls(for: initial).contains(.playerControls(1)))
    #expect(StreamPlayersPanel.controls(for: initial).contains(.playerControls(0)))
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory()
        $0.controllers = .testValue
    }
    store.exhaustivity = .off
    await store.send(.openControls(pad: 1))
    #expect(store.state.controlsDevice == .keyboard)
    #expect(store.state.navigationOwner == nil)
}

@MainActor @Test func newControllerPromptClosesWhenThatControllerBecomesPlayerOne() async {
    var initial = activeState(.cloud)
    initial.overlay = .newController(CouchNewControllerPrompt.State(device: reducerOther))
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
    }
    store.exhaustivity = .off
    await store.send(.event(.playerOneChanged(reducerHostPad.id)))
    #expect(store.state.newController == reducerOther)
    await store.send(.event(.playerOneChanged(nil)))
    #expect(store.state.newController == reducerOther)
    await store.send(.event(.playerOneChanged(reducerOther.id))) {
        $0.overlay = nil
    }
}

@MainActor @Test func aLateInventoryFromAnEndedSessionNeverReachesTheNextOne() async {
    let ended = StreamSessionID()
    let current = StreamSessionID()
    var initial = CouchReducer.State()
    initial.begin(.ps5, hostAccount: nil, session: current)
    let store = TestStore(initialState: initial) {
        CouchReducer()
    }
    let late = CouchInventory(controllers: [reducerGuest], playerOne: reducerGuest)
    await store.send(.inventoryLoaded(ended, late))
    await store.send(.commandRefused(ended, .join(pad: 1, controllerType: 2, accountID: nil)))
    #expect(store.state.inventory == CouchInventory())
}

@MainActor @Test func endingTheCouchSessionCancelsItsInventoryRequest() async {
    let session = StreamSessionID()
    let requested = LockIsolated(false)
    var initial = CouchReducer.State()
    initial.begin(.ps5, hostAccount: nil, session: session)
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.streamSession.couchInventory = {
            requested.setValue(true)
            try? await Task.sleep(for: .seconds(60))
            return CouchInventory(controllers: [reducerGuest])
        }
    }
    store.exhaustivity = .off
    await store.send(.loadInventory)
    await store.send(.sessionEnded) {
        $0.active = false
    }
    await store.finish()
    #expect(store.state.inventory == CouchInventory())
    #expect(store.state.session == nil)
}
