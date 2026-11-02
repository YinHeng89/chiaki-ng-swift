import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures
@testable import ChiakiClientsLive
@testable import ChiakiNG
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

private func catalog(_ count: Int) -> CloudLibrarySnapshot {
    let platforms = ["PS5", "PS4", "PS3"]
    return CloudLibrarySnapshot(settledLocale: "en-GB", games: (0..<count).map { index in
        CloudGame(
            productId: "game-\(index)", name: "Game \(index)", imageUrl: "https://image.example/\(index).png",
            platform: platforms[index % 3], isOwned: index % 2 == 0, plusCatalog: index % 3 == 0
        )
    })
}

private func ready(_ count: Int, shape: CloudGridShape = CloudGridShape(columns: 7, rows: 2))
    -> CloudLibraryFeature.State {
    var state = CloudLibraryFeature.State()
    state.accountID = UUID()
    state.phase = .ready
    state.snapshot = catalog(count)
    state.gridShape = shape
    state.listing.resize(to: shape.size, keeping: nil)
    return state
}

@MainActor private func library(_ state: CloudLibraryFeature.State) -> TestStoreOf<CloudLibraryFeature> {
    let store = TestStore(initialState: state) {
        CloudLibraryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.locale = Locale(identifier: "en_GB")
        $0.catalog.gameDetails = { _, _ in .success(GameDetails()) }
        $0.catalog.artLayers = { _ in nil }
        $0.catalog.heldArtLayers = { _ in nil }
    }
    store.exhaustivity = .off
    return store
}

private func ids(_ range: Range<Int>) -> [String] {
    range.map { "game-\($0)" }
}

private func covers(_ games: [CloudGame]) -> [URL] {
    games.compactMap { URL.secureArtwork($0.imageUrl) }
}

private final class Fetched: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []

    func note(_ url: URL) {
        lock.withLock {
            urls.append(url.absoluteString)
        }
    }

    var all: [String] {
        lock.withLock {
            urls.sorted()
        }
    }
}

@Test func thePageHoldsAsManyCardsAsTheWindowFits() {
    let mock = CloudGridMetrics.fit(CGSize(width: 1632, height: 792))
    #expect(mock.shape == CloudGridShape(columns: 7, rows: 2))
    #expect(mock.cardWidth == 216)
    #expect(mock.contentSize.width == 1632)
    #expect(mock.contentSize.height <= 792)
    let small = CloudGridMetrics.fit(CGSize(width: 820, height: 420))
    #expect(small.shape == CloudGridShape(columns: 3, rows: 1))
    #expect(small.contentSize.height <= 420 && small.contentSize.height > 380)
    let wideRow = CloudGridMetrics.fit(CGSize(width: 1350, height: 470))
    #expect(wideRow.shape == CloudGridShape(columns: 4, rows: 1))
    #expect(wideRow.cardWidth > 300 && wideRow.contentSize.height <= 470)
    #expect(wideRow.columnGap <= CloudGridMetrics.widestGap)
    #expect(abs(wideRow.contentSize.width - 1350) < 1)
    let tall = CloudGridMetrics.fit(CGSize(width: 1000, height: 1300))
    #expect(tall.shape.rows == 3 && tall.shape.columns == 4)
    let nearlyTwo = CloudGridMetrics.fit(CGSize(width: 1500, height: 660))
    #expect(nearlyTwo.shape.rows == 2)
    #expect(nearlyTwo.cardWidth >= CloudGridMetrics.tightestCard)
    #expect(nearlyTwo.contentSize.height <= 660 && nearlyTwo.contentSize.width <= 1500)
    let squat = CloudGridMetrics.fit(CGSize(width: 1000, height: 240))
    #expect(squat.shape.rows == 1 && squat.cardHeight <= 240)
    #expect(squat.shape.columns > 4)
    #expect(CloudGridMetrics.fit(.zero).shape == .unmeasured)
    #expect(CloudGridShape(columns: 0, rows: -3).size == 1)
}

@MainActor @Test func pagesAreSlicesOfTheMatchingGames() async {
    let store = library(ready(31))
    #expect(store.state.pageCount == 3)
    #expect(store.state.visibleGameIDs == ids(0..<14))
    #expect(store.state.upcomingGames.map(\.id) == ids(14..<28))
    await store.send(.turnPage(-1))
    #expect(store.state.page == 0)
    await store.send(.turnPage(1))
    #expect(store.state.page == 1 && store.state.pageTurn == .forward)
    #expect(store.state.visibleGameIDs == ids(14..<28))
    #expect(store.state.upcomingGames.map(\.id) == ids(28..<31))
    await store.send(.turnPage(1))
    #expect(store.state.visibleGameIDs == ids(28..<31))
    #expect(store.state.upcomingGames.isEmpty)
    await store.send(.turnPage(1))
    #expect(store.state.page == 2)
    await store.send(.turnPage(-1))
    #expect(store.state.page == 1 && store.state.pageTurn == .backward)
    await store.send(.showPage(99))
    #expect(store.state.page == 2)
    await store.send(.showPage(-4))
    #expect(store.state.page == 0)
    #expect(ready(0).pageCount == 1)
    #expect(ready(14).pageCount == 1)
    #expect(ready(15).pageCount == 2)
}

@MainActor @Test func theFirstPageReturnsWhenTheQueryTabOrPlatformChanges() async {
    let store = library(ready(200))
    await store.send(.showPage(5))
    await store.send(.binding(.set(\.query, "Game 1")))
    #expect(store.state.page == 0)
    await store.send(.binding(.set(\.query, "")))
    await store.send(.showPage(5))
    await store.send(.filter(.owned))
    #expect(store.state.page == 0)
    await store.send(.showPage(3))
    await store.send(.platform(.ps4))
    #expect(store.state.page == 0)
    await store.send(.platform(.all))
    await store.send(.filter(.all))
    await store.send(.showPage(4))
    await store.send(.select("game-60"))
    await store.send(.select(nil))
    await store.skipReceivedActions(strict: false)
    #expect(store.state.page == 4)
    await store.send(.account(UUID()))
    #expect(store.state.gridShape == CloudGridShape(columns: 7, rows: 2))
    #expect(store.state.listing.pageSize == 14)
}

@MainActor @Test func aPageSizeChangeKeepsTheChosenGameOnScreen() async {
    let store = library(ready(200))
    await store.send(.showPage(5))
    #expect(store.state.visibleGameIDs.contains("game-75"))
    await store.send(.gridShape(CloudGridShape(columns: 5, rows: 2), keeping: "game-75"))
    #expect(store.state.listing.pageSize == 10)
    #expect(store.state.page == 7)
    #expect(store.state.visibleGameIDs.contains("game-75"))
    await store.send(.select("game-33"))
    await store.send(.gridShape(CloudGridShape(columns: 4, rows: 1), keeping: nil))
    #expect(store.state.visibleGameIDs.contains("game-33"))
    await store.send(.select(nil))
    await store.send(.showPage(2))
    let first = store.state.visibleGameIDs[0]
    await store.send(.gridShape(CloudGridShape(columns: 3, rows: 3), keeping: nil))
    #expect(store.state.visibleGameIDs.contains(first))
    let pages = store.state.listing.derivations.pages
    await store.send(.gridShape(CloudGridShape(columns: 3, rows: 3), keeping: "game-1"))
    #expect(store.state.listing.derivations.pages == pages)
}

@Test func movingPastThePageEdgeTurnsThePageInTheSameRow() {
    let shape = CloudGridShape(columns: 7, rows: 2)
    let middle = CloudGridNavigation(shape: shape, count: 14, page: 1, pageCount: 3)
    #expect(middle.stop(from: 3, .right) == .card(4))
    #expect(middle.stop(from: 3, .left) == .card(2))
    #expect(middle.stop(from: 6, .right) == .turn(forward: true, row: 0))
    #expect(middle.stop(from: 13, .right) == .turn(forward: true, row: 1))
    #expect(middle.stop(from: 7, .left) == .turn(forward: false, row: 1))
    #expect(middle.stop(from: 0, .left) == .turn(forward: false, row: 0))
    #expect(middle.stop(from: 2, .up) == .header)
    #expect(middle.stop(from: 9, .up) == .card(2))
    #expect(middle.stop(from: 2, .down) == .card(9))
    #expect(middle.stop(from: 9, .down) == .pageBar)
    #expect(middle.stop(from: 14, .down) == .stay)
    let first = CloudGridNavigation(shape: shape, count: 14, page: 0, pageCount: 3)
    #expect(first.stop(from: 7, .left) == .edge(.left))
    #expect(first.stop(from: 0, .left) == .edge(.left))
    let last = CloudGridNavigation(shape: shape, count: 10, page: 2, pageCount: 3)
    #expect(last.stop(from: 6, .right) == .edge(.right))
    #expect(last.stop(from: 9, .right) == .edge(.right))
    #expect(last.stop(from: 1, .down) == .card(8))
    #expect(last.stop(from: 5, .down) == .card(9))
    #expect(last.stop(from: 8, .down) == .pageBar)
    let only = CloudGridNavigation(shape: shape, count: 5, page: 0, pageCount: 1)
    #expect(only.stop(from: 2, .down) == .edge(.down))
    #expect(only.stop(from: 4, .right) == .edge(.right))
    #expect(CloudGridNavigation.landing(row: 1, forward: true, shape: shape, count: 14) == 7)
    #expect(CloudGridNavigation.landing(row: 1, forward: false, shape: shape, count: 14) == 13)
    #expect(CloudGridNavigation.landing(row: 0, forward: true, shape: shape, count: 3) == 0)
    #expect(CloudGridNavigation.landing(row: 1, forward: true, shape: shape, count: 3) == 0)
    #expect(CloudGridNavigation.landing(row: 1, forward: true, shape: shape, count: 10) == 7)
    #expect(CloudGridNavigation.landing(row: 1, forward: false, shape: shape, count: 10) == 9)
    #expect(CloudGridNavigation.landing(row: 0, forward: true, shape: shape, count: 0) == nil)
}

@Test func theDotWindowFollowsThePageAndTapersTowardsHiddenPages() {
    func sizes(_ page: Int, _ count: Int) -> [CloudPageDot.Size] {
        CloudPageDots.dots(page: page, count: count).map(\.size)
    }
    func pages(_ page: Int, _ count: Int) -> [Int] {
        CloudPageDots.dots(page: page, count: count).map(\.page)
    }
    #expect(CloudPageDots.dots(page: 0, count: 1).isEmpty)
    #expect(CloudPageDots.dots(page: 0, count: 0).isEmpty)
    #expect(sizes(147, 362) == [.edge, .far, .near, .now, .near, .far, .edge])
    #expect(pages(147, 362) == Array(144...150))
    #expect(sizes(0, 362) == [.now, .full, .full, .full, .near, .far, .edge])
    #expect(pages(0, 362) == Array(0...6))
    #expect(sizes(1, 362) == [.full, .now, .full, .full, .near, .far, .edge])
    #expect(sizes(3, 362) == [.full, .full, .full, .now, .near, .far, .edge])
    #expect(sizes(4, 362) == [.edge, .far, .near, .now, .near, .far, .edge])
    #expect(sizes(361, 362) == [.edge, .far, .near, .full, .full, .full, .now])
    #expect(pages(361, 362) == Array(355...361))
    #expect(sizes(359, 362) == [.edge, .far, .near, .full, .now, .full, .full])
    #expect(sizes(2, 4) == [.full, .full, .now, .full])
    #expect(pages(2, 4) == [0, 1, 2, 3])
    #expect(sizes(6, 7) == [.full, .full, .full, .full, .full, .full, .now])
    #expect(pages(99, 4) == [0, 1, 2, 3])
    #expect(sizes(99, 4).last == .now)
}

@Test func aTypedPageJumpsClampsOrIsIgnored() {
    #expect(CloudPageJump.page(typed: "12", count: 362) == 11)
    #expect(CloudPageJump.page(typed: " 1 ", count: 362) == 0)
    #expect(CloudPageJump.page(typed: "362", count: 362) == 361)
    #expect(CloudPageJump.page(typed: "9999", count: 362) == 361)
    #expect(CloudPageJump.page(typed: "99999999999999999999999", count: 362) == 361)
    #expect(CloudPageJump.page(typed: "0", count: 362) == 0)
    #expect(CloudPageJump.page(typed: "-3", count: 362) == 0)
    #expect(CloudPageJump.page(typed: "", count: 362) == nil)
    #expect(CloudPageJump.page(typed: "abc", count: 362) == nil)
    #expect(CloudPageJump.page(typed: "12a", count: 362) == nil)
    #expect(CloudPageJump.page(typed: "1.5", count: 362) == nil)
}

@Test func thePageControlOpensWhileAttendedAndFoldsBackAfterwards() {
    var control = CloudPageControl()
    #expect(control.phase == .resting && !control.isOpen)
    #expect(control.handle(.pointer(true), pageCount: 9) == nil)
    #expect(control.phase == .open)
    #expect(control.handle(.focus(true), pageCount: 9) == nil)
    #expect(control.handle(.pointer(false), pageCount: 9) == nil)
    #expect(control.phase == .open)
    #expect(control.handle(.focus(false), pageCount: 9) == nil)
    #expect(control.phase == .resting)
    #expect(control.handle(.dragged(40), pageCount: 9) == nil)
    #expect(control.phase == .dragging(8))
    #expect(control.shownPage(current: 2) == 8)
    #expect(control.handle(.dragged(5), pageCount: 9) == nil)
    #expect(control.handle(.pointer(true), pageCount: 9) == nil)
    #expect(control.phase == .dragging(5))
    #expect(control.handle(.released, pageCount: 9) == 5)
    #expect(control.phase == .open)
    #expect(control.handle(.released, pageCount: 9) == nil)
    #expect(control.handle(.pointer(false), pageCount: 9) == nil)
    #expect(control.phase == .resting)
    #expect(control.handle(.typed("4"), pageCount: 9) == nil)
    #expect(control.phase == .resting)
    #expect(control.handle(.focus(true), pageCount: 9) == nil)
    #expect(control.handle(.startTyping, pageCount: 9) == nil)
    #expect(control.typed == "")
    #expect(control.handle(.typed("4"), pageCount: 9) == nil)
    #expect(control.handle(.focus(false), pageCount: 9) == nil)
    #expect(control.phase == .typing("4"))
    #expect(control.handle(.focus(true), pageCount: 9) == nil)
    #expect(control.handle(.commit, pageCount: 9) == 3)
    #expect(control.phase == .open && control.typed == nil)
    #expect(control.handle(.startTyping, pageCount: 9) == nil)
    #expect(control.handle(.typed("soon"), pageCount: 9) == nil)
    #expect(control.handle(.commit, pageCount: 9) == nil)
    #expect(control.handle(.startTyping, pageCount: 9) == nil)
    #expect(control.handle(.typed("7"), pageCount: 9) == nil)
    #expect(control.handle(.cancel, pageCount: 9) == nil)
    #expect(control.phase == .open)
    #expect(control.handle(.commit, pageCount: 9) == nil)
    #expect(control.handle(.pointer(true), pageCount: 1) == nil)
    #expect(control.phase == .resting)
    #expect(control.handle(.startTyping, pageCount: 1) == nil)
    #expect(control.phase == .resting)
}

@MainActor @Test func thePositionBarAndTheTypedNumberJumpToTheirPage() async {
    let store = library(ready(200))
    #expect(store.state.pageCount == 15)
    await store.send(.pageControl(.pointer(true)))
    await store.send(.pageControl(.dragged(9)))
    #expect(store.state.page == 0)
    #expect(store.state.pageControl.shownPage(current: store.state.page) == 9)
    await store.send(.pageControl(.released))
    #expect(store.state.page == 9)
    #expect(store.state.visibleGameIDs == ids(126..<140))
    await store.send(.pageControl(.startTyping))
    await store.send(.pageControl(.typed("3")))
    await store.send(.pageControl(.commit))
    #expect(store.state.page == 2 && store.state.pageTurn == .backward)
    await store.send(.pageControl(.startTyping))
    await store.send(.pageControl(.typed("400")))
    await store.send(.pageControl(.commit))
    #expect(store.state.page == 14)
    await store.send(.pageControl(.startTyping))
    await store.send(.pageControl(.typed("x")))
    await store.send(.pageControl(.commit))
    #expect(store.state.page == 14)
    await store.send(.pageControl(.startTyping))
    await store.send(.pageControl(.typed("1")))
    await store.send(.pageControl(.cancel))
    #expect(store.state.page == 14)
    #expect(CloudPageBar.page(at: 0, width: 800, count: 15) == 0)
    #expect(CloudPageBar.page(at: 800, width: 800, count: 15) == 14)
    #expect(CloudPageBar.page(at: 400, width: 800, count: 15) == 7)
    #expect(CloudPageBar.page(at: -50, width: 800, count: 15) == 0)
    #expect(CloudPageBar.page(at: 9000, width: 800, count: 15) == 14)
    #expect(CloudPageBar.page(at: 10, width: 0, count: 15) == 0)
}

@Test func aSwipeOrAWheelTurnsOnePagePerGesture() {
    var swipe = CloudPageSwipe()
    #expect(swipe.turn(for: .began, at: 0) == nil)
    #expect(swipe.turn(for: .moved(20), at: 0.01) == nil)
    #expect(swipe.turn(for: .moved(20), at: 0.02) == 1)
    #expect(swipe.turn(for: .moved(400), at: 0.03) == nil)
    #expect(swipe.turn(for: .ended, at: 0.04) == nil)
    #expect(swipe.turn(for: .momentum, at: 0.05) == nil)
    #expect(swipe.turn(for: .momentum, at: 0.3) == nil)
    #expect(swipe.turn(for: .began, at: 1) == nil)
    #expect(swipe.turn(for: .moved(-60), at: 1.01) == -1)
    #expect(swipe.turn(for: .moved(-60), at: 1.02) == nil)
    #expect(swipe.turn(for: .wheel(-3), at: 5) == -1)
    #expect(swipe.turn(for: .wheel(-3), at: 5.2) == nil)
    #expect(swipe.turn(for: .wheel(3), at: 5.6) == nil)
    #expect(swipe.turn(for: .wheel(0.1), at: 5.7) == 1)
    #expect(swipe.turn(for: .wheel(0), at: 9) == nil)
}

@Test func aHeldDirectionOnThePageControlSpeedsUp() {
    var hold = CloudPageHold()
    var steps: [Int] = []
    for press in 0..<24 {
        steps.append(hold.step(forward: true, at: Double(press) * 0.1))
    }
    #expect(steps.prefix(4) == [1, 1, 1, 1])
    #expect(steps[4] == 2 && steps[9] == 2)
    #expect(steps[10] == 5 && steps[19] == 5)
    #expect(steps[20] == 10)
    #expect(hold.step(forward: false, at: 2.4) == 1)
    #expect(hold.step(forward: false, at: 9) == 1)
}

@Test func theNextPagesCoversArePrefetchedOnce() async throws {
    let fetched = Fetched()
    let pipeline = ArtworkPipeline { url in
        fetched.note(url)
        throw URLError(.cancelled)
    }
    var state = ready(40)
    let box = ArtworkBox(width: 256, height: 384)
    await pipeline.prefetch(covers(state.upcomingGames), box: box)
    #expect(fetched.all == (14..<28).map { "https://image.example/\($0).png" }.sorted())
    await pipeline.prefetch(covers(state.upcomingGames), box: box)
    #expect(fetched.all.count == 14)
    state.show(page: 1)
    await pipeline.prefetch(covers(state.upcomingGames), box: box)
    #expect(fetched.all.count == 26)
    #expect(Set(fetched.all) == Set((14..<40).map { "https://image.example/\($0).png" }))
    state.show(page: 0)
    await pipeline.prefetch(covers(state.upcomingGames), box: box)
    state.show(page: 2)
    await pipeline.prefetch(covers(state.upcomingGames), box: box)
    #expect(fetched.all.count == 26)
    await pipeline.prefetch(covers(state.listing.games(onPage: 1)), box: ArtworkBox(width: 512, height: 768))
    #expect(fetched.all.count == 40)
}

@MainActor @Test func pageTurnsNeverMatchOrListAgain() async {
    let store = library(ready(5_000))
    let settled = store.state.listing.derivations
    #expect(settled.listings == 1 && settled.matches == 1)
    for _ in 0..<50 {
        await store.send(.turnPage(1))
    }
    for _ in 0..<20 {
        await store.send(.turnPage(-1))
    }
    await store.send(.showPage(300))
    await store.send(.pageControl(.dragged(10)))
    await store.send(.pageControl(.dragged(200)))
    await store.send(.pageControl(.released))
    await store.send(.pageControl(.pointer(true)))
    await store.send(.pageControl(.focus(true)))
    #expect(store.state.page == 200)
    #expect(store.state.listing.derivations.listings == 1)
    #expect(store.state.listing.derivations.matches == 1)
    #expect(store.state.listing.derivations.pages == settled.pages + 72)
    await store.send(.turnPage(0))
    await store.send(.showPage(200))
    #expect(store.state.listing.derivations.pages == settled.pages + 72)
    await store.send(.gridShape(CloudGridShape(columns: 6, rows: 2), keeping: nil))
    #expect(store.state.listing.derivations.matches == 1)
    #expect(store.state.listing.derivations.pages == settled.pages + 73)
}
