import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let player = ProfileID(uuid: UUID(7))
private let game = TrophyTitle(
    id: "NPWR07028_00",
    name: "UNCHARTED 4",
    earned: TrophyCounts(bronze: 1),
    progress: 2
)

private func current(earned: Bool) -> CurrentTrophies {
    CurrentTrophies(title: game, trophies: TitleTrophies(groups: [], trophies: [
        PSNTrophy(id: 0, grade: .bronze, name: "Start", earned: true),
        PSNTrophy(id: 7, grade: .bronze, name: "First Treasure", earned: earned)
    ]))
}

@MainActor private func panel(
    asked: LockIsolated<[String]>,
    answers: LockIsolated<[CurrentTrophies?]>,
    now: LockIsolated<Date>,
    clock: TestClock<Duration> = TestClock(),
    failing: Set<String> = []
) -> TestStoreOf<StreamTrophiesFeature> {
    TestStore(initialState: StreamTrophiesFeature.State(
        profile: player,
        titleIDs: ["CUSA00341_00", "PPSA01234_00"]
    )) {
        StreamTrophiesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.date = DateGenerator {
            now.value
        }
        $0.continuousClock = clock
        $0.psnTrophies = PSNTrophiesClient(
            summary: { _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            titles: { _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            trophies: { _, _ throws(PSNTrophiesFailure) in
                throw .unavailable
            },
            current: { _, titleID throws(PSNTrophiesFailure) in
                asked.withValue {
                    $0.append(titleID)
                }
                if failing.contains(titleID) {
                    throw .unavailable
                }
                return answers.withValue {
                    $0.isEmpty
                        ? nil
                        : $0.removeFirst()
                }
            }
        )
    }
}

@MainActor @Test func showingThePanelReadsTheGamesTrophiesAtMostOnceAMinute() async {
    let asked = LockIsolated<[String]>([])
    let answers = LockIsolated<[CurrentTrophies?]>([current(earned: false)])
    let now = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = panel(asked: asked, answers: answers, now: now)
    await store.send(.appeared) {
        $0.listing = .loading(UUID(0), kept: nil)
    }
    await store.receive(.loaded(UUID(0), .success(current(earned: false)))) {
        $0.listing = .loaded(current(earned: false))
        $0.readAt = Date(timeIntervalSince1970: 1000)
    }
    #expect(asked.value == ["CUSA00341_00"])
    now.setValue(Date(timeIntervalSince1970: 1030))
    await store.send(.appeared)
    now.setValue(Date(timeIntervalSince1970: 1061))
    answers.setValue([current(earned: true)])
    await store.send(.appeared) {
        $0.listing = .loading(UUID(1), kept: current(earned: false))
    }
    await store.receive(.loaded(UUID(1), .success(current(earned: true)))) {
        $0.listing = .loaded(current(earned: true))
        $0.readAt = Date(timeIntervalSince1970: 1061)
    }
}

@MainActor @Test func anEarnedTrophyReadsAgainOncePsnHasItAndRefreshReadsAtOnce() async {
    let asked = LockIsolated<[String]>([])
    let answers = LockIsolated<[CurrentTrophies?]>([current(earned: false), current(earned: true)])
    let now = LockIsolated(Date(timeIntervalSince1970: 1000))
    let clock = TestClock()
    let store = panel(asked: asked, answers: answers, now: now, clock: clock)
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.receive(\.loaded)
    await store.send(.earned)
    #expect(asked.value.count == 1)
    await clock.advance(by: StreamTrophiesFeature.earnedDelay)
    await store.receive(\.earnedSettled)
    await store.receive(\.loaded)
    #expect(store.state.current == current(earned: true))
    answers.setValue([current(earned: false)])
    await store.send(.refresh)
    await store.receive(\.loaded)
    #expect(asked.value.count == 3)
}

@MainActor @Test func showingThePanelAfterAnEarnedTrophyReadsWhateverTheGap() async {
    let asked = LockIsolated<[String]>([])
    let answers = LockIsolated<[CurrentTrophies?]>([current(earned: false), current(earned: true)])
    let now = LockIsolated(Date(timeIntervalSince1970: 1000))
    let clock = TestClock()
    let store = panel(asked: asked, answers: answers, now: now, clock: clock)
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.receive(\.loaded)
    await store.send(.earned)
    now.setValue(Date(timeIntervalSince1970: 1005))
    await store.send(.appeared)
    await store.receive(\.loaded)
    #expect(asked.value.count == 2)
    #expect(store.state.earnedSinceRead == false)
    await clock.advance(by: StreamTrophiesFeature.earnedDelay)
    await store.receive(\.earnedSettled)
    await store.skipReceivedActions()
}

@MainActor @Test func aFailedReleaseFallsBackToTheOtherVersion() async {
    let asked = LockIsolated<[String]>([])
    let answers = LockIsolated<[CurrentTrophies?]>([current(earned: true)])
    let now = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = panel(asked: asked, answers: answers, now: now, failing: ["CUSA00341_00"])
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.receive(\.loaded)
    #expect(asked.value == ["CUSA00341_00", "PPSA01234_00"])
    #expect(store.state.current == current(earned: true))
}

@MainActor @Test func aGameWithoutASetOnItsReleaseFallsBackToTheOtherVersion() async {
    let asked = LockIsolated<[String]>([])
    let answers = LockIsolated<[CurrentTrophies?]>([nil, current(earned: true)])
    let now = LockIsolated(Date(timeIntervalSince1970: 1000))
    let store = panel(asked: asked, answers: answers, now: now)
    store.exhaustivity = .off
    await store.send(.appeared)
    await store.receive(\.loaded)
    #expect(asked.value == ["CUSA00341_00", "PPSA01234_00"])
    #expect(store.state.current == current(earned: true))
}

@MainActor @Test func theChoicesFilterSortAndRevealTheShownTrophies() async {
    var initial = StreamTrophiesFeature.State(profile: player, titleIDs: ["CUSA00341_00"])
    initial.listing = .loaded(current(earned: false))
    let store = TestStore(initialState: initial) {
        StreamTrophiesFeature()
    }
    await store.send(.filterChosen(.unearned)) {
        $0.filter = .unearned
    }
    #expect(store.state.shown.map(\.id) == [7])
    await store.send(.filterChosen(.all)) {
        $0.filter = .all
    }
    await store.send(.sortChosen(.name)) {
        $0.sort = .name
    }
    #expect(store.state.shown.map(\.id) == [7, 0])
    await store.send(.reverseToggled) {
        $0.direction = .reversed
    }
    #expect(store.state.shown.map(\.id) == [0, 7])
    await store.send(.sortChosen(.game)) {
        $0.sort = .game
    }
    #expect(store.state.direction == .reversed)
    await store.send(.reverseToggled) {
        $0.direction = .standard
    }
    await store.send(.revealToggled(7)) {
        $0.revealed = [7]
    }
    await store.send(.revealToggled(7)) {
        $0.revealed = []
    }
}

@MainActor @Test func anAnswerAfterTheStreamEndedIsDropped() async {
    var initial = StreamTrophiesFeature.State(profile: player, titleIDs: ["CUSA00341_00"])
    initial.listing = .loading(UUID(3), kept: current(earned: false))
    let store = TestStore(initialState: initial) {
        StreamTrophiesFeature()
    }
    await store.send(.streamEnded) {
        $0.listing = .loaded(current(earned: false))
    }
    await store.send(.loaded(UUID(3), .success(current(earned: true))))
}

@Test func theTitleIdIsReadFromTheStoreProductId() {
    let read: (String) -> String? = { text in
        ProductID(rawValue: text).flatMap(StreamFeature.titleID(of:))
    }
    #expect(read("UP9000-CUSA00341_00-UNCHARTED0000000") == "CUSA00341_00")
    #expect(read("EP9000-PPSA01234_00-GAME000000000000") == "PPSA01234_00")
    #expect(read("UP9000-NOTATITLE-X") == nil)
    #expect(read("plain") == nil)
}

@Test func theStreamTrophiesPanelShowsThePageThatHoldsFocus() {
    let trophies = (0 ..< 14).map {
        PSNTrophy(id: $0, grade: .bronze, name: "Trophy \($0)")
    }
    let page = { (anchor: StreamMenuControl?) in
        StreamMenuTrophiesControls.page(of: StreamTrophiesPaging(anchor: anchor, rows: 6), in: trophies)
    }
    #expect(page(nil) == 0 ..< 6)
    #expect(page(.trophiesSort) == 0 ..< 6)
    #expect(page(.trophy(5)) == 0 ..< 6)
    #expect(page(.trophy(6)) == 6 ..< 12)
    #expect(page(.trophy(13)) == 12 ..< 14)
    #expect(StreamMenuTrophiesControls.page(
        of: StreamTrophiesPaging(anchor: .trophy(3), rows: 4),
        in: trophies
    )
        == 0 ..< 4)
    #expect(StreamMenuTrophiesControls.page(of: StreamTrophiesPaging(), in: []) == 0 ..< 0)
}
