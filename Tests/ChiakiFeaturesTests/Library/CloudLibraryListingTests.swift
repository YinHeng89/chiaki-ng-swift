import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

private func largeCatalog(_ count: Int = 5_067) -> CloudLibrarySnapshot {
    let words = ["Horizon", "Shadow", "Legends", "Racing", "Chronicles", "Odyssey", "Remastered", "Zero",
                 "Étoile", "Pokémon", "Final", "Fantasy", "Dawn", "Souls", "Tactics", "Ultimate"]
    let platforms = ["PS5", "PS4", "PS3"]
    let games = (0..<count).map { index in
        CloudGame(
            productId: "game-\(index)",
            name: "\(words[index % words.count]) \(words[(index / 16) % words.count]) \(index)",
            imageUrl: "https://image.example/\(index).png",
            platform: platforms[index % 3], isOwned: index % 4 == 0, plusCatalog: index % 3 == 0,
            streamServiceType: index % 5 == 0
                ? "psnow"
                : "pscloud",
            visible: index % 20 != 19
        )
    }
    return CloudLibrarySnapshot(settledLocale: "en-GB", games: games)
}

private func readAsTheLibraryViewDoes(_ state: CloudLibraryFeature.State) -> Int {
    var touched = 0
    for _ in 0..<5 {
        touched += state.selectedGame == nil
            ? 0
            : 1
    }
    touched += state.visibleGames.map(\.id).count
    touched += state.visibleGames.isEmpty
        ? 0
        : 1
    touched += state.visibleGames.count
    touched += state.pageCount > 1
        ? 1
        : 0
    touched += state.gridNavigation.count
    return touched
}

private func expectedMatches(
    _ snapshot: CloudLibrarySnapshot, filter: CloudLibraryFilter, platform: CloudPlatformFilter, query: String
) -> [String] {
    var ids: [String] = []
    for game in snapshot.games where game.visible {
        if query.isEmpty {
            switch filter {
            case .all:
                guard !game.isStoreOnly else {
                    continue
                }
            case .recent:
                continue
            case .owned:
                guard game.isOwnedPS5 else {
                    continue
                }
            case .plus:
                guard game.isInCatalog else {
                    continue
                }
            case .browse:
                guard game.isStoreOnly else {
                    continue
                }
            case .preorders:
                continue
            }
        }
        guard platform.admits(game.platform) else {
            continue
        }
        guard query.isEmpty || game.name.localizedStandardContains(query) else {
            continue
        }
        ids.append(game.id)
    }
    return ids
}

private func milliseconds(_ duration: Duration) -> String {
    let value = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    return String(format: "%.3f", value)
}

@MainActor private func libraryStore(_ state: CloudLibraryFeature.State) -> TestStoreOf<CloudLibraryFeature> {
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.continuousClock = ImmediateClock()
        $0.openURL = OpenURLEffect { _ in
            true
        }
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    store.exhaustivity = .off
    return store
}

private func readyState(_ snapshot: CloudLibrarySnapshot) -> CloudLibraryFeature.State {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.snapshot = snapshot
    return state
}

@Test func cloudListingReadsNeverDeriveAgain() {
    let state = readyState(largeCatalog())
    #expect(state.listing.derivations == .init(listings: 1, matches: 1, pages: 1))
    for _ in 0..<60 {
        _ = readAsTheLibraryViewDoes(state)
    }
    #expect(state.listing.derivations == .init(listings: 1, matches: 1, pages: 1))
    #expect(state.listedGames.count == 4_814)
    #expect(state.visibleGames.count == 40)
    #expect(state.pageCount == 121)
}

@MainActor @Test func cloudListingIgnoresActionsThatLeaveTheListAlone() async {
    let store = libraryStore(readyState(largeCatalog()))
    let settled = store.state.listing.derivations
    for index in 0..<50 {
        await store.send(.cardChecked(store.state.accountID!, "game-\(index)", .checking))
        await store.send(.cardChecked(store.state.accountID!, "game-\(index)", .streams))
        await store.send(.addToLibraryTapped("game-\(index)"))
        await store.send(.titleRefreshCooled(UUID()))
        await store.send(.failed(UUID(), UUID(), .network))
        _ = readAsTheLibraryViewDoes(store.state)
    }
    #expect(store.state.listing.derivations == settled)
    for index in 0..<20 {
        await store.send(.select("game-\(index)"))
        _ = readAsTheLibraryViewDoes(store.state)
        #expect(store.state.selectedGame?.id == "game-\(index)" || index == 19)
        await store.send(.select(nil))
        _ = readAsTheLibraryViewDoes(store.state)
    }
    await store.skipReceivedActions(strict: false)
    #expect(store.state.listing.derivations == settled)
    await store.send(.select("game-19"))
    #expect(store.state.selection == nil)
    await store.send(.select("missing"))
    #expect(store.state.selection == nil)
    await store.skipReceivedActions(strict: false)
}

@MainActor @Test func cloudListingPagesWithoutMatchingAgain() async {
    let snapshot = largeCatalog()
    let store = libraryStore(readyState(snapshot))
    let all = expectedMatches(snapshot, filter: .all, platform: .all, query: "")
    for page in 1...20 {
        await store.send(.turnPage(1))
        _ = readAsTheLibraryViewDoes(store.state)
        #expect(store.state.visibleGameIDs == Array(all[(40 * page)..<(40 * (page + 1))]))
    }
    #expect(store.state.listing.derivations == .init(listings: 1, matches: 1, pages: 21))
    #expect(store.state.visibleGames.map(\.id) == store.state.visibleGameIDs)
}

@MainActor @Test func cloudListingMatchesOncePerChangedInput() async {
    let snapshot = largeCatalog()
    let store = libraryStore(readyState(snapshot))
    var typed = ""
    for character in "shadow legends" {
        typed.append(character)
        await store.send(.binding(.set(\.query, typed)))
        _ = readAsTheLibraryViewDoes(store.state)
        #expect(store.state.matchingGames.map(\.id)
            == expectedMatches(snapshot, filter: .all, platform: .all, query: typed))
    }
    #expect(store.state.listing.derivations.matches == 15)
    #expect(store.state.listing.derivations.listings == 1)
    await store.send(.binding(.set(\.query, typed)))
    await store.send(.filter(.all))
    await store.send(.platform(.all))
    #expect(store.state.listing.derivations.matches == 15)
    await store.send(.binding(.set(\.query, "étoile")))
    #expect(store.state.matchingGames.map(\.id)
        == expectedMatches(snapshot, filter: .all, platform: .all, query: "étoile"))
    #expect(store.state.matchingGames.map(\.id)
        == expectedMatches(snapshot, filter: .all, platform: .all, query: "ETOILE"))
    await store.send(.binding(.set(\.query, "")))
    #expect(store.state.listing.derivations.matches == 17)
    for filter in CloudLibraryFilter.allCases {
        for platform in CloudPlatformFilter.allCases {
            await store.send(.filter(filter))
            await store.send(.platform(platform))
            #expect(store.state.matchingGames.map(\.id)
                == expectedMatches(snapshot, filter: filter, platform: platform, query: ""))
            #expect(store.state.page == 0)
        }
    }
    #expect(store.state.listing.derivations.listings == 1)
    #expect(store.state.listing.derivations.matches <= 17 + 40)
}

@Test func cloudListingFollowsAReplacedSnapshot() {
    let snapshot = largeCatalog(200)
    var state = readyState(snapshot)
    state.selection = "game-3"
    state.search("game")
    #expect(state.matchingGames.isEmpty)
    state.search("")
    let renamed = CloudGame(productId: "game-3", name: "Renamed", isOwned: true)
    state.snapshot = snapshot.replacing(renamed)
    #expect(state.selectedGame == renamed)
    #expect(state.listedGames.first { $0.id == "game-3" } == renamed)
    #expect(state.listing.derivations.listings == 2)
    state.snapshot = snapshot.replacing(CloudGame(productId: "game-3", name: "Hidden", visible: false))
    #expect(state.selectedGame == nil)
    #expect(!state.visibleGameIDs.contains("game-3"))
    state.snapshot = nil
    #expect(state.listedGames.isEmpty && state.visibleGames.isEmpty && state.pageCount == 1)
}

@Test func cloudListingEqualityFollowsItsInputs() {
    let snapshot = largeCatalog(200)
    var first = readyState(snapshot)
    var second = first
    _ = readAsTheLibraryViewDoes(first)
    #expect(first == second)
    second.search("shadow")
    #expect(first != second)
    first.listing.show(page: 1)
    first.listing.show(page: 0)
    first.search("shadow")
    #expect(first.listing.derivations != second.listing.derivations)
    #expect(first == second)
    second.snapshot = snapshot.replacing(CloudGame(productId: "game-3", name: "Renamed"))
    #expect(first != second)
}

@MainActor @Test func cloudListingKeepsSettledCardChecksAcrossAccountsAndWhenTheLibraryCloses() async {
    let store = libraryStore(readyState(largeCatalog(10)))
    await store.send(.cardChecked(store.state.accountID!, "game-1", .streams))
    await store.send(.cardChecked(store.state.accountID!, "game-2", .checking))
    #expect(store.state.cardChecks == ["game-1": .streams, "game-2": .checking])
    await store.send(.account(nil))
    #expect(store.state.cardChecks == ["game-1": .streams])
    #expect(store.state.snapshot == nil)
    await store.send(.stop)
    #expect(store.state.cardChecks == ["game-1": .streams])
}

@Test func cloudListingTimings() {
    let snapshot = largeCatalog()
    let clock = ContinuousClock()
    let state = readyState(snapshot)
    let onePass = clock.measure {
        _ = readAsTheLibraryViewDoes(state)
    }
    let sixtyPasses = clock.measure {
        for _ in 0..<60 {
            _ = readAsTheLibraryViewDoes(state)
        }
    }
    var searching = state
    let rematch = clock.measure {
        searching.query = "sha"
    }
    let sixtySearching = clock.measure {
        for _ in 0..<60 {
            _ = readAsTheLibraryViewDoes(searching)
        }
    }
    let relist = clock.measure {
        searching.snapshot = snapshot
    }
    print("LISTING one view pass ms=\(milliseconds(onePass))")
    print("LISTING 60 view passes ms=\(milliseconds(sixtyPasses))")
    print("LISTING one rematch for a query ms=\(milliseconds(rematch))")
    print("LISTING 60 view passes while searching ms=\(milliseconds(sixtySearching))")
    print("LISTING one relist of the snapshot ms=\(milliseconds(relist))")
    let other = state
    let equal = clock.measure {
        for _ in 0..<1_000 {
            _ = state == other
        }
    }
    print("LISTING 1000 state comparisons ms=\(milliseconds(equal))")
}

@Test func cloudListingActionTimings() {
    let clock = ContinuousClock()
    var live = readyState(largeCatalog())
    let reducer = CloudLibraryFeature()
    func reduce(_ action: CloudLibraryFeature.Action) {
        withDependencies {
            $0.uuid = .incrementing
            $0.locale = Locale(identifier: "en_GB")
        } operation: {
            _ = reducer.reduce(into: &live, action: action)
        }
    }
    var typed = ""
    var elapsed = clock.measure {
        for character in "shadow legends" {
            typed.append(character)
            reduce(.binding(.set(\.query, typed)))
            _ = readAsTheLibraryViewDoes(live)
        }
    }
    print("LISTING typing 14 keys with one view pass each ms=\(milliseconds(elapsed))")
    reduce(.binding(.set(\.query, "")))
    elapsed = clock.measure {
        for _ in 0..<20 {
            reduce(.turnPage(1))
            _ = readAsTheLibraryViewDoes(live)
        }
    }
    print("LISTING 20 pages with one view pass each ms=\(milliseconds(elapsed))")
    elapsed = clock.measure {
        for index in 0..<20 {
            reduce(.select("game-\(index)"))
            _ = readAsTheLibraryViewDoes(live)
            reduce(.select(nil))
            _ = readAsTheLibraryViewDoes(live)
        }
    }
    print("LISTING 20 select and close with one view pass each ms=\(milliseconds(elapsed))")
    elapsed = clock.measure {
        for index in 0..<1_000 {
            reduce(.cardChecked(live.accountID!, "game-\(index)", .checking))
            _ = readAsTheLibraryViewDoes(live)
        }
    }
    print("LISTING 1000 unrelated actions with one view pass each ms=\(milliseconds(elapsed))")
}
