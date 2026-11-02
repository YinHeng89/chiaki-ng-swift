import ChiakiModels
import ComposableArchitecture
import PlatformUI
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func theLayeredContinuePillIsTheStopAndContinuesTheGame() async throws {
        let console = FeatureFocusStores.console(1)
        let item = DisplayedConsole(target: console, preview: false)
        let title = RecentTitle(
            titleID: "PPSA00001_00", launchID: "PPSA00001", name: "Starfall Run", imageURL: "",
            lastPlayedMs: 1, recent: true, conceptID: "1"
        )
        let layers = try #require(SampleArtStudio().layers(named: "Starfall Run"))
        let requests = LockIsolated<[LibraryRequest]>([])
        let store = FeatureFocusStores.libraryStore(consoles: [console], requests: requests) { state in
            state.recentlyPlayed.selection = .init(profileID: state.selectedAccount ?? UUID(), eligible: true)
            state.recentlyPlayed.phase = .loaded
            state.recentlyPlayed.rails = [RecentlyPlayedRail(
                consoleID: console.id ?? UUID(),
                hardwareID: Data(repeating: 1, count: 6),
                titles: [title]
            )]
            state.consoleArt.games["1"] = .layered(layers)
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryView(store: store))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.heldFocus == .console(item)
        }
        await harness.pause(400)
        #expect(store.heldFocus == .console(item))
        await harness.send([.right, .right, .right])
        #expect(store.heldFocus == .action(item, .resume), "\(String(describing: store.heldFocus))")
        await harness.send(.right)
        #expect(store.heldFocus == .action(item, .resume), "\(String(describing: store.heldFocus))")
        await harness.send(.left)
        #expect(store.heldFocus == .action(item, .delete))
        await harness.send(.right)
        #expect(store.heldFocus == .action(item, .resume), "\(String(describing: store.heldFocus))")
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(requests.value.filter { $0 == .playTitle(console.id ?? UUID(), title) }.count == 1)
    }
}
