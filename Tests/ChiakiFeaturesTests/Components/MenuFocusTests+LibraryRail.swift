@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import PlatformUI
import SwiftUI
import Testing
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    private func railHarness() -> (StoreOf<LibraryFeature>, MenuFocusHarness) {
        let store = FeatureFocusStores.libraryStore(consoles: [])
        let harness = MenuFocusHarness(width: 1000, height: 800) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store)
                .environment(\.quitControlShown, true))
        }
        return (store, harness)
    }

    @Test func railIsEnteredFromTheLeftEdgeAndWalkedWithTheDpad() async {
        let (store, harness) = railHarness()
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .addConsole
        }
        #expect(store.heldFocus == .addConsole)
        let sections: [(MenuCommand, ConsoleLibraryFocus?)] = [
            (.left, .librarySection(.consoles)),
            (.left, .librarySection(.consoles)),
            (.up, .librarySection(.consoles)),
            (.down, .librarySection(.cloud)),
            (.down, .librarySection(.trophies))
        ]
        let join: [(MenuCommand, ConsoleLibraryFocus?)] = KakusanBuild.included
            ? [(.down, .joinGame)]
            : []
        let steps: [(MenuCommand, ConsoleLibraryFocus?)] = sections + join + [
            (.down, .notifications),
            (.down, .settings),
            (.down, .profile),
            (.down, .quit),
            (.down, .quit),
            (.up, .profile),
            (.right, .addConsole),
            (.left, .librarySection(.consoles)),
            (.down, .librarySection(.cloud))
        ]
        for (command, expected) in steps {
            await harness.send(command)
            await waitUntil(harness, attempts: 10) {
                store.heldFocus == expected
            }
            #expect(store.heldFocus == expected, "after \(command)")
        }
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.section == .cloud
        }
        #expect(store.section == .cloud)
    }

    @Test func sideRailOnlySpansItsControls() async {
        let (store, harness) = railHarness()
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .addConsole
        }
        await harness.send([.left, .down, .down, .down])
        if KakusanBuild.included {
            await harness.send(.down)
        }
        #expect(store.heldFocus == .notifications)
        let notifications = harness.focusedFrame
        await harness.send(.down)
        #expect(store.heldFocus == .settings)
        let settings = harness.focusedFrame
        #expect(settings.maxY < notifications.minY)
        #expect(notifications.minY - settings.maxY < 40)
    }
}
