@testable import ChiakiFeatures
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
import MenuFocus
import ChiakiTestSupport

private let toPlayersPanel = [MenuCommand](
    repeating: .next,
    count: StreamMenuPanel.allCases.firstIndex(of: .players) ?? 0
)

extension MenuFocusTests {
    @Test func backFromTheControllerPickerReturnsToTheSeatThatOpenedIt() async {
        let couch = playersCouchStore()
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(
                store: playersMenuStore(), stopTitle: "Disconnect", couch: couch
            ))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(400)
        await harness.send(toPlayersPanel)
        await harness.pause(200)
        await harness.send([.up, .left, .down])
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(couch.picking == 1)
        await harness.send(.back)
        await harness.pause(300)
        #expect(couch.picking == nil)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(couch.controlsPad == 1)
    }

    @Test func focusReturnsToThePlayersPanelAfterAnOverlayAboveItCloses() async {
        let couch = playersCouchStore()
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(
                store: playersMenuStore(), stopTitle: "Disconnect", couch: couch
            ))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        let overlay = UUID()
        defer {
            testNavigator.inputGate.presentations.remove(overlay)
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(400)
        await harness.send(toPlayersPanel)
        await harness.pause(200)
        await harness.send([.up, .left])
        await harness.pause(150)
        testNavigator.inputGate.presentations.insert(overlay)
        await harness.pause(300)
        testNavigator.inputGate.presentations.remove(overlay)
        await harness.pause(300)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(couch.controlsPad == 1)
    }

    @Test func playerControlsOverlayStartsFocusedReachesTheInputChoiceAndBackFinishes() async {
        let couch = controlsOverlayStore()
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CouchControlsOverlay(store: couch))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(500)
        #expect(testNavigator.hasControlFocus(in: harness.window))
        await harness.send([.right, .confirm])
        await harness.pause(200)
        #expect(couch.controlsKeyboard)
        await harness.send(.back)
        await harness.pause(200)
        #expect(couch.controlsPad == nil)
    }
}

@MainActor
private func playersMenuStore() -> StoreOf<StreamMenuReducer> {
    Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.loadTuning = { _ in
            StreamTuningConfiguration(nativeHeight: 1080)
        }
        $0.streamSession.saveTuning = { _, _ in
        }
    }
}

@MainActor
private func playersCouchStore() -> StoreOf<CouchReducer> {
    let host = AccountProfile(
        id: UUID(),
        name: "Host",
        method: .npsso,
        accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(1))
    )
    let guest = AccountProfile(
        id: UUID(),
        name: "Mika",
        method: .npsso,
        accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(2))
    )
    var state = CouchReducer.State()
    state.begin(.ps5, hostAccount: host.id)
    state.accounts = [host, guest]
    _ = state.seats.claim(ControllerDevice(
        id: 2, preferenceKey: "unit:2", name: "DualSense", transport: "Bluetooth", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true
    ))
    _ = state.seats.chooseAccount(guest, for: 1)
    _ = state.seats.apply(.confirmed(pad: 1, color: 0xff5f57))
    return Store(initialState: state) {
        Reduce<CouchReducer.State, CouchReducer.Action> { state, action in
            switch action {
            case .pickController(let pad):
                state.picking = pad
            case .cancelPicking:
                state.picking = nil
            case .openControls(let pad):
                state.overlay = .controls(CouchControlsFeature.State(pad: pad))
            default:
                break
            }
            return .none
        }
    }
}

@MainActor
private func controlsOverlayStore() -> StoreOf<CouchReducer> {
    var state = CouchReducer.State()
    state.inventory = CouchInventory(playerOne: ControllerDevice(
        id: 1, preferenceKey: "unit:1", name: "DualSense", transport: "USB", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true
    ))
    state.overlay = .controls(CouchControlsFeature.State(
        pad: 0,
        settings: ControlsSettingsFeature.State.loaded()
    ))
    return Store(initialState: state) {
        Reduce<CouchReducer.State, CouchReducer.Action> { state, action in
            switch action {
            case .showKeyboardControls(let keyboard):
                state.overlay?.modify(\.controls) {
                    $0.keyboard = keyboard
                }
            case .finishControls, .discardControls:
                state.overlay = nil
            default:
                break
            }
            return .none
        }
    }
}
