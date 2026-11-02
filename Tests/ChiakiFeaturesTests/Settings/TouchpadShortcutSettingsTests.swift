import ChiakiModels
import Foundation
import Testing
import ChiakiClients
import ComposableArchitecture
@testable import ChiakiFeatures

@MainActor
@Suite struct TouchpadShortcutSettingsTests {
    let id = UUID()

    func store() -> TestStoreOf<ControlsSettingsFeature> {
        let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
            ControlsSettingsFeature()
        } withDependencies: { [id] in
            $0.uuid = .constant(id)
            $0.settings = .inMemory()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    @Test func recordingAcceptsOnlyItsOwnAttempt() async {
        let store = store()
        let chord = KeyChord(keyCode: 9, modifiers: [.control, .option], label: "V")
        await store.send(.recordTouchpadShortcut) {
            $0.mode = .recordingShortcut(id)
        }
        await store.send(.recordedTouchpadShortcut(UUID(), chord))
        #expect(store.state.draft.touchpadShortcut.key != chord)
        await store.send(.recordedTouchpadShortcut(id, chord)) {
            $0.mode = .idle
            $0.draft.touchpadShortcut.key = chord
        }
        await store.receive(\.delegate.committed)
        await store.send(.recordedTouchpadShortcut(id, KeyChord(keyCode: 1, modifiers: .command, label: "S")))
        #expect(store.state.draft.touchpadShortcut.key == chord)
    }

    @Test func recordingRejectsReservedAndUnanchoredKeys() async {
        let store = store()
        await store.send(.recordTouchpadShortcut) {
            $0.mode = .recordingShortcut(id)
        }
        await store.send(.recordedTouchpadShortcut(
            id,
            KeyChord(keyCode: 12, modifiers: .command, label: "Q")
        )) {
            $0.notice = .shortcutNotAllowed
        }
        await store.send(.recordedTouchpadShortcut(id, KeyChord(keyCode: 17, modifiers: .shift, label: "T")))
        await store.send(.cancelTouchpadShortcut) {
            $0.mode = .idle
        }
        #expect(store.state.draft.touchpadShortcut == .standard)
        #expect(store.state.setting == .ready(saved: ControlsConfiguration()))
    }

    @Test func recordingYieldsToAButtonCapture() async {
        let store = store()
        await store.send(.recordTouchpadShortcut) {
            $0.mode = .recordingShortcut(id)
        }
        await store.send(.capture(.cross)) {
            $0.mode = .capturing(ControlsCapture(id: id, target: .cross, presetID: $0.draft.selectedPresetID))
        }
        await store.send(.recordTouchpadShortcut) {
            $0.mode = .recordingShortcut(id)
        }
    }

    @Test func theTouchpadComboValidatesBeforeChanging() async {
        let store = store()
        await store.send(.setTouchpadButtons([9, 10])) {
            $0.draft.touchpadShortcut.buttons = [9, 10]
        }
        await store.send(.setTouchpadButtons([7, 8])) {
            $0.notice = .touchpadButtonsInvalid
        }
        await store.send(.setTouchpadButtons([])) {
            $0.draft.touchpadShortcut.buttons = []
            $0.notice = .quiet
        }
    }

    @Test func theStreamMenuComboValidatesAgainstTheTouchpadCombo() async {
        let store = store()
        await store.send(.setStreamMenuButtons([9, 10, 6])) {
            $0.draft.streamMenuShortcut.buttons = [9, 10, 6]
        }
        await store.send(.setStreamMenuButtons([4, 8, 9])) {
            $0.notice = .streamMenuButtonsInvalid
        }
        await store.send(.setStreamMenuButtons([9]))
        await store.send(.setStreamMenuButtons([7, 8])) {
            $0.draft.streamMenuShortcut = .standard
            $0.notice = .quiet
        }
    }

    @Test func editingAControllersBindingNeverChangesTheSharedStandard() async {
        let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
            ControlsSettingsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.settings = .inMemory()
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.ownPreset(key: "xbox", name: "Xbox", touchpad: false, gyro: true))
        let owned = store.state.draft.controllers["xbox"]?.presetID
        #expect(owned != nil)
        if let owned {
            await store.send(.assignBinding(
                owned,
                InputBinding(source: .gamepadButton, code: 16, label: "", target: .options)
            ))
        }
        #expect(store.state.draft.preset(for: nil, touchpad: true) == .standard)
        let xbox = store.state.draft.preset(for: store.state.draft.controllers["xbox"], touchpad: false)
        #expect(xbox.bindings
            .contains { $0.source == .gamepadButton && $0.code == 16 && $0.target == .options })
    }
}
