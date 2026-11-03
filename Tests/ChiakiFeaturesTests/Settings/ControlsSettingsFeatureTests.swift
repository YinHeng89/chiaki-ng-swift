import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

extension ControlsSettingsFeature.State {
    static func loaded(_ configuration: ControlsConfiguration = ControlsConfiguration()) -> Self {
        var state = Self()
        state.setting = .ready(saved: configuration)
        state.draft = configuration
        return state
    }
}

@MainActor
@Suite struct ControlsSettingsFeatureTests {
    let id = UUID()

    var operation: OperationID {
        OperationID(uuid: id)
    }

    func store(
        _ state: ControlsSettingsFeature.State = .loaded(),
        clock: TestClock<Duration> = TestClock(),
        settings: SettingsClient = .inMemory()
    ) -> TestStoreOf<ControlsSettingsFeature> {
        TestStore(initialState: state) {
            ControlsSettingsFeature()
        } withDependencies: { [id] in
            $0.uuid = .constant(id)
            $0.continuousClock = clock
            $0.settings = settings
        }
    }

    @Test func aKeyAlreadyInUseSwapsWithTheControlThatHadIt() async throws {
        let clock = TestClock()
        let store = store(clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let original = store.state.draft
        await store.send(.capture(.cross)) {
            $0.mode = .capturing(ControlsCapture(id: id, target: .cross, presetID: original.selectedPresetID))
        }
        await store.send(.captured(UUID(), 7, "X"))
        #expect(store.state.capture != nil)
        await store.send(.captured(id, 51, "Delete"))
        await store.receive(\.delegate.committed)
        let keys = store.state.draft.preset().bindings.filter { $0.source == .macKey }
        #expect(keys.contains(InputBinding(source: .macKey, code: 51, label: "Delete", target: .cross)))
        #expect(keys.contains(InputBinding(source: .macKey, code: 36, label: "Return", target: .circle)))
        #expect(keys.filter { $0.code == 51 }.count == 1)
        #expect(store.state.mode == .idle)
        #expect(store.state.change?.summary == .moved(
            InputBinding(source: .macKey, code: 51, label: "Delete", target: .cross),
            from: .circle,
            exchanged: InputBinding(source: .macKey, code: 36, label: "Return", target: .circle)
        ))
        #expect(try store.state.draft.validated() == store.state.draft)
        #expect(store.state.draft.preset().bindings.filter { $0.source == .gamepadButton }
            == original.preset().bindings.filter { $0.source == .gamepadButton })
        await clock.advance(by: ControlsSettingsFeature.changeLifetime)
        await store.receive(.changeExpired(id))
        #expect(store.state.change == nil)
    }

    @Test func undoPutsBackTheConfigurationFromBeforeTheChange() async {
        let store = store()
        store.exhaustivity = .off(showSkippedAssertions: false)
        let original = store.state.draft
        await store.send(.capture(.cross))
        await store.send(.captured(id, 13, "W"))
        await store.receive(\.delegate.committed)
        #expect(store.state.draft != original)
        await store.send(.undoChange(UUID()))
        #expect(store.state.change != nil)
        await store.send(.undoChange(id))
        await store.receive(\.delegate.committed)
        #expect(store.state.draft == original)
        #expect(store.state.change == nil)
    }

    @Test func aCancelledControllerCaptureTakesBackThePresetItCreated() async {
        let pad = ControllerDevice(
            id: 4,
            preferenceKey: "pad",
            name: "Pad",
            transport: "USB",
            individual: true,
            rumble: true,
            lights: false,
            motion: false,
            touchpad: false,
            family: .xbox
        )
        var state = ControlsSettingsFeature.State.loaded()
        state.devices = [pad]
        let store = store(state)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let original = store.state.draft
        await store.send(.captureControllerButton(pad, .cross))
        #expect(store.state.draft.presets.count == 2)
        #expect(store.state.capture?.restores == original)
        await store.send(.cancelCapture)
        #expect(store.state.draft == original)
    }

    @Test func aDisconnectedControllerWaitsForATappedButton() async throws {
        let clock = TestClock()
        let store = store(clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        var configuration = ControlsConfiguration()
        let pad = ControllerDevice(
            id: 4,
            preferenceKey: "pad",
            name: "Pad",
            transport: "USB",
            individual: true,
            rumble: true,
            lights: false,
            motion: false,
            touchpad: false,
            family: .xbox
        )
        configuration.remembered["pad"] = RememberedController(pad, seen: Date(timeIntervalSince1970: 0))
        await store.send(.edit(configuration))
        await store.receive(\.delegate.committed)
        let away = try #require(store.state.device("pad"))
        await store.send(.captureControllerButton(away, .touchpad))
        await clock.advance(by: ControlsSettingsFeature.buttonCaptureTimeout * 2)
        #expect(store.state.capture != nil)
        await store.send(.captured(id, 10, ""))
        await store.receive(\.delegate.committed)
        let preset = try #require(store.state.draft.controllers["pad"]?.presetID)
        #expect(store.state.draft.presets.first { $0.id == preset }?.bindings.contains {
            $0.source == .gamepadButton && $0.code == 10 && $0.target == .touchpad
        } == true)
        #expect(try store.state.draft.validated() == store.state.draft)
    }

    @Test func editsBeforeTheConfigurationLoadsAreRefused() async {
        let store = store(ControlsSettingsFeature.State())
        var edited = ControlsConfiguration()
        edited.keyboardMode = .controller
        await store.send(.edit(edited))
        await store.send(.binding(.set(\.draft, edited)))
        await store.send(.setStreamMenuButtons([9, 10, 6]))
        await store.send(.capture(.cross))
        #expect(store.state.setting == .unloaded)
    }

    @Test func anInvalidConfigurationIsHeldUntilAValidEditSavesIt() async {
        let store = store()
        var invalid = ControlsConfiguration()
        invalid.presets[0].name = ""
        await store.send(.edit(invalid)) {
            $0.draft = invalid
            $0.setting = .saveFailed(saved: ControlsConfiguration(), draft: invalid, failure: .invalid)
            $0.notice = .invalidConfiguration
        }
        var valid = invalid
        valid.presets[0].name = "Mine"
        await store.send(.renamePreset(valid.presets[0].id, "Mine")) {
            $0.draft = valid
            $0.notice = .quiet
            $0.setting = .saving(operation, saved: ControlsConfiguration(), draft: valid)
        }
        await store.receive(.saved(operation, .success(valid))) {
            $0.setting = .ready(saved: valid)
        }
        await store.receive(.delegate(.committed(valid)))
    }

    @Test func aStaleSaveCompletionIsIgnoredAndANewerEditFollowsTheRunningSave() async {
        let clock = TestClock()
        let store = store(settings: SettingsClient(
            read: { type in
                type.defaultSetting
            },
            write: { _ in
                try? await clock.sleep(for: .seconds(1))
            }
        ))
        var first = ControlsConfiguration()
        first.keyboardMode = .controller
        await store.send(.edit(first)) {
            $0.draft = first
            $0.setting = .saving(operation, saved: ControlsConfiguration(), draft: first)
        }
        await store.send(.saved(OperationID(), .success(first)))
        var second = first
        second.mouseEnabled = true
        await store.send(.edit(second)) {
            $0.draft = second
            $0.setting = .saving(operation, saved: ControlsConfiguration(), draft: second)
        }
        await clock.advance(by: .seconds(1))
        await store.receive(.saved(operation, .success(first))) {
            $0.setting = .saving(operation, saved: first, draft: second)
        }
        await store.receive(.delegate(.committed(first)))
        await clock.advance(by: .seconds(1))
        await store.receive(.saved(operation, .success(second))) {
            $0.setting = .ready(saved: second)
        }
        await store.receive(.delegate(.committed(second)))
    }

    @Test func aControllerButtonCaptureAssignsThePressedButtonAndSaves() async {
        let clock = TestClock()
        let store = store(clock: clock)
        store.exhaustivity = .off(showSkippedAssertions: false)
        let presetID = store.state.draft.selectedPresetID
        await store.send(.captureButton(.cross, presetID)) {
            $0.mode = .capturing(ControlsCapture(
                id: id,
                target: .cross,
                presetID: presetID,
                source: .gamepadButton
            ))
        }
        await store.send(.captured(UUID(), 17, "Left paddle 1"))
        await store.send(.captured(id, 99, "Button 99"))
        #expect(store.state.capture != nil)
        await store.send(.captured(id, 17, "Left paddle 1")) {
            $0.mode = .idle
        }
        await store.receive(\.delegate.committed)
        #expect(store.state.draft.presets[0].bindings.contains {
            $0.source == .gamepadButton && $0.code == 17 && $0.target == .cross
        })
        await clock.advance(by: ControlsSettingsFeature.buttonCaptureTimeout)
    }

    @Test func aControllerButtonCaptureTimesOut() async {
        let clock = TestClock()
        let store = store(clock: clock)
        let presetID = store.state.draft.selectedPresetID
        await store.send(.captureButton(.cross, UUID()))
        await store.send(.captureButton(.circle, presetID)) {
            $0.mode = .capturing(ControlsCapture(
                id: id,
                target: .circle,
                presetID: presetID,
                source: .gamepadButton
            ))
        }
        await clock.advance(by: .seconds(5))
        await store.send(.captureTimedOut(UUID()))
        await clock.advance(by: .seconds(1))
        await store.receive(.captureTimedOut(id)) {
            $0.mode = .idle
        }
    }

    @Test func aKeyCaptureIgnoresControllerButtonCodes() async {
        let store = store()
        await store.send(.capture(.cross)) {
            $0.mode = .capturing(ControlsCapture(id: id, target: .cross, presetID: $0.draft.selectedPresetID))
        }
        await store.send(.captured(id, 200, "Key"))
        await store.send(.edit(store.state.draft)) {
            $0.mode = .idle
        }
    }

    @Test func leavingThePaneEndsACaptureAndCommitsNothingNew() async {
        let store = store()
        await store.send(.recordTouchpadShortcut) {
            $0.mode = .recordingShortcut(id)
        }
        await store.send(.stop) {
            $0.mode = .idle
        }
        #expect(store.state.setting == .ready(saved: ControlsConfiguration()))
    }
}

@MainActor @Test func choosingAKeyboardModeSavesItAtOnce() async throws {
    let id = UUID()
    let settings = SettingsClient.inMemory()
    let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.settings = settings
    }
    var configuration = ControlsConfiguration()
    configuration.keyboardMode = .controller
    await store.send(.binding(.set(\.draft, configuration))) {
        $0.draft = configuration
        $0.setting = .saving(OperationID(uuid: id), saved: ControlsConfiguration(), draft: configuration)
    }
    await store.receive(.saved(OperationID(uuid: id), .success(configuration))) {
        $0.setting = .ready(saved: configuration)
    }
    await store.receive(.delegate(.committed(configuration)))
    let persisted = try await settings.load(ControlsConfiguration.self)
    #expect(persisted.keyboardMode == .controller)
}

@MainActor @Test func aDuplicatedPresetIsUsedByTheControllerThatAskedForIt() async {
    let id = UUID()
    let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.continuousClock = TestClock()
        $0.settings = .inMemory()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    let original = store.state.draft.selectedPresetID
    await store.send(.duplicatePreset(original, for: .controller("pad")))
    await store.receive(\.delegate.committed)
    #expect(store.state.draft.presets.count == 2)
    #expect(store.state.draft.controllers["pad"]?.presetID == id)
    #expect(store.state.draft.presets[1].name.hasSuffix(" copy"))
    await store.send(.deletePreset(id))
    await store.receive(\.delegate.committed)
    #expect(store.state.draft.presets.count == 1)
    #expect(store.state.draft.controllers["pad"]?.presetID == nil)
}

@MainActor @Test func controllersAreRememberedWhenSeenAndForgottenWithTheirPreset() async throws {
    let id = UUID()
    let now = Date(timeIntervalSince1970: 1000)
    let pad = ControllerDevice(id: 4, preferenceKey: "pad", name: "Pad", transport: "USB", individual: true,
                               rumble: true, lights: false, motion: true, touchpad: true,
                               family: .playStation)
    let connected = LockIsolated([pad])
    let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.date = .constant(now)
        $0.continuousClock = TestClock()
        $0.settings = .inMemory()
        $0.controllers = ControllersClient(
            devices: { connected.value },
            testRumble: { _, _ in },
            showLights: { _ in }
        )
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.refreshDevices)
    await store.receive(\.devices)
    await store.receive(\.delegate.committed)
    #expect(store.state.draft.remembered["pad"]?.lastSeen == now)
    #expect(store.state.listedDevices.map(\.preferenceKey) == ["keyboard", "pad"])
    await store.send(.forgetController("pad"))
    #expect(store.state.draft.remembered["pad"] != nil)
    connected.setValue([])
    await store.send(.refreshDevices)
    await store.receive(\.devices)
    #expect(store.state.device("pad")?.name == "Pad")
    #expect(!store.state.isConnected("pad"))
    await store.send(.show(.controller("pad")))
    await store.send(.forgetController("pad"))
    await store.receive(\.delegate.committed)
    #expect(store.state.draft.remembered["pad"] == nil)
    #expect(store.state.editing == .keyboard)
    #expect(store.state.change?.summary == .forgot("Pad"))
}

@MainActor @Test func aPlayersFirstChangeGivesThemTheirOwnBindings() async throws {
    let id = UUID()
    let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.continuousClock = TestClock()
        $0.settings = .inMemory()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.show(.player(1)))
    await store.send(.capturePlayerButton(1, .cross))
    #expect(store.state.draft.playerPresets[1] == id)
    await store.send(.captured(id, 3, ""))
    await store.receive(\.delegate.committed)
    let own = try #require(store.state.draft.playerPreset(1))
    #expect(own.name == "Player 2")
    #expect(own.bindings.contains { $0.source == .gamepadButton && $0.code == 3 && $0.target == .cross })
    #expect(store.state.change?.createdPreset == "Player 2")
    await store.send(.removePlayerPreset(1))
    await store.receive(\.delegate.committed)
    #expect(store.state.draft.playerPresets[1] == nil)
    #expect(store.state.draft.presets.count == 1)
}

@MainActor @Test func theMappingScreenOpensOnAPlayerAndClosingItTakesBackAnUnfinishedCapture() async {
    let id = UUID()
    let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.continuousClock = TestClock()
        $0.settings = .inMemory()
    }
    let original = store.state.draft
    await store.send(.openMapping(.player(1))) {
        $0.showsMapping = true
        $0.editing = .player(1)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.capturePlayerButton(1, .cross))
    #expect(store.state.draft.playerPresets[1] == id)
    await store.send(.closeMapping)
    #expect(!store.state.showsMapping)
    #expect(store.state.capture == nil)
    #expect(store.state.draft == original)
    #expect(store.state.editing == .player(1))
}

@MainActor @Test func leavingThePaneClosesTheMappingScreen() async {
    let store = TestStore(initialState: ControlsSettingsFeature.State.loaded()) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.uuid = .constant(UUID())
        $0.continuousClock = TestClock()
        $0.settings = .inMemory()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.openMapping(.player(0)))
    #expect(store.state.showsMapping)
    await store.send(.stop)
    #expect(!store.state.showsMapping)
}
