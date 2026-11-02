@testable import ChiakiFeatures
import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func pictureSettingsColourSlidersAreReachedAdjustedAndReset() async {
        let store = FeatureFocusStores.settingsStore(tab: .picture)
        let harness = MenuFocusHarness(width: 1000, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 780, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        var previous = NSRect.zero
        var presses = 0
        while harness.focusedFrame.integral != previous, presses < 30 {
            previous = harness.focusedFrame.integral
            await harness.send(.down)
            presses += 1
        }
        await harness.send([.up, .confirm])
        await harness.pause(150)
        #expect(!store.picture.draft.reduceBanding)
        await harness.send([.up, .confirm, .right])
        #expect(abs(store.picture.draft.adjustments.gamma - 1.05) < 0.001)
        await harness.send([.up, .confirm, .left, .left])
        #expect(abs(store.picture.draft.adjustments.saturation - 0.9) < 0.001)
        await harness.send([.up, .up, .confirm, .right, .right, .left])
        #expect(abs(store.picture.draft.adjustments.brightness - 0.05) < 0.001)
        #expect(store.picture.draft.adjustments.contrast == 1)
        await harness.send([.down, .down, .down, .down, .down, .confirm])
        await harness.pause(150)
        #expect(store.picture.draft.adjustments.isNeutral)
        #expect(!store.picture.draft.reduceBanding)
    }
}
