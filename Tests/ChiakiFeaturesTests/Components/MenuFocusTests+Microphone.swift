import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

@MainActor
private func microphoneStores(
    requests: LockIsolated<Int>
) -> (StoreOf<StreamMenuReducer>, StoreOf<MicrophoneReducer>) {
    let menu = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.loadTuning = { _ in
            StreamTuningConfiguration(nativeHeight: 1080, volume: 0.5)
        }
        $0.streamSession.saveTuning = { _, _ in
        }
    }
    var state = MicrophoneReducer.State()
    state.availability = .available(UUID())
    let microphone = Store(initialState: state) {
        MicrophoneReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.requestMicrophonePermission = {
            requests.withValue {
                $0 += 1
            }
            return false
        }
    }
    return (menu, microphone)
}

extension MenuFocusTests {
    @Test func soundPanelMicrophoneButtonIsReachedBelowVolumeAndToggles() async {
        let requests = LockIsolated(0)
        let (menu, microphone) = microphoneStores(requests: requests)
        let harness = MenuFocusHarness(width: 1000, height: 800) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(
                store: menu,
                stopTitle: "Disconnect",
                microphone: microphone
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
        await harness.pause(450)
        await harness.send([.right, .right, .up])
        await harness.pause(300)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(requests.value == 1)
        #expect(microphone.phase == .denied)
        await harness.send([.up, .up, .up, .confirm, .left, .confirm])
        await harness.pause(150)
        #expect(abs(menu.draft.volume - 0.45) < 0.001)
        await harness.send([.down, .down, .down, .confirm])
        await harness.pause(200)
        #expect(requests.value == 2)
        #expect(abs(menu.draft.volume - 0.45) < 0.001)
        await harness.send([.down, .up, .confirm])
        await harness.pause(200)
        #expect(requests.value == 3)
    }

    @Test func microphoneShortcutTogglesOnlyForItsOwnStreamWindow() async {
        let requests = LockIsolated(0)
        let (menu, microphone) = microphoneStores(requests: requests)
        let harness = MenuFocusHarness(width: 900, height: 700) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(
                store: menu,
                stopTitle: "Disconnect",
                microphone: microphone
            ))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        NotificationCenter.default.post(name: .toggleStreamMicrophone, object: harness.window)
        await harness.pause(200)
        #expect(requests.value == 1)
        let other = HeadlessWindow()
        NotificationCenter.default.post(name: .toggleStreamMicrophone, object: other)
        await harness.pause(200)
        #expect(requests.value == 1)
    }

    @Test func soundSettingsMicrophoneControlsSitAboveTheAudioBuffer() async {
        let store = FeatureFocusStores.settingsStore(tab: .sound)
        let harness = MenuFocusHarness(width: 1000, height: 1000) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: window)
        await harness.pause(200)
        #expect(store.sound.sound.isEditable)
        var previous = window.firstResponder
        for _ in 0..<10 {
            await harness.send(.down)
            if window.firstResponder === previous {
                break
            }
            previous = window.firstResponder
        }
        let buffer = window.firstResponder
        await harness.send(.up)
        let spatial = window.firstResponder
        #expect(spatial !== buffer)
        await harness.send(.up)
        let audio3D = window.firstResponder
        #expect(audio3D !== spatial)
        await harness.send(.up)
        let toggle = window.firstResponder
        #expect(toggle !== audio3D)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.sound.sound.draft.startWithMicrophone)
        #expect(store.sound.sound.draft.spatialAudio == SpatialAudio())
        await harness.send(.up)
        #expect(window.firstResponder !== toggle)
        await harness.send(.down)
        #expect(window.firstResponder === toggle)
        await harness.send([.down, .down, .down])
        #expect(window.firstResponder === buffer)
    }
}
