@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func theTouchLibraryOpensPagesOnlyFromWhereTheyLead() async {
    let console = UUID()
    let store = TestStore(initialState: MobileShellFeature.State()) {
        MobileShellFeature()
    }
    await store.send(.settingsOpened(.sound))
    await store.send(.consoleOpened(console)) {
        $0.page = .console(console)
    }
    await store.send(.consoleOpened(UUID()))
    await store.send(.accountOpened) {
        $0.page = .account
    }
    await store.send(.settingsOpened(.sound)) {
        $0.page = .settings(.sound)
    }
    await store.send(.settingsOpened(.network)) {
        $0.page = .settings(.network)
    }
    await store.send(.back) {
        $0.page = .account
        $0.forward = false
    }
    await store.send(.back) {
        $0.page = .home
    }
    await store.send(.back)
}

@MainActor @Test func backInTheTouchLibraryLeavesTheConsolePageForTheSection() async {
    let console = UUID()
    let store = TestStore(initialState: LibraryFeature.State(section: .consoles)) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    await store.send(.mobile(.consoleOpened(console)))
    #expect(store.state.mobileCanGoBack)
    await store.send(.mobileBackTapped)
    await store.receive(.mobile(.back)) {
        $0.mobile.page = .home
    }
    #expect(!store.state.mobileCanGoBack)
}

@MainActor @Test func backInTheTouchLibraryClosesTheOpenCloudGameFirst() async {
    var state = LibraryFeature.State(section: .cloud)
    state.cloudLibrary.selection = "game"
    let store = TestStore(initialState: state) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    #expect(store.state.mobileCanGoBack)
    await store.send(.mobileBackTapped)
    await store.receive(.cloudLibrary(.select(nil)))
    #expect(store.state.cloudLibrary.selection == nil)
    #expect(store.state.mobile.page == .home)
    await store.skipInFlightEffects(strict: false)
}

@MainActor @Test func choosingASectionInTheTouchRailLeavesAnyPushedPage() async {
    let store = TestStore(initialState: LibraryFeature.State(section: .consoles)) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    await store.send(.mobile(.accountOpened))
    await store.send(.mobile(.settingsOpened(.picture)))
    await store.send(.mobileSectionTapped(.consoles)) {
        $0.mobile.page = .home
    }
    await store.send(.mobileSectionTapped(.trophies))
    await store.receive(.sectionSelected(.trophies)) {
        $0.section = .trophies
    }
    await store.skipInFlightEffects(strict: false)
}

@MainActor @Test func aRemovedConsoleTakesTheTouchLibraryBackToTheSection() async {
    let console = UUID()
    let store = TestStore(initialState: LibraryFeature.State(section: .consoles)) {
        LibraryFeature()
    }
    store.exhaustivity = .off
    await store.send(.mobile(.consoleOpened(console)))
    await store.send(.catalogChanged) {
        $0.mobile.page = .home
    }
}
