@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let firstSession = StreamSessionID(uuid: UUID(0))

private func cloudSource() -> StreamSource {
    .cloud(CloudStreamRequest(
        profile: ProfileID(uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!),
        title: CloudStreamTitle(
            product: ProductID(rawValue: "EP0000-PPSA00000_00-GAME000000000000")!,
            name: "Example",
            service: .psCloud
        )
    ))
}

@Test func closingNoticesSayWhenAndWhyTheGameCloses() {
    #expect(String(localized: CloudClosingNotice(minutes: 5, reason: .timeLimit).message)
        == "The game closes in 5 minutes because of the streaming time limit. Save your progress.")
    #expect(String(localized: CloudClosingNotice(minutes: 1, reason: .timeLimit).message)
        .contains("in 1 minute because"))
    let maintenance = CloudClosingNotice(minutes: 180, reason: .maintenance)
    #expect(String(localized: maintenance.message).contains("maintenance in 3 hours"))
    #expect(String(localized: CloudClosingNotice(minutes: 30, reason: .unexplained).message)
        == "The streaming service closes the game in 30 minutes. Save your progress.")
    #expect(CloudClosingNotice(minutes: -4, reason: .timeLimit).minutes == 0)
}

@MainActor @Test func aClosingNoticeShowsForTheLiveSessionAndThenHides() async {
    let calls = StreamSessionCalls()
    let clock = TestClock()
    let store = calls.store(clock: clock)
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .firstFrame))
    let five = CloudClosingNotice(minutes: 5, reason: .timeLimit)
    let three = CloudClosingNotice(minutes: 3, reason: .timeLimit)
    await store.send(.event(StreamSessionID(uuid: UUID(99)), .closing(five)))
    #expect(store.state.closingNotice == nil)
    await store.send(.event(firstSession, .closing(five))) {
        $0.closingNotice = five
    }
    await clock.advance(by: .seconds(6))
    await store.send(.event(firstSession, .closing(three))) {
        $0.closingNotice = three
    }
    await clock.advance(by: .seconds(6))
    await store.send(.closingNoticeExpired(firstSession, five))
    #expect(store.state.closingNotice == three)
    await clock.advance(by: CloudClosingNotice.shownFor)
    await store.receive(.closingNoticeExpired(firstSession, three)) {
        $0.closingNotice = nil
    }
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aClosingNoticeLeavesWithTheSession() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.start(cloudSource()))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.event(firstSession, .closing(CloudClosingNotice(minutes: 1, reason: .maintenance))))
    #expect(store.state.closingNotice != nil)
    await store.send(.failed(firstSession, .renderer))
    #expect(store.state.closingNotice == nil)
}
