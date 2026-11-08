@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

private func catalog(
    _ ids: [String], forSale: [String] = [], flagged: [String] = []
) throws -> CloudLibrarySnapshot {
    let games = (ids.map { ($0, "owned") } + forSale.map { ($0, "browse") }).map { id, category in
        """
        {"productId":"\(id)","name":"Game \(id)","platform":"ps5",
        "category":"\(category)","isOwned":\(category == "owned"),"plusCatalog":false,
        "streamServiceType":"pscloud","streamIdentifier":"\(id)",
        "unstreamableKey":"\(flagged.contains(id)
            ? id
            : "")"}
        """
    }.joined(separator: ",")
    return try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[\(games)]}
    """.utf8))
}

private func played(_ id: String, at seconds: TimeInterval) -> CloudRecentlyPlayed {
    CloudRecentlyPlayed(productId: id, lastPlayed: Date(timeIntervalSince1970: seconds))
}

@Test func recentlyPlayedFilterKeepsPlayedGamesNewestFirst() throws {
    var listing = CloudLibraryListing()
    listing.snapshot = try catalog(["a", "b", "c"])
    listing.recentlyPlayed = [played("c", at: 300), played("a", at: 200), played("gone", at: 100)]
    listing.filter = .recent
    #expect(listing.matching.map(\.productId) == ["c", "a"])
    #expect(listing.lastPlayed(listing.matching[0]) == Date(timeIntervalSince1970: 300))
    listing.filter = .all
    #expect(listing.matching.count == 3)
    #expect(listing.lastPlayed(listing.matching[1]) == nil)
}

@MainActor @Test func historyThatArrivesWithTheLibraryOpensOnRecentlyPlayed() async throws {
    let account = UUID()
    let history = [played("a", at: 100)]
    let snapshot = try catalog(["a"])
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.continuousClock = TestClock()
        $0.catalog.library = { _, _, _, _ in
            snapshot
        }
        $0.catalog.recentlyPlayed = { _ in
            history
        }
    }
    store.exhaustivity = .off
    await store.send(.refresh)
    await store.receive(.recentlyPlayed(account, UUID(0), history))
    await store.receive(.loaded(account, UUID(0), snapshot))
    #expect(store.state.phase == .ready)
    #expect(store.state.filter == .recent)
    await store.send(.recentlyPlayed(account, UUID(), []))
    await store.send(.recentlyPlayed(UUID(), UUID(0), []))
    #expect(store.state.filter == .recent)
}

@MainActor @Test func lateHistoryShowsTheChipWithoutSwitchingFilters() async throws {
    let account = UUID()
    let history = [played("a", at: 100)]
    let snapshot = try catalog(["a"])
    let (arrivals, arrive) = AsyncStream<[CloudRecentlyPlayed]>.makeStream()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.continuousClock = ImmediateClock()
        $0.catalog.library = { _, _, _, _ in
            snapshot
        }
        $0.catalog.recentlyPlayed = { _ in
            for await played in arrivals {
                return played
            }
            return []
        }
    }
    store.exhaustivity = .off
    await store.send(.refresh)
    await store.receive(.loaded(account, UUID(0), snapshot))
    #expect(store.state.filter == .all)
    #expect(!store.state.filters.contains(.recent))
    arrive.yield(history)
    await store.receive(.recentlyPlayed(account, UUID(0), history))
    #expect(store.state.filters.first == .recent)
    #expect(store.state.filter == .all)
}

@MainActor @Test func aPickedFilterIsKeptAndAnEmptiedRecentFallsBackToAll() async throws {
    let account = UUID()
    let attempt = UUID()
    let history = [played("a", at: 100)]
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.snapshot = try catalog(["a"])
    state.phase = .ready
    state.recentAttempt = attempt
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    }
    await store.send(.filter(.owned)) {
        $0.filterChoice = .picked
        $0.filter = .owned
    }
    await store.send(.recentlyPlayed(account, attempt, history)) {
        $0.listing.recentlyPlayed = history
    }
    #expect(store.state.filters.first == .recent)
    await store.send(.filter(.recent)) {
        $0.filter = .recent
    }
    await store.send(.recentlyPlayed(account, attempt, [])) {
        $0.listing.recentlyPlayed = []
        $0.filter = .all
    }
    #expect(store.state.filters.first == .all)
}

@Test func searchingLooksAcrossEveryTabIncludingGamesForSale() throws {
    var listing = CloudLibraryListing()
    listing.snapshot = try catalog(["owned"], forSale: ["sale"])
    listing.filter = .owned
    #expect(listing.matching.map(\.productId) == ["owned"])
    listing.query = "Game"
    #expect(listing.matching.map(\.productId) == ["owned", "sale"])
    listing.query = "sale"
    #expect(listing.matching.map(\.productId) == ["sale"])
    listing.query = ""
    #expect(listing.matching.map(\.productId) == ["owned"])
}

@Test func aFlaggedGameStaysInRecentlyPlayedUntilAClickedCheckRefusesIt() throws {
    var listing = CloudLibraryListing()
    listing.snapshot = try catalog(["a", "flagged"], flagged: ["flagged"])
    listing.recentlyPlayed = [played("flagged", at: 300), played("a", at: 200)]
    listing.filter = .recent
    #expect(listing.matching.map(\.productId) == ["flagged", "a"])
    listing.unstreamable = ["flagged"]
    #expect(listing.matching.map(\.productId) == ["a"])
}

@MainActor @Test func loadingRecentlyPlayedSendsNoStoreChecks() async throws {
    let account = UUID()
    let flagged = ["f1", "f2"]
    let history = flagged.enumerated().map { played($1, at: TimeInterval(100 - $0)) }
    let snapshot = try catalog(flagged, flagged: flagged)
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
        $0.continuousClock = ImmediateClock()
        $0.catalog.library = { _, _, _, _ in
            snapshot
        }
        $0.catalog.recentlyPlayed = { _ in
            history
        }
    }
    store.exhaustivity = .off
    await store.send(.refresh)
    await store.receive(.recentlyPlayed(account, UUID(0), history))
    await store.receive(.loaded(account, UUID(0), snapshot))
    await store.finish()
    #expect(store.state.cardChecks.isEmpty)
    #expect(store.state.filter == .recent)
    #expect(store.state.matchingGames.map(\.productId) == flagged)
}

@Test func aFlaggedCardIsMarkedUntilTheStoreAnswers() throws {
    let snapshot = try catalog(["plain", "flagged"], flagged: ["flagged"])
    let plain = try #require(snapshot.games.first { $0.id == "plain" })
    let flagged = try #require(snapshot.games.first { $0.id == "flagged" })
    #expect(CloudStreamMark(plain, check: nil) == .none)
    #expect(CloudStreamMark(flagged, check: nil) == .unconfirmed)
    #expect(CloudStreamMark(flagged, check: .checking) == .unconfirmed)
    #expect(CloudStreamMark(flagged, check: .unavailable(.noAnswer)) == .unconfirmed)
    #expect(CloudStreamMark(flagged, check: .streams) == .none)
    #expect(CloudStreamMark(flagged, check: .notStreamable) == .unavailable)
    #expect(CloudStreamMark(plain, check: .refused) == .unavailable)
    #expect(CloudStreamMark.unconfirmed.icon == .cloudUnconfirmed)
    #expect(CloudStreamMark.unconfirmed.label.map { String(localized: $0) } == "Not confirmed for cloud")
    #expect(CloudStreamMark.unavailable.label == nil)
    #expect(CloudStreamMark.unavailable.statusIcon == .store)
    #expect(CloudStreamMark.unavailable.spoken.map { String(localized: $0) } == "Not streamable")
}

@Test func aConfirmedFlaggedGameShowsItsRealStanding() throws {
    let snapshot = try catalog(["flagged"], forSale: ["sale"], flagged: ["flagged", "sale"])
    let flagged = try #require(snapshot.games.first { $0.id == "flagged" })
    let sale = try #require(snapshot.games.first { $0.id == "sale" })
    #expect(flagged.standing(after: nil) == .mayStream)
    #expect(flagged.standing(after: .checking) == .mayStream)
    #expect(flagged.standing(after: .notStreamable) == .store)
    #expect(String(localized: flagged.standing(after: .notStreamable).label) == "View in Store")
    #expect(flagged.standing(after: .streams) == .inLibrary)
    #expect(String(localized: flagged.standing(after: .streams).label) == "In your library")
    #expect(sale.standing(after: .streams) == .store)
}

@Test func aGameTheStreamServiceRefusesLeavesAllStreamableAndRecentlyPlayedButStaysInTheLibrary() throws {
    var listing = CloudLibraryListing()
    listing.snapshot = try catalog(["a", "b"])
    listing.recentlyPlayed = [played("b", at: 200), played("a", at: 100)]
    listing.unstreamable = ["b"]
    #expect(listing.matching.map(\.productId) == ["a"])
    listing.filter = .recent
    #expect(listing.matching.map(\.productId) == ["a"])
    listing.filter = .owned
    #expect(listing.matching.map(\.productId) == ["a", "b"])
}
