import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func theOtherVersionIsTheDetailsLastActionAndOpensThatVersion() async {
        let ps5 = "UP9000-PPSA01289_00-SACKBOYADVENTURE"
        let ps4 = "UP9000-CUSA18886_00-SACKBOYADVENTURE"
        let snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
            CloudGame(
                productId: ps5, name: "Sackboy", platform: "PS5", isOwned: true, plusCatalog: true,
                standing: .inLibrary, otherVersion: CloudOtherVersion(productId: ps4, leads: true)
            ),
            CloudGame(
                productId: ps4, name: "Sackboy", platform: "PS4", plusCatalog: true,
                streamServiceType: "psnow",
                standing: .included, otherVersion: CloudOtherVersion(productId: ps5, leads: false)
            )
        ])
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        state.selection = ps5
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
            $0.catalog.gameDetails = { _, _ in
                try? await Task.sleep(for: .milliseconds(150))
                return .failure(CatalogFailure(reason: .coreClosed))
            }
            $0.catalog.storefrontCheck = CatalogClient.unanswered
        }
        #expect(store.matchingGames.map(\.id) == [ps5])
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 700))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(800)
        #expect(store.selection == ps5)
        let play = harness.focusedFrame.integral
        #expect(play.width > 120 && play.width < 1000)
        await harness.send(.right)
        let version = harness.focusedFrame.integral
        #expect(version != play && version.width > 120)
        await harness.send(.right)
        #expect(harness.focusedFrame.integral != version)
        await harness.send(.left)
        #expect(harness.focusedFrame.integral == version)
        await harness.send(.confirm)
        await harness.pause(800)
        #expect(store.selection == ps4)
        store.send(.closeTapped)
        await harness.pause(400)
        #expect(store.selection == nil)
    }
}
