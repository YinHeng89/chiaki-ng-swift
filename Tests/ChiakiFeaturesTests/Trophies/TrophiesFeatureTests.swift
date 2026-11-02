import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let player = ProfileID(uuid: UUID(7))
private let other = ProfileID(uuid: UUID(8))
private let summary = TrophySummary(level: 312, tier: 4, progress: 40, earned: TrophyCounts(bronze: 9))
private let title = TrophyTitle(id: "NPWR00001_00", name: "Astro", progress: 50)

private func trophies() -> TitleTrophies {
    TitleTrophies(
        groups: [TrophyGroup(id: "default", name: "Astro"), TrophyGroup(id: "001", name: "Extra")],
        trophies: [
            PSNTrophy(id: 0, grade: .platinum, name: "All"),
            PSNTrophy(id: 1, group: "001", grade: .gold, name: "Extra", hidden: true)
        ]
    )
}

@MainActor @Test func showingTheSectionReadsTheOverview() async {
    let store = TestStore(initialState: TrophiesFeature.State()) {
        TrophiesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnTrophies = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                summary
            },
            titles: { _ throws(PSNTrophiesFailure) in
                [title]
            },
            trophies: { _, _ throws(PSNTrophiesFailure) in
                trophies()
            }
        )
    }
    await store.send(.show(player)) {
        $0.profile = player
        $0.listing = .loading(UUID(0), kept: nil)
    }
    await store.receive(.overviewLoaded(UUID(0), .success(.init(summary: summary, titles: [title])))) {
        $0.listing = .loaded(.init(summary: summary, titles: [title]))
    }
}

@MainActor @Test func aMissingSummaryStillListsTheGames() async {
    let store = TestStore(initialState: TrophiesFeature.State()) {
        TrophiesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnTrophies = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            titles: { _ throws(PSNTrophiesFailure) in
                [title]
            },
            trophies: { _, _ throws(PSNTrophiesFailure) in
                trophies()
            }
        )
    }
    store.exhaustivity = .off
    await store.send(.show(player))
    await store.receive(\.overviewLoaded)
    #expect(store.state.overview == .init(summary: nil, titles: [title]))
}

@MainActor @Test func anAnswerForAnotherAccountIsDropped() async {
    let store = TestStore(initialState: TrophiesFeature.State()) {
        TrophiesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnTrophies = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                try? await Task.never()
                throw .cancelled
            },
            titles: { _ throws(PSNTrophiesFailure) in
                [title]
            },
            trophies: { _, _ throws(PSNTrophiesFailure) in
                trophies()
            }
        )
    }
    store.exhaustivity = .off
    await store.send(.show(player))
    await store.send(.show(other))
    await store.send(.overviewLoaded(UUID(0), .success(.init(summary: nil, titles: [title]))))
    #expect(store.state.listing == .loading(UUID(1), kept: nil))
    await store.send(.show(nil))
    #expect(store.state.profile == nil)
    #expect(store.state.listing == .idle)
}

@MainActor @Test func anOpenedGameReadsItsTrophiesAndIgnoresAnEarlierGame() async {
    var initial = TrophiesFeature.State()
    initial.profile = player
    initial.listing = .loaded(.init(summary: nil, titles: [title]))
    let store = TestStore(initialState: initial) {
        TrophiesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnTrophies = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                summary
            },
            titles: { _ throws(PSNTrophiesFailure) in
                [title]
            },
            trophies: { _, id throws(PSNTrophiesFailure) in
                #expect(id == title.id)
                return trophies()
            }
        )
    }
    await store.send(.open(title.id)) {
        $0.opened = TrophiesFeature.Opened(title: title, listing: .loading(UUID(0)))
    }
    await store.receive(.titleLoaded(UUID(0), .success(trophies()))) {
        $0.opened?.listing = .loaded(trophies())
    }
    #expect(store.state.opened?.groups.count == 2)
    await store.send(.groupSelected("001")) {
        $0.opened?.group = "001"
    }
    #expect(store.state.opened?.shown.map(\.id) == [1])
    await store.send(.revealToggled(1)) {
        $0.opened?.revealed = [1]
    }
    await store.send(.titleLoaded(UUID(9), .failure(.unavailable)))
    await store.send(.close) {
        $0.opened = nil
    }
}

@MainActor @Test func refreshStartsOverAndReadsAgain() async {
    let startedOver = LockIsolated<[ProfileID]>([])
    var initial = TrophiesFeature.State()
    initial.profile = player
    initial.listing = .loaded(.init(summary: nil, titles: [title]))
    initial.opened = TrophiesFeature.Opened(title: title, listing: .loaded(trophies()))
    let store = TestStore(initialState: initial) {
        TrophiesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.psnTrophies = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                summary
            },
            titles: { _ throws(PSNTrophiesFailure) in
                [title]
            },
            trophies: { _, _ throws(PSNTrophiesFailure) in
                trophies()
            },
            startOver: { profile in
                startedOver.withValue {
                    $0.append(profile)
                }
            }
        )
    }
    store.exhaustivity = .off
    await store.send(.refresh)
    #expect(store.state.opened == nil)
    await store.receive(\.overviewLoaded)
    #expect(startedOver.value == [player])
    #expect(store.state.overview?.summary == summary)
}

@MainActor @Test func leavingTheContentIsReportedToTheLibrary() async {
    let store = TestStore(initialState: TrophiesFeature.State()) {
        TrophiesFeature()
    }
    await store.send(.leaveContent(.left))
    await store.receive(.delegate(.leftContent(.left)))
    await store.send(.backToRail)
    await store.receive(.delegate(.backToRail))
}

@MainActor @Test func choosingTheSortInEffectReversesIt() async {
    let done = TrophyTitle(id: "NPWR00002_00", name: "Bloodborne", progress: 100)
    let fresh = TrophyTitle(id: "NPWR00003_00", name: "Concrete Genie", progress: 0)
    var initial = TrophiesFeature.State()
    initial.profile = player
    initial.listing = .loaded(.init(summary: nil, titles: [title, done, fresh]))
    initial.titleSort = .progress
    let store = TestStore(initialState: initial) {
        TrophiesFeature()
    }
    #expect(store.state.shownTitles.map(\.id) == [done.id, title.id, fresh.id])
    await store.send(.titleSortChosen(.progress)) {
        $0.titleSortDirection = .reversed
    }
    #expect(store.state.shownTitles.map(\.id) == [fresh.id, title.id, done.id])
    await store.send(.titleSortChosen(.progress)) {
        $0.titleSortDirection = .standard
    }
    await store.send(.titleSortChosen(.progress)) {
        $0.titleSortDirection = .reversed
    }
    await store.send(.titleSortChosen(.name)) {
        $0.titleSort = .name
        $0.titleSortDirection = .standard
    }
    await store.send(.trophySortChosen(.game)) {
        $0.trophySortDirection = .reversed
    }
    await store.send(.trophySortChosen(.grade)) {
        $0.trophySort = .grade
        $0.trophySortDirection = .standard
    }
}

@MainActor @Test func theChoicesFilterSortAndSearchWhatIsShown() async {
    let done = TrophyTitle(
        id: "NPWR00002_00",
        name: "Bloodborne",
        earned: TrophyCounts(gold: 3),
        progress: 100
    )
    let fresh = TrophyTitle(id: "NPWR00003_00", name: "Concrete Genie", progress: 0)
    var initial = TrophiesFeature.State()
    initial.profile = player
    initial.listing = .loaded(.init(summary: nil, titles: [title, done, fresh]))
    initial.opened = TrophiesFeature.Opened(title: title, listing: .loaded(TitleTrophies(
        groups: [],
        trophies: [
            PSNTrophy(id: 0, grade: .bronze, name: "Start", earned: true),
            PSNTrophy(id: 1, grade: .platinum, name: "All")
        ]
    )))
    let store = TestStore(initialState: initial) {
        TrophiesFeature()
    }
    #expect(store.state.shownTitles.map(\.id) == [title.id, done.id, fresh.id])
    await store.send(.titleSortChosen(.progress)) {
        $0.titleSort = .progress
    }
    #expect(store.state.shownTitles.map(\.id) == [done.id, title.id, fresh.id])
    await store.send(.titleFilterChosen(.notStarted)) {
        $0.titleFilter = .notStarted
    }
    #expect(store.state.shownTitles.map(\.id) == [fresh.id])
    await store.send(.titleFilterChosen(.all)) {
        $0.titleFilter = .all
    }
    await store.send(.queryChanged("blood")) {
        $0.query = "blood"
    }
    #expect(store.state.shownTitles.map(\.id) == [done.id])
    await store.send(.trophySortChosen(.grade)) {
        $0.trophySort = .grade
    }
    #expect(store.state.shownTrophies.map(\.id) == [1, 0])
    await store.send(.trophyFilterChosen(.earned)) {
        $0.trophyFilter = .earned
    }
    #expect(store.state.shownTrophies.map(\.id) == [0])
}
