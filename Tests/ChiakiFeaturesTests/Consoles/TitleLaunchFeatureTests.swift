import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let profileA = UUID()
private let profileB = UUID()
private let consoleID = UUID()
private let hardware = Data(repeating: 0xab, count: 6)
private let title = RecentTitle(
    titleID: "PPSA01234_00", launchID: "PPSA01234", name: "Game",
    imageURL: "https://image.api.playstation.com/game.png", lastPlayedMs: 1_767_290_400_000, recent: true
)

private func launchRequest(_ account: UUID = profileA) -> TitleLaunch {
    TitleLaunch(accountID: account, consoleID: consoleID, hardwareID: hardware, title: title)
}

@MainActor @Test func aLaunchFailureStillStartsTheStreamAndNoPINMeansNoResend() async {
    let launches = LockIsolated(0)
    let store = TestStore(initialState: TitleLaunchFeature.State.idle) {
        TitleLaunchFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.launchTitle = { _, _, _ in
            launches.withValue {
                $0 += 1
            }
            throw ConsoleTitlesFailure.rejected
        }
    }
    let request = launchRequest()
    await store.send(.play(request)) {
        $0 = .launching(OperationID(uuid: UUID(0)), request)
    }
    #expect(store.state.title == title)
    await store.receive(.launchFinished(OperationID(uuid: UUID(0)))) {
        $0 = .awaitingStream(request)
    }
    await store.receive(.delegate(.startStream(request)))
    await store.send(.play(launchRequest(profileB)))
    let session = UUID()
    await store.send(.streamStarted(session)) {
        $0 = .streaming(session, request, .none)
    }
    await store.send(.streamConnected(session))
    await store.send(.streamEnded) {
        $0 = .idle
    }
    #expect(launches.value == 1)
}

@MainActor @Test func aLoginPINResendsTheLaunchExactlyOnceAfterTheSessionConnects() async {
    let launches = LockIsolated<[String]>([])
    let session = UUID()
    let request = launchRequest()
    let store = TestStore(initialState: TitleLaunchFeature.State.streaming(session, request, .none)) {
        TitleLaunchFeature()
    } withDependencies: {
        $0.consoles.launchTitle = { _, device, title in
            launches.withValue {
                $0.append("\(device == hardware):\(title.titleID)")
            }
            return .completed
        }
    }
    await store.send(.loginPINRequested(UUID()))
    await store.send(.loginPINRequested(session)) {
        $0 = .streaming(session, request, .requested)
    }
    await store.send(.loginPINRequested(session))
    await store.send(.streamConnected(UUID()))
    await store.send(.streamConnected(session)) {
        $0 = .streaming(session, request, .resent)
    }
    await store.send(.streamConnected(session))
    await store.send(.loginPINRequested(session))
    await store.finish()
    #expect(launches.value == ["true:PPSA01234_00"])
}

@MainActor @Test func cancellingALaunchDropsItsLateCompletion() async {
    let clock = TestClock()
    let store = TestStore(initialState: TitleLaunchFeature.State.idle) {
        TitleLaunchFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.launchTitle = { _, _, _ in
            try await clock.sleep(for: .seconds(3))
            return .completed
        }
    }
    let request = launchRequest()
    await store.send(.play(request)) {
        $0 = .launching(OperationID(uuid: UUID(0)), request)
    }
    await store.send(.cancel) {
        $0 = .idle
    }
    await clock.advance(by: .seconds(5))
    await store.send(.launchFinished(OperationID(uuid: UUID(0))))
    await store.finish()
}
