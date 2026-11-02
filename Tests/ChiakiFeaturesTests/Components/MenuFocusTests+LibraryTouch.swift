@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI
import Testing

extension MenuFocusTests {
    private func touchLibrary(
        _ layout: ScreenLayout,
        consoles: [RegistrationFlow.ConsoleTarget],
        width: CGFloat,
        height: CGFloat
    ) -> (StoreOf<LibraryFeature>, MenuFocusHarness) {
        let store = FeatureFocusStores.libraryStore(consoles: consoles) { state in
            state.discovery = .watching(DiscoverySnapshot())
        }
        let harness = MenuFocusHarness(width: width, height: height) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store)
                .environment(\.screenLayout, layout)
                .environment(\.quitControlShown, true))
        }
        return (store, harness)
    }

    @Test func touchRailShowsTitlesUnderItsIconsAndNeverWidens() async {
        let (store, harness) = touchLibrary(
            ScreenLayout(room: .regular, stature: .tall, touch: true),
            consoles: [],
            width: 1000,
            height: 800
        )
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .addConsole
        }
        await harness.send(.left)
        await waitUntil(harness, attempts: 10) {
            store.heldFocus == .librarySection(.consoles)
        }
        #expect(store.heldFocus == .librarySection(.consoles))
        await harness.pause(400)
        let stop = harness.focusedFrame
        #expect(stop.width < 70, "\(stop)")
        #expect(stop.height >= 44, "\(stop)")
        await harness.send(.down)
        await waitUntil(harness, attempts: 10) {
            store.heldFocus == .librarySection(.cloud)
        }
        #expect(store.heldFocus == .librarySection(.cloud))
        #expect(harness.focusedFrame.width < 70, "\(harness.focusedFrame)")
        await harness.send(.right)
        await waitUntil(harness, attempts: 10) {
            store.heldFocus == .addConsole
        }
        #expect(store.heldFocus == .addConsole)
    }

    @Test func aTallCompactShelfStacksItsCardsSoDownReachesTheNextConsole() async {
        let consoles = [FeatureFocusStores.console(1), FeatureFocusStores.console(2)]
        let items = consoles.map {
            DisplayedConsole(target: $0, preview: false)
        }
        let (store, harness) = touchLibrary(
            ScreenLayout(room: .compact, stature: .tall, touch: true),
            consoles: consoles,
            width: 600,
            height: 760
        )
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .console(items[0])
        }
        await harness.pause(300)
        #expect(store.heldFocus == .console(items[0]))
        await harness.send(.down)
        await waitUntil(harness, attempts: 10) {
            store.heldFocus == .console(items[1])
        }
        #expect(store.heldFocus == .console(items[1]))
        await harness.send(.up)
        await waitUntil(harness, attempts: 10) {
            store.heldFocus == .action(items[1], .connection(.local))
        }
        #expect(store.heldFocus == .action(items[1], .connection(.local)))
        await harness.send(.up)
        await waitUntil(harness, attempts: 10) {
            store.heldFocus == .console(items[0])
        }
        #expect(store.heldFocus == .console(items[0]))
    }

    @Test func aShortCompactShelfPagesItsCardsInOneRow() async {
        let consoles = [FeatureFocusStores.console(1), FeatureFocusStores.console(2)]
        let items = consoles.map {
            DisplayedConsole(target: $0, preview: false)
        }
        let (store, harness) = touchLibrary(
            ScreenLayout(room: .compact, stature: .short, touch: true, sideInset: 59),
            consoles: consoles,
            width: 850,
            height: 390
        )
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .console(items[0])
        }
        await harness.pause(300)
        #expect(store.heldFocus == .console(items[0]))
        let card = harness.focusedFrame
        #expect(card.minX >= 59, "\(card)")
        await harness.send(.down)
        await harness.pause(200)
        #expect(store.heldFocus == .console(items[0]))
    }
}
