@testable import ChiakiFeatures
import PlatformUI
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func keyboardModeSegmentsSwitchWithTheControllerInTheControlsTab() async {
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
        #expect(store.controls.draft.keyboardMode == .typeOnConsole)
        for _ in 0..<20 where abs(harness.focusedFrame.height - ControlsBoardPlacement.chipHeight) >= 2 {
            await harness.send(.down)
            await harness.pause(60)
        }
        for _ in 0..<20 where abs(harness.focusedFrame.height - ControlsBoardPlacement.chipHeight) < 2 {
            await harness.send(.down)
            await harness.pause(60)
        }
        #expect(harness.focusedFrame.height < ControlsBoardPlacement.chipHeight - 4)
        await harness.send(.confirm)
        await harness.pause(500)
        #expect(store.controls.draft.keyboardMode == .controller)
        await harness.send(.left)
        await harness.pause(500)
        let first = harness.focusedFrame
        await harness.send(.right)
        await harness.pause(500)
        let segments = harness.focusedFrame
        #expect(abs(first.midY - segments.midY) <= 2 && first.minX < segments.minX)
        await harness.send(.left)
        await harness.pause(500)
        let typing = harness.focusedView
        await harness.send(.confirm)
        await harness.pause(500)
        #expect(store.controls.draft.keyboardMode == .typeOnConsole)
        await harness.send(.down)
        await harness.pause(500)
        #expect(harness.focusedView !== typing)
        #expect(harness.focusedFrame.height > segments.height)
        await harness.send(.up)
        await harness.pause(500)
        #expect(harness.focusedView === typing)
    }
}
