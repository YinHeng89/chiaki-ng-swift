import ChiakiModels
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func connectionTipsAreReachedFromTheStatisticsTabAndChosenWithTheController() async {
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
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(300)
        while store.navigation.panel != .statistics {
            let before = store.navigation.panel
            await harness.send(.next)
            await harness.pause(200)
            if store.navigation.panel == before {
                break
            }
        }
        #expect(store.navigation.panel == .statistics)
        await harness.send(.up)
        await harness.pause(150)
        await harness.send([.right, .confirm])
        await harness.pause(150)
        #expect(store.troubleshootTopic == .connectionSpeed)
        await harness.send([.right, .right, .confirm])
        await harness.pause(150)
        #expect(store.troubleshootTopic == .resolution)
        await harness.send([.down, .up, .left, .confirm])
        await harness.pause(150)
        #expect(store.troubleshootTopic == .connectionSpeed)
    }
}
