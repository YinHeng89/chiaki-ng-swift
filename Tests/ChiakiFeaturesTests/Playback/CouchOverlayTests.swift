import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

@MainActor @Suite struct CouchOverlayTests {
    private let guest = ControllerDevice(
        id: 9, preferenceKey: "unit:9", name: "DualShock 4", transport: "USB", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true
    )

    private let newcomer = ControllerDevice(
        id: 12, preferenceKey: "unit:12", name: "DualSense", transport: "USB", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true
    )

    private func seatedState() -> CouchReducer.State {
        var state = CouchReducer.State()
        state.begin(.cloud, hostAccount: nil)
        _ = state.seats.claim(guest)
        return state
    }

    @Test func aNewControllerWaitsUntilTheOpenControlsClose() async {
        var initial = seatedState()
        initial.overlay = .controls(CouchControlsFeature.State(pad: 1))
        let store = TestStore(initialState: initial) {
            CouchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off
        await store.send(.event(.controllerConnected(newcomer)))
        #expect(store.state.controlsPad == 1)
        #expect(store.state.newController == nil)
        await store.send(.discardControls) {
            $0.overlay = nil
        }
        await store.send(.event(.controllerConnected(newcomer))) {
            $0.overlay = .newController(CouchNewControllerPrompt.State(device: newcomer))
        }
        await store.send(.discardControls)
        #expect(store.state.newController == newcomer)
    }

    @Test func dismissingTheControlsLetsTheSaveUnderWayFinish() async {
        let clock = TestClock()
        let store = TestStore(initialState: seatedState()) {
            CouchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.settings = SettingsClient(
                read: { type in
                    type.defaultSetting
                },
                write: { _ in
                    try? await clock.sleep(for: .seconds(1))
                }
            )
            $0.controllers = .testValue
            $0.streamSession.reloadControls = { _ in }
        }
        store.exhaustivity = .off
        await store.send(.openControls(pad: 1))
        await store.receive(\.overlay.presented.controls.settings.loaded)
        var edited = ControlsConfiguration()
        var preferences = ControllerPreferences()
        preferences.invertRightY = true
        edited.controllers[guest.preferenceKey] = preferences
        await store.send(.overlay(.presented(.controls(.settings(.edit(edited))))))
        await store.send(.discardControls)
        #expect(store.state.controlsPad == nil)
        #expect(store.state.overlay?.controls?.phase == .closing)
        await clock.advance(by: .seconds(1))
        await store.receive(\.overlay.presented.controls.settings.delegate.committed)
        await store.receive { action in
            if case .delegate(.controlsCommitted(let saved)) = action {
                return saved.controllers[guest.preferenceKey]?.invertRightY == true
            }
            return false
        }
        #expect(store.state.overlay == nil)
    }

    @Test func endingTheSessionDismissesTheOverlay() async {
        var initial = seatedState()
        initial.overlay = .newController(CouchNewControllerPrompt.State(device: newcomer))
        let store = TestStore(initialState: initial) {
            CouchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off
        await store.send(.sessionEnded) {
            $0.overlay = nil
        }
        #expect(!store.state.active)
    }
}
