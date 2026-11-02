import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture
@testable import ChiakiFeatures

private let ps5 = CloudGame(
    productId: "EP9000-PPSA01234_00-ASTROBOT00000000",
    name: "Astro Bot",
    isOwned: true
)
private let psNow = CloudGame(
    productId: "EP9000-CUSA01234_00-CLASSIC000000000", name: "Classic", platform: "PS4",
    streamServiceType: "psnow"
)

private func checks(for game: CloudGame) throws -> CloudLaunchChecks {
    try CloudLaunchChecks(request: CloudLaunchRequest(accountID: UUID(), game: game), attempt: UUID())
}

private func marks(_ checks: CloudLaunchChecks) -> [CloudLaunchChecks.Mark] {
    checks.steps.map(checks.mark)
}

@MainActor private func libraryStore(
    selecting game: CloudGame, events: [CloudLaunchClearanceEvent]
) -> TestStoreOf<CloudLibraryFeature> {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.snapshot = CloudLibrarySnapshot(settledLocale: "en-US", games: [ps5, psNow])
    state.selection = game.id
    state.cardChecks[ps5.id] = .streams
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.catalog.clearForLaunch = { _, _ in
            AsyncStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    store.exhaustivity = .off
    return store
}

@MainActor private func settle(_ store: TestStoreOf<CloudLibraryFeature>) async {
    await store.finish()
    await store.skipReceivedActions(strict: false)
}

@Test func launchChecksShowTheCloudRowAsUncheckedBeforeAnyCheck() throws {
    let row = try checks(for: ps5)
    #expect(row.steps == [.premium, .yourCopy, .cloudGame, .restrictions, .release])
    #expect(row.steps.map(\.label) == ["Premium", "Your copy", "Cloud game", "Restrictions", "Release"])
    #expect(marks(row) == Array(repeating: .unchecked, count: 5))
    #expect(row.reason == nil)
}

@Test func launchChecksTickEveryStepOfAClearedPS5Launch() throws {
    var row = try checks(for: ps5)
    row.observe(.loadingLibrary)
    #expect(row.phase == .starting)
    #expect(marks(row) == [.unchecked, .unchecked, .unchecked, .unchecked, .unchecked])
    row.observe(.cloudStreaming)
    #expect(marks(row) == [.checking, .unchecked, .unchecked, .unchecked, .unchecked])
    row.observe(.entitlement)
    #expect(marks(row) == [.passed, .checking, .unchecked, .unchecked, .unchecked])
    row.observe(.cloudGame)
    row.observe(.exclusions)
    #expect(marks(row) == [.passed, .passed, .passed, .checking, .unchecked])
    row.observe(.release)
    #expect(marks(row) == [.passed, .passed, .passed, .passed, .checking])
    #expect(row.handOff == nil)
    row.finish(.success(.cleared(nil)))
    #expect(marks(row) == Array(repeating: .passed, count: 5))
    #expect(row.handOff?.game == ps5)
    #expect(row.reason == nil)
    row.launched()
    #expect(row.phase == .launched)
    #expect(row.handOff == nil)
    #expect(marks(row) == Array(repeating: .passed, count: 5))
}

@Test func launchChecksCrossYourCopyAndLeaveTheRestUnchecked() throws {
    var row = try checks(for: ps5)
    let refusal = CloudClearanceRefusal(refusal: .notStreamable, notice: "Not on PS5 cloud")
    for check in [CloudLaunchCheck.loadingLibrary, .cloudStreaming, .entitlement] {
        row.observe(check)
    }
    row.finish(.success(.refused(refusal)))
    #expect(marks(row) == [.passed, .refused, .unchecked, .unchecked, .unchecked])
    #expect(row.reason == "This title can’t be streamed: Not on PS5 cloud")
    #expect(row.handOff == nil)
    row.observe(.cloudGame)
    #expect(marks(row) == [.passed, .refused, .unchecked, .unchecked, .unchecked])
}

@Test func launchChecksFoldOwnershipAndEntitlementIntoYourCopy() throws {
    var row = try checks(for: ps5)
    row.observe(.loadingLibrary)
    row.observe(.cloudStreaming)
    row.observe(.ownership)
    #expect(marks(row) == [.passed, .checking, .unchecked, .unchecked, .unchecked])
    row.observe(.entitlement)
    #expect(row.steps.count == 5)
    #expect(marks(row) == [.passed, .checking, .unchecked, .unchecked, .unchecked])
    row.observe(.loadingLibrary)
    #expect(marks(row) == [.passed, .checking, .unchecked, .unchecked, .unchecked])
    for check in [CloudLaunchCheck.cloudGame, .exclusions, .release] {
        row.observe(check)
    }
    row.finish(.success(.cleared(nil)))
    #expect(marks(row) == Array(repeating: .passed, count: 5))
}

@Test func launchChecksShowMembershipAndReleaseForPSNow() throws {
    var row = try checks(for: psNow)
    #expect(row.steps == [.membership, .release])
    #expect(row.steps.map(\.label) == ["Membership", "Release"])
    row.observe(.loadingLibrary)
    row.observe(.membership)
    #expect(marks(row) == [.checking, .unchecked])
    row.observe(.cloudStreaming)
    #expect(marks(row) == [.checking, .unchecked])
    row.observe(.release)
    #expect(marks(row) == [.passed, .checking])
    row.finish(.success(.cleared(nil)))
    #expect(marks(row) == [.passed, .passed])
}

@Test func launchChecksRefusedWhileLoadingLeaveEveryStepUnchecked() throws {
    var row = try checks(for: ps5)
    row.observe(.loadingLibrary)
    row.finish(.success(.refused(CloudClearanceRefusal(refusal: .notListed))))
    #expect(marks(row) == Array(repeating: .unchecked, count: 5))
    #expect(row.reason == "This title isn’t in the cloud catalog.")
}

@Test func launchChecksThatCannotBeAnsweredCrossTheCurrentStep() throws {
    var row = try checks(for: ps5)
    row.observe(.cloudStreaming)
    row.finish(.failure(CatalogFailure(reason: .unavailable, needsSignIn: true)))
    #expect(marks(row) == [.refused, .unchecked, .unchecked, .unchecked, .unchecked])
    #expect(row.reason == CloudPlaybackFailureMessage.text(for: .signInRequired))
}

@MainActor @Test func checkAndPlayRunsTheChecksAndOffersTheClearedLaunch() async throws {
    let events: [CloudLaunchClearanceEvent] = [
        .check(.loadingLibrary), .check(.cloudStreaming), .check(.entitlement), .check(.cloudGame),
        .check(.exclusions), .check(.release), .finished(.success(.cleared(nil)))
    ]
    let store = libraryStore(selecting: ps5, events: events)
    let request = try CloudLaunchRequest(accountID: UUID(), game: ps5)
    await store.send(.checkAndPlay(request))
    await store.receive(.delegate(.play(request)))
    await settle(store)
    let checks = try #require(store.state.launchChecks)
    #expect(marks(checks) == Array(repeating: .passed, count: 5))
    #expect(checks.phase == .launched)
    #expect(checks.handOff == nil)
}

@MainActor @Test func checkAndPlayStopsWhenTheCardCloses() async throws {
    let store = libraryStore(selecting: ps5, events: [.check(.loadingLibrary), .check(.cloudStreaming)])
    await store.send(.checkAndPlay(try CloudLaunchRequest(accountID: UUID(), game: ps5)))
    await settle(store)
    let attempt = try #require(store.state.launchChecks?.attempt)
    #expect(store.state.launchChecks?.phase == .checking(.premium))
    await store.send(.select(nil))
    #expect(store.state.launchChecks == nil)
    await store.send(.launchChecked(attempt, .finished(.success(.cleared(nil)))))
    #expect(store.state.launchChecks == nil)
}

@MainActor @Test func checkAndPlayForgetsTheRowWhenTheChecksAreCancelled() async throws {
    let store = libraryStore(
        selecting: ps5,
        events: [
            .check(.loadingLibrary),
            .check(.cloudStreaming),
            .finished(.failure(.init(reason: .cancelled)))
        ]
    )
    await store.send(.checkAndPlay(try CloudLaunchRequest(accountID: UUID(), game: ps5)))
    await settle(store)
    #expect(store.state.launchChecks == nil)
}

@MainActor @Test func checkAndPlayAgainRerunsEveryCheck() async throws {
    let refused = CloudClearanceRefusal(refusal: .needsPremium)
    let store = libraryStore(
        selecting: ps5,
        events: [.check(.loadingLibrary), .check(.cloudStreaming), .finished(.success(.refused(refused)))]
    )
    let request = try CloudLaunchRequest(accountID: UUID(), game: ps5)
    await store.send(.checkAndPlay(request))
    await settle(store)
    let first = try #require(store.state.launchChecks)
    #expect(marks(first) == [.refused, .unchecked, .unchecked, .unchecked, .unchecked])
    #expect(first.reason == "PlayStation Plus Premium is required to stream this title.")
    await store.send(.select(ps5.id))
    #expect(store.state.launchChecks == first)
    store.dependencies.catalog.clearForLaunch = { _, _ in
        AsyncStream { $0.finish() }
    }
    await store.send(.checkAndPlay(request))
    let second = try #require(store.state.launchChecks)
    #expect(second.attempt != first.attempt)
    #expect(second.phase == .starting)
    #expect(marks(second) == Array(repeating: .unchecked, count: 5))
    #expect(second.reason == nil)
    await store.send(.launchChecked(first.attempt, .check(.release)))
    #expect(store.state.launchChecks == second)
    await store.finish()
}

@MainActor @Test func aLaunchHandsOffWithoutTheDetailViewOnScreen() async throws {
    let store = libraryStore(selecting: ps5, events: [.finished(.success(.cleared(nil)))])
    let request = try CloudLaunchRequest(accountID: UUID(), game: ps5)
    await store.send(.checkAndPlay(request))
    await store.receive(.delegate(.play(request)))
    #expect(store.state.launchChecks?.phase == .launched)
}

@MainActor @Test func aGameTheWebsiteListDoubtsWarnsBeforeItPlays() async throws {
    let store = libraryStore(selecting: ps5, events: [.finished(.success(.cleared(nil)))])
    await store.send(.cardChecked(store.state.accountID!, ps5.id, .checking))
    let request = try CloudLaunchRequest(accountID: UUID(), game: ps5)
    await store.send(.checkAndPlay(request))
    await settle(store)
    #expect(store.state.websiteWarning != nil)
    #expect(store.state.launchChecks?.handOff == request)
    await store.send(.websiteWarning(.presented(.play)))
    await store.receive(.delegate(.play(request)))
    #expect(store.state.launchChecks?.phase == .launched)
}

@MainActor @Test func cancellingTheWebsiteWarningForgetsTheClearedChecks() async throws {
    let store = libraryStore(selecting: ps5, events: [.finished(.success(.cleared(nil)))])
    await store.send(.cardChecked(store.state.accountID!, ps5.id, .checking))
    let request = try CloudLaunchRequest(accountID: UUID(), game: ps5)
    await store.send(.checkAndPlay(request))
    await settle(store)
    #expect(store.state.websiteWarning != nil)
    await store.send(.websiteWarning(.dismiss))
    #expect(store.state.websiteWarning == nil)
    #expect(store.state.launchChecks == nil)
    await store.send(.checkAndPlay(request))
    #expect(store.state.launchChecks?.phase == .starting)
}
