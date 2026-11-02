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
    @Test func closingAGamesDetailReturnsFocusToItsCardAfterTheDetailHasGone() async {
        let first = "UP9000-PPSA01289_00-SACKBOYADVENTURE"
        let second = "UP9000-PPSA09006_00-FULLGAME00000000"
        let snapshot = CloudLibrarySnapshot(settledLocale: "en-GB", games: [
            CloudGame(
                productId: first,
                name: "Sackboy",
                platform: "PS5",
                isOwned: true,
                standing: .inLibrary
            ),
            CloudGame(productId: second, name: "Owned", platform: "PS5", isOwned: true, standing: .inLibrary)
        ])
        var state = CloudLibraryFeature.State()
        state.accountID = UUID()
        state.snapshot = snapshot
        state.phase = .ready
        let store = Store(initialState: state) {
            CloudLibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ImmediateClock()
            $0.catalog.gameDetails = { _, _ in
                .failure(CatalogFailure(reason: .coreClosed))
            }
            $0.catalog.storefrontCheck = CatalogClient.unanswered
        }
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 700))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(600)
        await harness.send(.right)
        let card = harness.focusedFrame.integral
        #expect(card.width > 60)
        for _ in 0..<3 {
            await harness.send(.confirm)
            await harness.pause(600)
            #expect(store.selection == second)
            await harness.send(.back)
            await harness.pause(800)
            #expect(store.selection == nil)
            #expect(harness.focusedFrame.integral == card)
        }
    }
}
