import ChiakiModels
import ComposableArchitecture
import PlatformUI
import SwiftUI
import Testing
@testable import ChiakiFeatures
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test(arguments: [false, true])
    func cloudFilterChipsStartWithRecentlyPlayedOnlyWhenThereIsSome(played: Bool) async throws {
        let (store, harness) = try cloudRecentHarness(played: played)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        let order: [CloudLibraryFilter] = played
            ? [.recent, .all, .owned]
            : [.all, .owned, .plus]
        #expect(store.filters.first == order[0])
        await harness.send([.up, .confirm])
        #expect(store.filter == order[0])
        await harness.send([.right, .confirm])
        #expect(store.filter == order[1])
        await harness.send([.left, .left, .confirm])
        #expect(store.filter == order[0])
    }

    @Test func shoulderButtonsCycleTheShownChipsAndKeepFocusOnThem() async throws {
        let (store, harness) = try cloudRecentHarness(played: true)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        var navigation = ControllerNavigationState()
        navigation.setRoute(.menu)
        var now = 0.0
        func press(_ button: Int) async {
            harness.perform(navigation.button(button, down: true, now: now), in: harness.window)
            _ = navigation.button(button, down: false, now: now + 0.1)
            now += 1
            await harness.pause(200)
        }
        #expect(store.filter == .recent)
        await press(10)
        #expect(store.filter == .all)
        await harness.send([.right, .confirm])
        #expect(store.filter == .owned)
        await press(9)
        #expect(store.filter == .all)
        await press(9)
        #expect(store.filter == .recent)
        await press(9)
        #expect(store.filter == .browse)
        await press(10)
        #expect(store.filter == .recent)
    }

    @Test func thePreordersChipEndsTheRowAndShowsOnlyUnreleasedGames() async throws {
        let (store, harness) = try cloudRecentHarness(played: false, preorder: true)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        #expect(store.filters == [.all, .owned, .plus, .browse, .preorders])
        await harness.send([.up, .right, .right, .right, .right, .confirm])
        #expect(store.filter == .preorders)
        #expect(store.visibleGames.map(\.id) == ["preorder"])
        var navigation = ControllerNavigationState()
        navigation.setRoute(.menu)
        harness.perform(navigation.button(10, down: true, now: 0), in: harness.window)
        _ = navigation.button(10, down: false, now: 0.1)
        await harness.pause(200)
        #expect(store.filter == .all)
        harness.perform(navigation.button(9, down: true, now: 1), in: harness.window)
        _ = navigation.button(9, down: false, now: 1.1)
        await harness.pause(200)
        #expect(store.filter == .preorders)
        await harness.send([.left, .confirm])
        #expect(store.filter == .browse)
        #expect(!store.visibleGames.contains { $0.id == "preorder" })
    }

    @Test func aHiddenRecentlyPlayedChipHandsFocusToAllStreamable() async throws {
        let (store, harness) = try cloudRecentHarness(played: true)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        await harness.send(.up)
        let recent = harness.window.firstResponder
        store.send(.recentlyPlayed(store.accountID ?? UUID(), store.recentAttempt ?? UUID(), []))
        await harness.pause(300)
        #expect(!store.filters.contains(.recent))
        #expect(store.filter == .all)
        #expect(harness.window.firstResponder !== recent)
        await harness.send([.right, .confirm])
        #expect(store.filter == .owned)
    }

    @Test func aRefusedGameHandsFocusToTheCardThatTakesItsPlace() async throws {
        let (store, harness) = try cloudRecentHarness(played: false)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        #expect(store.filter == .all)
        await harness.send(.right)
        store.send(.cardChecked(store.accountID!, "game-1", .notStreamable))
        await harness.pause(400)
        #expect(!store.matchingGames.contains { $0.id == "game-1" })
        await harness.send(.confirm)
        #expect(store.selectedGame?.id == "game-2")
    }

    @Test func closingTheDetailsOfARefusedGameFocusesTheCardThatTookItsPlace() async throws {
        let (store, harness) = try cloudRecentHarness(played: false)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        await harness.send([.right, .confirm])
        #expect(store.selectedGame?.id == "game-1")
        store.send(.cardChecked(store.accountID!, "game-1", .notStreamable))
        await harness.pause(200)
        await harness.send(.back)
        await harness.pause(400)
        #expect(store.selectedGame == nil)
        await harness.send(.confirm)
        #expect(store.selectedGame?.id == "game-2")
    }
}

@MainActor
private func cloudRecentHarness(
    played: Bool, games count: Int = 6, preorder: Bool = false
) throws -> (StoreOf<CloudLibraryFeature>, MenuFocusHarness) {
    let games = (0..<count).map { index in
        """
        {"productId":"game-\(index)","name":"Game \(index)","platform":"ps5",
        "category":"owned","isOwned":true,"plusCatalog":true,
        "streamServiceType":"pscloud","streamIdentifier":"game-\(index)"}
        """
    }.joined(separator: ",")
    let snapshot = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[\(games)]}
    """.utf8))
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.snapshot = preorder
        ? CloudLibrarySnapshot(settledLocale: snapshot.settledLocale, games: snapshot.games + [CloudGame(
            productId: "preorder", name: "Preorder", isOwned: true, standing: .inLibrary,
            release: .unannounced
        )])
        : snapshot
    state.phase = .ready
    state.recentAttempt = UUID()
    if played {
        state.listing.recentlyPlayed = [
            CloudRecentlyPlayed(productId: "game-3", lastPlayed: Date(timeIntervalSince1970: 1_000_000))
        ]
        state.filter = .recent
    }
    let store = Store(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
    }
    let harness = MenuFocusHarness(width: 1500, height: 800) { _ in
        MenuFocusHostingView(rootView: CloudLibraryView(store: store, height: 600))
    }
    return (store, harness)
}
