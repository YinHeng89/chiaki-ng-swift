@testable import ChiakiFeatures
import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func streamMediaIsTheFirstSoundControlAndIsChosenWithTheController() async {
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
        #expect(store.sound.sound.draft.media == .pictureAndSound)
        await harness.send(.left)
        let first = window.firstResponder
        await harness.send(.right)
        #expect(window.firstResponder !== first)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.sound.sound.draft.media == .soundOnly)
        await harness.send([.right, .right, .confirm])
        await harness.pause(150)
        #expect(store.sound.sound.draft.media == .controlsOnly)
        await harness.send(.right)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.sound.sound.draft.media == .controlsOnly)
    }
}
