import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

@MainActor private func libraryStore(
    _ state: LibraryFeature.State = LibraryFeature.State(section: .consoles),
    clock: TestClock<Duration> = TestClock()
) -> TestStoreOf<LibraryFeature> {
    let store = TestStore(initialState: state) {
        LibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.continuousClock = clock
        $0.date.now = Date(timeIntervalSince1970: 0)
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func theAccountSheetOpensFromTheRailAndPassesItsChoiceOn() async {
    let account = UUID()
    let store = libraryStore()
    await store.send(.accountTapped) {
        $0.accountSheet = LibraryAccountSheetFeature.State()
    }
    await store.send(.accountSheet(.presented(.chose(.account(account))))) {
        $0.accountSheet = nil
        $0.focusRequest = .returnToAccount
    }
    await store.receive(.requested(.selectAccount(account)))
    await store.receive(.delegate(.requested(.selectAccount(account))))
}

@MainActor @Test func dismissingTheAccountSheetReturnsFocusToTheAccountStop() async {
    var state = LibraryFeature.State(section: .consoles)
    state.accountSheet = LibraryAccountSheetFeature.State()
    let store = libraryStore(state)
    await store.send(.accountSheet(.dismiss)) {
        $0.accountSheet = nil
        $0.focusRequest = .returnToAccount
    }
    await store.send(.focusRequestHandled) {
        $0.focusRequest = nil
    }
}

@MainActor @Test func refreshingTheAccountsAlsoRefreshesTheCloudStatus() async {
    let store = libraryStore()
    await store.send(.requested(.refreshAccounts))
    await store.receive(.delegate(.requested(.refreshAccounts)))
    await store.receive(.cloudStatus(.refresh))
}

@MainActor @Test func theShelfWaitsForTheCatalogOnlyForItsPatience() async {
    let clock = TestClock()
    let store = libraryStore(clock: clock)
    await store.send(.activityChanged(LibraryActivity(catalog: .loading))) {
        $0.activity.catalog = .loading
        $0.consoleLoad = .waiting
    }
    await clock.advance(by: ConsoleShelfLoad.patience)
    await store.receive(.consoleLoadElapsed) {
        $0.consoleLoad = .slow
    }
    await store.send(.activityChanged(LibraryActivity(catalog: .loaded))) {
        $0.activity.catalog = .loaded
        $0.consoleLoad = .loaded
        $0.focusRequest = .firstConsole
    }
}

@MainActor @Test func aCatalogThatLoadsInTimeNeverShowsTheShelfEarly() async {
    let clock = TestClock()
    let store = libraryStore(clock: clock)
    await store.send(.activityChanged(LibraryActivity(catalog: .loading)))
    await store.send(.activityChanged(LibraryActivity(catalog: .loaded))) {
        $0.consoleLoad = .loaded
    }
    await clock.advance(by: ConsoleShelfLoad.patience)
    #expect(store.state.consoleLoad == .loaded)
}

@MainActor @Test func aFinishedRefreshReadsTheCloudStatusAgain() async {
    let account = UUID()
    @Shared(.selectedAccount) var selected
    $selected.withLock {
        $0 = account
    }
    var state = LibraryFeature.State(section: .consoles)
    state.scenePhase = .active
    state.activity = LibraryActivity(refresh: .refreshing)
    let store = libraryStore(state)
    await store.send(.activityChanged(LibraryActivity(refresh: .idle)))
    await store.receive(.accountsRefreshed)
    await store.receive(.cloudStatus(.select(account)))
}

@MainActor @Test func contentFocusGoesToTheShownSection() async {
    let store = libraryStore(LibraryFeature.State(section: .cloud))
    let entry = LibraryContentFocus(.platform, horizontalPosition: 320)
    await store.send(.contentFocusRequested(entry))
    await store.receive(.cloudLibrary(.focusRequested(entry))) {
        $0.cloudLibrary.contentFocus = entry
    }
    let consoles = libraryStore()
    await consoles.send(.contentFocusRequested(entry)) {
        $0.focusRequest = .firstConsole
    }
}

@MainActor @Test func focusLeavingTheCloudBecomesARequestForTheLibrary() async {
    let store = libraryStore(LibraryFeature.State(section: .cloud))
    await store.send(.cloudLibrary(.leaveContent(.up, fromFilter: true)))
    await store.receive(.cloudLibrary(.delegate(.leftContent(.up, fromFilter: true)))) {
        $0.focusRequest = .leftCloud(.up, fromFilter: true)
    }
    await store.send(.cloudLibrary(.backToRail))
    await store.receive(.cloudLibrary(.delegate(.backToRail))) {
        $0.focusRequest = .rail
    }
}

@MainActor @Test func theLibraryAsksForRecentlyPlayedTitlesOnlyOnTheConsoleShelf() async {
    let account = UUID()
    @Shared(.accounts) var accounts
    @Shared(.selectedAccount) var selected
    $accounts.withLock {
        $0 = [.init(id: account, name: "PSN", kind: .npsso, accountID: nil)]
    }
    $selected.withLock {
        $0 = account
    }
    let store = libraryStore()
    await store.send(.scenePhaseChanged(.active))
    let selection = RecentlyPlayedReducer.Selection(profileID: account, eligible: false)
    await store.receive(.delegate(.showRecentlyPlayed(selection)))
    #expect(store.state.recentlyPlayedShown == selection)
    await store.send(.catalogChanged)
    await store.send(.scenePhaseChanged(.inactive)) {
        $0.scenePhase = .inactive
        $0.recentlyPlayedShown = nil
    }
    await store.skipInFlightEffects(strict: false)
}
