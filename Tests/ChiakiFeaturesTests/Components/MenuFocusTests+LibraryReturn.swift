@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import MenuFocus
import Observation
import PlatformUI
import SwiftUI
import Testing

extension MenuFocusTests {
    @Test func theCloudLibraryComesBackOnTheGameThatHadFocusAfterAStreamCoveredIt() async throws {
        let snapshot = try CloudLibrarySnapshot.decode(Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
        "games":[
        {"productId":"first","name":"First","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"first"},
        {"productId":"second","name":"Second","platform":"ps5","category":"owned",
        "isOwned":true,"plusCatalog":true,"streamServiceType":"pscloud","streamIdentifier":"second"}]}
        """.utf8))
        let store = FeatureFocusStores.libraryStore(consoles: [], section: .cloud) { state in
            state.cloudLibrary.accountID = state.selectedAccount
            state.cloudLibrary.snapshot = snapshot
            state.cloudLibrary.phase = .ready
        }
        let mount = LibraryMount()
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LibraryMountHost(store: store, mount: mount))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.cloudLibrary.heldFocus == .game("first")
        }
        await harness.send(.right)
        await waitUntil(harness) {
            store.cloudLibrary.heldFocus == .game("second")
        }
        mount.shown = false
        await harness.settle()
        mount.shown = true
        await harness.settle()
        #expect(store.cloudLibrary.phase == .ready)
        #expect(store.cloudLibrary.heldFocus == .game("second"))
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.cloudLibrary.selectedGame != nil
        }
        #expect(store.cloudLibrary.selectedGame?.id == "second")
    }
}

@MainActor @Observable
private final class LibraryMount {
    var shown = true
}

private struct LibraryMountHost: View {
    let store: StoreOf<LibraryFeature>
    let mount: LibraryMount

    var body: some View {
        if mount.shown {
            LibraryView(store: store)
        } else {
            Color.clear
        }
    }
}
