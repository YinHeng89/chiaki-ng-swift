@testable import ChiakiFeatures
import ChiakiModels
import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func colourPanelSlidersFollowTheControllerAndResetRestoresThePicture() async {
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080)
            }
            $0.streamSession.saveTuning = { _, _ in
            }
        }
        let harness = MenuFocusHarness(width: 1000, height: 900) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(store: store, stopTitle: "Disconnect"))
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
        await harness.send([.right, .up])
        await harness.pause(300)
        await harness.send(.up)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(!store.draft.reduceBanding)
        await harness.send([.up, .confirm, .right, .confirm])
        await harness.pause(150)
        #expect(abs(store.draft.adjustments.gamma - 1.05) < 0.001)
        await harness.send([.up, .confirm, .left, .left, .confirm])
        await harness.pause(150)
        #expect(abs(store.draft.adjustments.saturation - 0.9) < 0.001)
        await harness.send([.up, .up, .confirm, .right, .up, .confirm, .right, .confirm])
        await harness.pause(150)
        #expect(abs(store.draft.adjustments.brightness - 0.1) < 0.001)
        #expect(store.draft.adjustments.contrast == 1)
        await harness.send([.down, .down, .down, .down, .down, .confirm])
        await harness.pause(200)
        #expect(store.draft.adjustments.isNeutral)
        #expect(!store.draft.reduceBanding)
    }
}
