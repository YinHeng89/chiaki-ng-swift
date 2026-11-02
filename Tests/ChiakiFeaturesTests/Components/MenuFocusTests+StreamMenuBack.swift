@testable import ChiakiFeatures
import ChiakiModels
import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    private func streamMenuStore() -> StoreOf<StreamMenuReducer> {
        Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080)
            }
            $0.streamSession.saveTuning = { _, _ in
            }
        }
    }

    private func streamMenuHarness(_ store: StoreOf<StreamMenuReducer>) async
        -> (MenuFocusHarness, KeyWindowOverride) {
        let harness = MenuFocusHarness(width: 1000, height: 800) { _ in
            MenuFocusHostingView(
                rootView: MirroredStreamMenu(store: store)
                    .environment(\.controllerNavigation, testControllerNavigation)
            )
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(300)
        return (harness, override)
    }

    @Test func backFromAStreamMenuTabResumesTheStream() async {
        let store = streamMenuStore()
        let (harness, override) = await streamMenuHarness(store)
        defer {
            override.restore()
            harness.close()
        }
        #expect(store.navigation.isActive)
        #expect(testControllerNavigation.streamNavigationActive)
        await harness.send(.right)
        await harness.pause(150)
        await harness.send(.back)
        await harness.pause(200)
        #expect(!store.navigation.isActive)
        #expect(!testControllerNavigation.streamNavigationActive)
    }

    @Test func aFeatureClosingTheStreamMenuResumesTheStream() async {
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
        let harness = MenuFocusHarness(width: 1000, height: 800) { _ in
            MenuFocusHostingView(
                rootView: MirroredStreamMenu(store: store)
                    .environment(\.controllerNavigation, testControllerNavigation)
            )
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(300)
        #expect(store.navigation.isActive)
        #expect(testControllerNavigation.streamNavigationActive)
        #expect(testNavigator.inputGate.isBlocking)
        store.send(.returnToGameplay(save: true))
        await harness.pause(300)
        #expect(!store.navigation.isActive)
        #expect(!testControllerNavigation.streamNavigationActive)
        #expect(!testNavigator.inputGate.isBlocking)
    }

    @Test func confirmOnTheStreamMenuCloseButtonResumesTheStream() async {
        let store = streamMenuStore()
        let (harness, override) = await streamMenuHarness(store)
        defer {
            override.restore()
            harness.close()
        }
        var previous = harness.focusedFrame
        for _ in 0..<12 {
            await harness.send(.right)
            await harness.pause(120)
            if harness.focusedFrame == previous {
                break
            }
            previous = harness.focusedFrame
        }
        #expect(store.navigation.isActive)
        #expect(testControllerNavigation.streamNavigationActive)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(!store.navigation.isActive)
        #expect(!testControllerNavigation.streamNavigationActive)
    }

    @Test func backOnTheStreamMenuCloseButtonResumesTheStream() async {
        let store = streamMenuStore()
        let (harness, override) = await streamMenuHarness(store)
        defer {
            override.restore()
            harness.close()
        }
        var previous = harness.focusedFrame
        for _ in 0..<10 {
            await harness.send(.right)
            await harness.pause(100)
            if harness.focusedFrame == previous {
                break
            }
            previous = harness.focusedFrame
        }
        await harness.send(.back)
        await harness.pause(200)
        await harness.send(.back)
        await harness.pause(200)
        #expect(!store.navigation.isActive)
        #expect(!testControllerNavigation.streamNavigationActive)
    }
}

extension MenuFocusTests {
    @Test func theDockSettingsItemOpensSettingsAndResumesTheStream() async {
        let store = streamMenuStore()
        let (harness, override) = await streamMenuHarness(store)
        let settings = LockIsolated(0)
        let listener = Task { @MainActor in
            for await event in testNavigator.commands.events() where event.command == .settings {
                settings.withValue {
                    $0 += 1
                }
            }
        }
        defer {
            listener.cancel()
            override.restore()
            harness.close()
        }
        var previous = harness.focusedFrame
        for _ in 0..<12 {
            await harness.send(.right)
            await harness.pause(120)
            if harness.focusedFrame == previous {
                break
            }
            previous = harness.focusedFrame
        }
        await harness.send(.left)
        await harness.pause(150)
        #expect(settings.value == 0)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(settings.value == 1)
        #expect(!store.navigation.isActive)
        #expect(!testControllerNavigation.streamNavigationActive)
    }
}

private struct MirroredStreamMenu: View {
    let store: StoreOf<StreamMenuReducer>

    var body: some View {
        StreamMenuOverlay(store: store, stopTitle: "Disconnect")
            .modifier(StreamNavigationMirror(active: store.navigation.isActive))
    }
}
