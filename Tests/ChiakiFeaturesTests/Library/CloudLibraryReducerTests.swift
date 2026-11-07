@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func cloudLibraryRejectsPreviousAccountAndCancelledResults() async throws {
    let account = UUID()
    let attempt = UUID()
    let snapshot = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[]}
    """.utf8))
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .loading(attempt, fetch: nil)
    let store = TestStore(initialState: state) { CloudLibraryFeature() }
    await store.send(.loaded(UUID(), attempt, snapshot))
    await store.send(.loaded(account, UUID(), snapshot))
    await store.send(.stop) { $0.phase = .idle }
    await store.send(.loaded(account, attempt, snapshot))
    await store.send(.failed(account, attempt, .network))
}

@MainActor @Test func cloudLibraryKeepsALoadedLibraryWhenShownAgain() async throws {
    let account = UUID()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    state.snapshot = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[]}
    """.utf8))
    let store = TestStore(initialState: state) { CloudLibraryFeature() }
    await store.send(.stop)
    await store.send(.account(account))
}

@MainActor @Test func cloudLibraryKeepsItsFocusWhileAStreamCoversItAndForgetsItWhenTheAccountGoes(
) async throws {
    let account = UUID()
    var state = CloudLibraryFeature.State()
    state.accountID = account
    state.phase = .ready
    state.snapshot = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[]}
    """.utf8))
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
    }
    store.exhaustivity = .off
    await store.send(.focusMoved(.game("PPSA01234_00"))) {
        $0.heldFocus = .game("PPSA01234_00")
    }
    await store.send(.stop)
    await store.send(.account(account))
    #expect(store.state.phase == .ready)
    #expect(store.state.heldFocus == .game("PPSA01234_00"))
    await store.send(.account(nil))
    #expect(store.state.heldFocus == nil)
    await store.skipInFlightEffects(strict: false)
}

@MainActor @Test func cloudLibraryAccountRemovalClearsCatalogAndSelection() async throws {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.query = "Old account"
    state.selection = "old-entitlement"
    state.snapshot = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[]}
    """.utf8))
    let store = TestStore(initialState: state) { CloudLibraryFeature() }
    await store.send(.account(nil)) { $0 = .init() }
}

@Test func cloudCatalogPreservesLaunchIdentityAndRejectsDuplicateIDs() throws {
    let game = """
    {"productId":"catalog-id","name":"Example","imageUrl":"","landscapeImageUrl":"",
    "platform":"ps5","category":"owned","isOwned":true,"plusCatalog":false,
    "streamServiceType":"pscloud","streamIdentifier":"canonical-entitlement","conceptUrl":""}
    """
    func payload(_ games: String) -> Data {
        Data("""
        {"schemaVersion":11,"nativeMode":true,"settledLocale":"nl-NL","resolvedStoreLang":"nl",
        "games":[\(games)]}
        """.utf8)
    }
    let snapshot = try CloudLibrarySnapshot.decode(payload(game))
    #expect(snapshot.games.first?.productId == "catalog-id")
    #expect(snapshot.settledLocale == "nl-NL")
    #expect(throws: CloudLibraryFailure.invalidCatalog) {
        try CloudLibrarySnapshot.decode(payload(game + "," + game))
    }
}

@MainActor @Test func cloudPaginationIsBoundedAndSearchIncludesUnloadedTitles() async throws {
    let games: [[String: Any]] = (0..<83).map { index in
        ["productId": "game-\(index)", "name": "Game \(index)", "platform": "ps5",
         "category": "owned", "isOwned": true, "plusCatalog": false,
         "streamServiceType": "pscloud",
         "streamIdentifier": "EP9000-PPSA\(10000 + index)_00-GAME000000000000"]
    }
    let data = try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 11, "nativeMode": true, "settledLocale": "en-GB",
        "resolvedStoreLang": "en", "games": games
    ])
    var state = CloudLibraryFeature.State()
    state.snapshot = try CloudLibrarySnapshot.decode(data)
    state.phase = .ready
    let store = TestStore(initialState: state) { CloudLibraryFeature() }
    #expect(store.state.visibleGames.count == 40)
    #expect(store.state.pageCount == 3)
    await store.send(.turnPage(1)) { $0.listing.show(page: 1) }
    await store.send(.turnPage(1)) { $0.listing.show(page: 2) }
    #expect(store.state.visibleGames.count == 3)
    await store.send(.turnPage(1))
    #expect(store.state.page == 2)
    await store.send(.binding(.set(\.query, "Game 82"))) {
        $0.search("Game 82")
    }
    #expect(store.state.visibleGames.map(\.id) == ["game-82"])
    await store.send(.binding(.set(\.query, ""))) {
        $0.search("")
    }
    #expect(store.state.visibleGames.count == 40)
}

@Test func samplePreordersCoverEachReleaseStateWithoutTouchingRealTitles() throws {
    let base = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[{"productId":"real","name":"Real","platform":"ps5","category":"owned","isOwned":true,
    "plusCatalog":false,"streamServiceType":"pscloud","streamIdentifier":"real"}]}
    """.utf8))
    let now = Date(timeIntervalSince1970: 1_791_273_600)
    let sampled = CloudSamplePreorders.adding(to: base, now: now)
    #expect(sampled.games.count == 4)
    #expect(sampled.games.last == base.games[0])
    #expect(sampled.games.map(CloudSamplePreorders.isSample) == [true, true, true, false])
    #expect(sampled.games.map { $0.release.label(now: now).map { String(localized: $0) } } == [
        "Releases in 00:01:15",
        "Releases in 3d 04:05:00",
        "Release date not announced",
        nil
    ])
    #expect(CloudSamplePreorders.adding(to: sampled, now: now).games.count == 4)
}

@MainActor @Test func cloudPlatformFilterMatchesTheCatalogLabels() async throws {
    let games: [[String: Any]] = ["PS3", "PS4", "PS5"].map { label in
        ["productId": "game-\(label)", "name": "Game \(label)", "platform": label,
         "category": "owned", "isOwned": true, "plusCatalog": true,
         "streamServiceType": "psnow", "streamIdentifier": "stream-\(label)"]
    }
    let data = try JSONSerialization.data(withJSONObject: [
        "schemaVersion": 11, "nativeMode": true, "settledLocale": "en-GB",
        "resolvedStoreLang": "en", "games": games
    ])
    var state = CloudLibraryFeature.State()
    state.snapshot = try CloudLibrarySnapshot.decode(data)
    state.phase = .ready
    for (tag, label) in [(CloudPlatformFilter.ps3, "PS3"), (.ps4, "PS4"), (.ps5, "PS5")] {
        state.platform = tag
        #expect(state.matchingGames.map(\.id) == ["game-\(label)"])
    }
    state.platform = .all
    #expect(state.matchingGames.count == 3)
}
