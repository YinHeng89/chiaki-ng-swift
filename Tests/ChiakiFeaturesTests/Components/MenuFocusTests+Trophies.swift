@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import SwiftUI
import Testing

private let firstGame = TrophyTitle(id: "NPWR00001_00", name: "First", progress: 30)
private let secondGame = TrophyTitle(id: "NPWR00002_00", name: "Second", progress: 60)

private func sampleTrophies() -> PSNTrophiesClient {
    PSNTrophiesClient(
        summary: { _ throws(PSNTrophiesFailure) in
            TrophySummary(level: 12, tier: 1, progress: 20, earned: TrophyCounts(bronze: 3))
        },
        titles: { _ throws(PSNTrophiesFailure) in
            [firstGame, secondGame]
        },
        trophies: { _, _ throws(PSNTrophiesFailure) in
            TitleTrophies(
                groups: [TrophyGroup(id: "default", name: "Base")],
                trophies: [
                    PSNTrophy(id: 0, grade: .bronze, name: "Start", earned: true),
                    PSNTrophy(id: 1, grade: .gold, name: "Secret", hidden: true)
                ]
            )
        }
    )
}

private let manyGames = (1 ... 120).map { index in
    TrophyTitle(id: String(format: "NPWR%05d_00", index), name: "Game \(index)", progress: index % 100)
}

private func manyTrophies() -> PSNTrophiesClient {
    PSNTrophiesClient(
        summary: { _ throws(PSNTrophiesFailure) in
            TrophySummary(level: 300, tier: 3, progress: 50, earned: TrophyCounts(bronze: 900))
        },
        titles: { _ throws(PSNTrophiesFailure) in
            manyGames
        },
        trophies: { _, _ throws(PSNTrophiesFailure) in
            TitleTrophies(
                groups: [],
                trophies: (0 ..< 80).map {
                    PSNTrophy(id: $0, grade: .bronze, name: "Trophy \($0)", earned: $0 % 2 == 0)
                }
            )
        }
    )
}

private func slowTrophies(released: LockIsolated<Bool>) -> PSNTrophiesClient {
    var client = sampleTrophies()
    client.titles = { _ throws(PSNTrophiesFailure) in
        while !released.value {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return [firstGame, secondGame]
    }
    return client
}

/// A prompt shown over the library the way the app shows its quit prompt.
@Observable @MainActor private final class StandInModal {
    /// Whether the prompt is shown.
    var shown = false
}

/// Presents the app's alert card over content while its prompt is shown; any choice dismisses it.
private struct StandInModalHost<Content: View>: View {
    /// The prompt.
    let modal: StandInModal
    /// What the prompt covers.
    let content: Content

    var body: some View {
        content.modifier(AppAlertPresentation(alert: alert, systemImage: nil) { _ in
            modal.shown = false
        })
    }

    private var alert: AlertState<Bool>? {
        guard modal.shown else {
            return nil
        }
        return AlertState {
            TextState("Quit chiaki-ng?")
        } actions: {
            ButtonState(role: .cancel, action: false) {
                TextState("Cancel")
            }
            ButtonState(action: true) {
                TextState("Quit")
            }
        }
    }
}

extension MenuFocusTests {
    @MainActor private func trophiesLibrary(
        quits: LockIsolated<Int>,
        trophies: PSNTrophiesClient = sampleTrophies(),
        section: LibrarySection = .trophies,
        modal: StandInModal = StandInModal(),
        compact: Bool = false,
        layout: ScreenLayout? = nil,
        width: CGFloat = 1300,
        height: CGFloat = 900
    ) -> (StoreOf<LibraryFeature>, MenuFocusHarness) {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = []
        }
        let store = Store(initialState: LibraryFeature.State(section: section)) {
            LibraryFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
            $0.psnTrophies = trophies
        }
        let harness = MenuFocusHarness(width: width, height: height) { _ in
            MenuFocusHostingView(rootView: StandInModalHost(modal: modal, content: LibraryView(store: store)
                    .transformEnvironment(\.screenLayout) { screen in
                        if let layout {
                            screen = layout
                        }
                    }
                    .environment(\.compactScreen, layout?.isCompact ?? compact)
                    .environment(\.quitControlShown, true)
                    .environment(\.requestQuit, RequestQuitAction { _ in
                        quits.withValue {
                            $0 += 1
                        }
                        modal.shown = true
                    })))
        }
        store.send(.trophies(.show(ProfileID(uuid: profileID))))
        return (store, harness)
    }

    @Test func theTrophiesListKeepsFocusAcrossTheQuitPromptInACompactWindow() async {
        let quits = LockIsolated(0)
        let modal = StandInModal()
        let (store, harness) = trophiesLibrary(quits: quits, modal: modal, compact: true)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
        await harness.pause(300)
        await harness.send(.back)
        await harness.pause(300)
        #expect(quits.value == 1)
        #expect(testNavigator.inputGate.isBlocking)
        await harness.send(.back)
        await harness.pause(300)
        #expect(!modal.shown)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == firstGame.id,
            "opened \(String(describing: store.trophies.opened?.title.id))"
        )
    }

    @Test func shouldersCycleTheTrophiesFilters() async {
        let quits = LockIsolated(0)
        let (store, harness) = trophiesLibrary(quits: quits)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
        await harness.pause(300)
        await harness.send(.next)
        await waitUntil(harness) {
            store.trophies.titleFilter == .inProgress
        }
        #expect(store.trophies.titleFilter == .inProgress)
        await harness.send([.previous, .previous])
        await waitUntil(harness) {
            store.trophies.titleFilter == .notStarted
        }
        #expect(store.trophies.titleFilter == .notStarted)
        await harness.send(.next)
        await waitUntil(harness) {
            store.trophies.titleFilter == .all
        }
        await harness.send([.down, .down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.shown.count == 2
        }
        await harness.send(.next)
        await waitUntil(harness) {
            store.trophies.trophyFilter == .earned
        }
        #expect(store.trophies.trophyFilter == .earned)
        #expect(store.trophies.titleFilter == .all)
    }

    @Test func theRailQuitStopKeepsFocusAfterTheQuitPromptOnTrophies() async {
        let quits = LockIsolated(0)
        let modal = StandInModal()
        let (store, harness) = trophiesLibrary(quits: quits, modal: modal)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        await harness.send(.focusToolbar)
        await waitUntil(harness) {
            store.heldFocus == .librarySection(.trophies)
        }
        for _ in 0 ..< 8 where store.heldFocus != .quit {
            await harness.send(.down)
            await harness.pause(80)
        }
        #expect(store.heldFocus == .quit)
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(modal.shown)
        await harness.send(.back)
        await harness.pause(300)
        #expect(!modal.shown)
        await harness.send(.up)
        await waitUntil(harness) {
            store.heldFocus == .profile
        }
        #expect(store.heldFocus == .profile)
    }

    @Test func openingAGameFocusesItsFirstTrophy() async {
        let quits = LockIsolated(0)
        let (store, harness) = trophiesLibrary(quits: quits)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
        await harness.pause(300)
        await harness.send([.down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.shown.count == 2
        }
        await harness.pause(300)
        await harness.send([.down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.revealed == [1]
        }
        #expect(store.trophies.opened?.revealed == [1])
    }

    @Test func squareJumpsToTheTrophiesFilters() async {
        let quits = LockIsolated(0)
        let (store, harness) = trophiesLibrary(quits: quits)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
        await harness.pause(300)
        await harness.send([.down, .alternate])
        await harness.pause(200)
        await harness.send([.right, .confirm])
        await waitUntil(harness) {
            store.trophies.titleFilter == .inProgress
        }
        #expect(store.trophies.titleFilter == .inProgress)
        await harness.send([.left, .confirm])
        await waitUntil(harness) {
            store.trophies.titleFilter == .all
        }
        await harness.send([.down, .down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.shown.count == 2
        }
        await harness.pause(300)
        await harness.send([.down, .alternate])
        await harness.pause(200)
        await harness.send([.right, .confirm])
        await waitUntil(harness) {
            store.trophies.trophyFilter == .earned
        }
        #expect(store.trophies.trophyFilter == .earned)
    }

    @Test func trophiesChosenInTheRailAreEnteredWithTheController() async {
        let quits = LockIsolated(0)
        let (store, harness) = trophiesLibrary(quits: quits, section: .consoles)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.send(.focusToolbar)
        await waitUntil(harness) {
            store.heldFocus == .librarySection(.consoles)
        }
        for _ in 0 ..< 4 where store.heldFocus != .librarySection(.trophies) {
            await harness.send(.down)
            await harness.pause(100)
        }
        #expect(store.heldFocus == .librarySection(.trophies))
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.section == .trophies && store.trophies.overview?.titles.count == 2
        }
        #expect(store.section == .trophies)
        await harness.pause(300)
        await harness.send(.down)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == secondGame.id,
            "opened \(String(describing: store.trophies.opened?.title.id)), held \(String(describing: store.heldFocus))"
        )
    }

    @Test func trophiesAreEnteredFromTheRailOpenedAndClosedWithTheController() async {
        let quits = LockIsolated(0)
        let (store, harness) = trophiesLibrary(quits: quits)
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        await harness.send(.focusToolbar)
        await waitUntil(harness) {
            store.heldFocus == .librarySection(.trophies)
        }
        #expect(store.heldFocus == .librarySection(.trophies))
        await harness.send(.right)
        await harness.pause(200)
        await harness.send(.down)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened?.title.id == secondGame.id
        }
        #expect(
            store.trophies.opened?.title.id == secondGame.id,
            "opened \(String(describing: store.trophies.opened?.title.id))"
        )
        await waitUntil(harness) {
            store.trophies.opened?.shown.count == 2
        }
        await harness.send([.down, .down, .down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.revealed == [1]
        }
        #expect(store.trophies.opened?.revealed == [1])
        await harness.send(.back)
        await waitUntil(harness) {
            store.trophies.opened == nil
        }
        #expect(store.trophies.opened == nil)
        await harness.pause(200)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == secondGame.id,
            "opened \(String(describing: store.trophies.opened?.title.id))"
        )
        await harness.send(.back)
        await waitUntil(harness) {
            store.trophies.opened == nil
        }
        await harness.pause(200)
        await harness.send(.back)
        await waitUntil(harness) {
            store.heldFocus == .librarySection(.trophies)
        }
        #expect(store.heldFocus == .librarySection(.trophies))
        #expect(quits.value == 0)
    }

    @Test func trophiesEnteredWhileLoadingMoveToTheFirstGameOnceItArrives() async {
        let released = LockIsolated(false)
        let (store, harness) = trophiesLibrary(
            quits: LockIsolated(0),
            trophies: slowTrophies(released: released)
        )
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(500)
        await harness.send(.focusToolbar)
        await waitUntil(harness) {
            store.heldFocus == .librarySection(.trophies)
        }
        await harness.send(.right)
        await harness.pause(300)
        released.setValue(true)
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        await harness.pause(300)
        await harness.send(.down)
        await harness.pause(200)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == secondGame.id,
            "opened \(String(describing: store.trophies.opened?.title.id))"
        )
    }

    @Test func trophiesAreFilteredAndSortedWithTheController() async {
        let (store, harness) = trophiesLibrary(quits: LockIsolated(0))
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        await harness.send(.focusToolbar)
        await harness.send(.right)
        await harness.pause(200)
        await harness.send([.up, .right, .right, .confirm])
        await waitUntil(harness) {
            store.trophies.titleFilter == .completed
        }
        #expect(store.trophies.titleFilter == .completed)
        await harness.send([.left, .left, .confirm])
        await waitUntil(harness) {
            store.trophies.titleFilter == .all
        }
        await harness.send([.down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.title.id == firstGame.id
        }
        await waitUntil(harness) {
            store.trophies.opened?.shown.count == 2
        }
        await harness.pause(200)
        await harness.send([.up, .right, .confirm])
        await waitUntil(harness) {
            store.trophies.trophyFilter == .earned
        }
        #expect(store.trophies.trophyFilter == .earned)
        #expect(store.trophies.shownTrophies.map(\.id) == [0])
        await harness.send([.right, .right, .right, .confirm])
        await waitUntil(harness) {
            store.trophies.trophySort == .grade
        }
        #expect(store.trophies.trophySort == .grade)
        await harness.send(.back)
        await waitUntil(harness) {
            store.trophies.opened == nil
        }
        #expect(store.trophies.opened == nil)
    }

    @Test func leftFromATrophiesRowReturnsToTheRail() async {
        let (store, harness) = trophiesLibrary(quits: LockIsolated(0))
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        await harness.send(.focusToolbar)
        await harness.send(.right)
        await harness.pause(200)
        await harness.send(.down)
        await harness.send(.left)
        await waitUntil(harness) {
            store.heldFocus == .librarySection(.trophies)
        }
        #expect(store.heldFocus == .librarySection(.trophies))
        await harness.send(.right)
        await harness.pause(200)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == secondGame.id,
            "opened \(String(describing: store.trophies.opened?.title.id))"
        )
    }

    @Test func aLongTrophiesListIsWalkedPastItsFirstScreenWithTheController() async {
        let (store, harness) = trophiesLibrary(quits: LockIsolated(0), trophies: manyTrophies())
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == manyGames.count
        }
        await harness.send(.focusToolbar)
        await harness.send(.right)
        await harness.pause(200)
        await harness.send(Array(repeating: .down, count: 30))
        await harness.pause(200)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == manyGames[30].id,
            "opened \(String(describing: store.trophies.opened?.title.id))"
        )
        await waitUntil(harness) {
            store.trophies.opened?.shown.count == 80
        }
        await harness.send(Array(repeating: .down, count: 40))
        await harness.pause(200)
        await harness.send(.confirm)
        await harness.pause(200)
        await harness.send(.back)
        await waitUntil(harness) {
            store.trophies.opened == nil
        }
        await harness.pause(300)
        await harness.send(.down)
        await harness.pause(200)
        await harness.send(.confirm)
        await waitUntil(harness) {
            store.trophies.opened != nil
        }
        #expect(
            store.trophies.opened?.title.id == manyGames[31].id,
            "reopened \(String(describing: store.trophies.opened?.title.id))"
        )
    }
}

extension MenuFocusTests {
    @Test func aCompactTrophiesRowWalksToSearchWhichOpensAndClosesThePopUp() async {
        let (store, harness) = trophiesLibrary(
            quits: LockIsolated(0),
            layout: ScreenLayout(room: .compact, stature: .tall, touch: true),
            width: 393,
            height: 852
        )
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
        await harness.pause(300)
        await harness.send(.alternate)
        await harness.pause(100)
        await harness.send([.right, .right, .confirm])
        await waitUntil(harness) {
            store.trophies.isSearching
        }
        #expect(store.trophies.isSearching)
        await harness.send(.back)
        await waitUntil(harness) {
            !store.trophies.isSearching
        }
        #expect(!store.trophies.isSearching)
        await harness.pause(100)
        await harness.send([.down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.title.id == firstGame.id
        }
        #expect(store.trophies.opened?.title.id == firstGame.id)
    }

    @Test func aCompactShowDropdownFollowsTheFilterTheShouldersChoose() async {
        let (store, harness) = trophiesLibrary(
            quits: LockIsolated(0),
            layout: ScreenLayout(room: .compact, stature: .tall, touch: true),
            width: 393,
            height: 852
        )
        defer {
            harness.close()
        }
        await harness.open()
        await waitUntil(harness) {
            store.trophies.overview?.titles.count == 2
        }
        store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
        await harness.pause(300)
        await harness.send(.next)
        await waitUntil(harness) {
            store.trophies.titleFilter == .inProgress
        }
        #expect(store.trophies.titleFilter == .inProgress)
        await harness.send([.right, .right, .confirm])
        await waitUntil(harness) {
            store.trophies.isSearching
        }
        #expect(store.trophies.isSearching)
        await harness.send(.back)
        await waitUntil(harness) {
            !store.trophies.isSearching
        }
        await harness.pause(100)
        await harness.send([.left, .left, .left, .down, .confirm])
        await waitUntil(harness) {
            store.trophies.opened?.title.id == firstGame.id
        }
        #expect(store.trophies.opened?.title.id == firstGame.id)
    }
}
