@testable import ChiakiFeatures
import AppKit
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func backgroundInputCheckboxIsTheLastControlInTheControlsTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = MenuFocusHarness(width: 1300, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(200)
        var previous = harness.window.firstResponder
        for _ in 0..<160 {
            await harness.send(.down)
            if harness.window.firstResponder === previous {
                break
            }
            previous = harness.window.firstResponder
        }
        #expect(store.controls.isEditable)
        #expect(!store.controls.draft.backgroundInput)
        let toggle = harness.window.firstResponder
        let frame = harness.focusedFrame
        await harness.send(.confirm)
        await harness.pause(80)
        #expect(store.controls.draft.backgroundInput)
        #expect(harness.window.firstResponder === toggle)
        await harness.send(.up)
        #expect(harness.focusedFrame.size != frame.size)
        await harness.send(.down)
        #expect(harness.focusedFrame.size == frame.size)
        #expect(harness.window.firstResponder === toggle)
        await harness.send(.confirm)
        await harness.pause(80)
        #expect(!store.controls.draft.backgroundInput)
    }
}
