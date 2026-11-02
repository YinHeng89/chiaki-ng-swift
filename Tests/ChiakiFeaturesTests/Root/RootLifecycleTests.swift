import ChiakiClients
import ChiakiDiagnostics
@testable import ChiakiFeatures
@testable import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Test
func switchingAccountsStopsOwnedCloudPlayback() async throws {
    let firstAccount = UUID()
    let secondAccount = UUID()
    let playbackID = StreamSessionID()
    let game = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[{"productId":"catalog-id","name":"Example","platform":"ps5","category":"owned",
    "isOwned":true,"plusCatalog":false,"streamServiceType":"pscloud",
    "streamIdentifier":"launch-entitlement","entitlementId":"owned-entitlement"}]}
    """.utf8))
    var flow = RegistrationFlow()
    flow.restoreProfiles([
        .init(id: firstAccount, name: "First", kind: .npsso, accountID: nil),
        .init(id: secondAccount, name: "Second", kind: .npsso, accountID: nil)
    ], selected: firstAccount)
    var state = RootFeature.State(route: .library)
    state.appData = flow
    let request = try CloudLaunchRequest(accountID: firstAccount, game: game.games[0])
    state.stream.source = StreamFeature.source(cloud: request)
    state.stream.session = .playing(playbackID)
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
        $0.accounts.selectAccount = { _ in
            true
        }
    }
    store.exhaustivity = .off

    await store.send(.view(.selectAccount(secondAccount))) {
        $0.$selectedAccount.withLock {
            $0 = secondAccount
        }
    }
    await store.receive(.autoConnect(.interrupted))
    await store.receive(.wakeResume(.interrupted))
    await store.receive(.accounts(.refresh(force: false)))
    await store.receive(.stream(.stop))
    #expect(store.state.stream.session == .stopping(playbackID, .disconnect))
    await store.receive(.stream(.stopped(playbackID, .left)))
    #expect(store.state.stream.status == .idle)
}

private func quitting() -> RootFeature.State {
    var state = RootFeature.State()
    state.lifecycle = LifecycleFeature.State(termination: .ready)
    return state
}

@MainActor @Test func terminationWaitsForTheLifecycleOwnerAndRejectsStaleCompletion() async {
    let id = OperationID(uuid: UUID())
    let clock = TestClock()
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .constant(id.uuid)
        $0.platform.shutdown = {
            try? await clock.sleep(for: .seconds(1))
        }
    }
    await store.send(.terminationRequested)
    await store.receive(.lifecycle(.terminationRequested)) {
        $0.lifecycle = LifecycleFeature.State(termination: .stopping(id))
    }
    await store.receive(.lifecycle(.delegate(.terminating)))
    await store.receive(.stream(.stop))
    await store.receive(.liveLog(.close))
    await store.send(.terminationRequested)
    await store.receive(.lifecycle(.terminationRequested))
    await store.send(.lifecycle(.terminationCompleted(OperationID(uuid: UUID()))))
    await clock.advance(by: .seconds(1))
    await store.receive(.lifecycle(.terminationCompleted(id))) {
        $0.lifecycle = LifecycleFeature.State(termination: .ready)
    }
    await store.finish()
}

@MainActor @Test func systemSleepStopsActivePlaybackThroughTheSleepPath() async throws {
    let playbackID = StreamSessionID()
    let account = UUID()
    let game = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[{"productId":"catalog-id","name":"Example","platform":"ps5","category":"owned",
    "isOwned":true,"plusCatalog":false,"streamServiceType":"pscloud",
    "streamIdentifier":"launch-entitlement","entitlementId":"owned-entitlement"}]}
    """.utf8))
    var state = RootFeature.State()
    let request = try CloudLaunchRequest(accountID: account, game: game.games[0])
    state.stream.source = StreamFeature.source(cloud: request)
    state.stream.session = .playing(playbackID)
    let sleeps = LockIsolated(0)
    let shutdowns = LockIsolated(0)
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.platform = PlatformClient(
            shutdown: {
                shutdowns.withValue {
                    $0 += 1
                }
            },
            sleep: { _ in
                sleeps.withValue {
                    $0 += 1
                }
                return true
            }
        )
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
    }
    store.exhaustivity = .off
    await store.send(.systemWillSleep(7))
    await store.receive(.lifecycle(.systemWillSleep(
        7,
        consoleStreaming: false,
        stream: playbackID,
        guestJoin: nil
    )))
    await store.receive(.lifecycle(.delegate(.sleeping)))
    await store.receive(.autoConnect(.interrupted))
    await store.receive(.wakeResume(.sleeping(active: nil)))
    await store.receive(.lifecycle(.sleepStoppedStream(playbackID, guestJoin: nil)))
    await store.receive(.lifecycle(.delegate(.sleepStoppedStream(playbackID, guestJoin: nil))))
    await store.receive(.stream(.stop))
    await store.receive(.stream(.stopped(playbackID, .left)))
    #expect(store.state.stream.status == .idle)
    await store.finish()
    #expect(sleeps.value == 1 && shutdowns.value == 0)
}

@MainActor @Test func systemSleepWithoutAStreamLeavesPlaybackAlone() async {
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.platform = PlatformClient(shutdown: {}, sleep: { _ in
            false
        })
    }
    await store.send(.systemWillSleep(7))
    await store.receive(.lifecycle(.systemWillSleep(7, consoleStreaming: false, stream: nil, guestJoin: nil)))
    await store.receive(.lifecycle(.delegate(.sleeping)))
    await store.receive(.autoConnect(.interrupted))
    await store.receive(.wakeResume(.sleeping(active: nil)))
    await store.finish()
    let stopped = TestStore(initialState: quitting()) {
        RootFeature()
    } withDependencies: {
        $0.platform = PlatformClient(shutdown: {}, sleep: { _ in
            Issue.record("sleep after termination")
            return true
        })
    }
    await stopped.send(.systemWillSleep(7))
    await stopped.receive(.lifecycle(.systemWillSleep(
        7,
        consoleStreaming: false,
        stream: nil,
        guestJoin: nil
    )))
}

@MainActor @Test func systemSleepIsReleasedOnlyAfterPlaybackStops() async {
    let events = LockIsolated([String]())
    let lifecycle = PlatformClient(
        shutdown: {},
        sleep: { _ in
            events.withValue {
                $0.append("stopped")
            }
            return false
        },
        allowSleep: { notification in
            events.withValue {
                $0.append("allow \(notification)")
            }
        }
    )
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    store.exhaustivity = .off
    await store.send(.systemWillSleep(42))
    await store.finish()
    #expect(events.value == ["stopped", "allow 42"])

    let ended = TestStore(initialState: quitting()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
        $0.platform.sleep = { _ in
            Issue.record("sleep after termination")
            return true
        }
    }
    ended.exhaustivity = .off
    await ended.send(.systemWillSleep(43))
    await ended.finish()
    #expect(events.value == ["stopped", "allow 42", "allow 43"])
}

@MainActor @Test func systemWakeIsForwardedOnlyWhileRunning() async {
    let wakes = LockIsolated(0)
    let lifecycle = PlatformClient(
        shutdown: {},
        woke: {
            wakes.withValue {
                $0 += 1
            }
        }
    )
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    await store.send(.systemDidWake)
    await store.receive(.lifecycle(.systemDidWake))
    await store.receive(.lifecycle(.delegate(.woke)))
    await store.receive(.wakeResume(.woke))
    await store.finish()
    #expect(wakes.value == 1)
    let ended = TestStore(initialState: quitting()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    await ended.send(.systemDidWake)
    await ended.receive(.lifecycle(.systemDidWake))
    #expect(wakes.value == 1)
}

@MainActor @Test func aNetworkChangeDropsConnectionsOnlyWhileRunning() async {
    let changes = LockIsolated(0)
    let lifecycle = PlatformClient(
        shutdown: {},
        networkChanged: {
            changes.withValue {
                $0 += 1
            }
        }
    )
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    await store.send(.networkChanged)
    await store.receive(.lifecycle(.networkChanged))
    await store.finish()
    #expect(changes.value == 1)
    let ended = TestStore(initialState: quitting()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    await ended.send(.networkChanged)
    await ended.receive(.lifecycle(.networkChanged))
    #expect(changes.value == 1)
}

@MainActor @Test func macSleepRestsTheConsoleOnlyForAConsoleStreamWithTheSettingOn() async {
    let requests = LockIsolated([Bool]())
    let loads = LockIsolated(0)
    let lifecycle = PlatformClient(
        shutdown: {},
        sleep: { rest in
            requests.withValue {
                $0.append(rest)
            }
            return false
        },
        restsConsoleOnSleep: {
            loads.withValue {
                $0 += 1
            }
            return true
        }
    )
    var streaming = RootFeature.State()
    streaming.stream.session = .playing(StreamSessionID())
    streaming.stream.source = StreamFeature.source(
        account: UUID(),
        console: RegistrationFlow.ConsoleTarget(address: "192.0.2.5", kind: .ps5),
        route: .local
    )
    let store = TestStore(initialState: streaming) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    store.exhaustivity = .off
    await store.send(.systemWillSleep(1))
    await store.finish()

    let idle = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.platform = lifecycle
    }
    idle.exhaustivity = .off
    await idle.send(.systemWillSleep(2))
    await idle.finish()
    #expect(requests.value == [true, false])
    #expect(loads.value == 1)
}

@MainActor @Test(.enabled(if: KakusanBuild.included))
func joiningAKakusanSessionCancelsAutoConnect() async {
    var state = RootFeature.State(route: .library)
    let console = RegistrationFlow.ConsoleTarget(address: "192.0.2.5", kind: .ps5, id: UUID(), name: "Den")
    state.autoConnection.machine = .discovering(
        UUID(), AutoConnect.Plan(account: UUID(), consoleID: UUID(), console: console, mode: .stream(.local))
    )
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
    }
    store.exhaustivity = .off
    await store.send(.view(.joinGame))
    await store.receive(.autoConnect(.cancel))
    #expect(store.state.autoConnection.machine == .idle)
    await store.finish()
}

@MainActor @Test func aSleepThatFinishesAfterWakeCannotStopTheStreamStartedSince() async throws {
    let sleeping = AsyncStream.makeStream(of: Bool.self)
    let sleeps = LockIsolated(0)
    let lifecycle = PlatformClient(
        shutdown: {},
        sleep: { _ in
            sleeps.withValue {
                $0 += 1
            }
            for await stopped in sleeping.stream {
                return stopped
            }
            return false
        }
    )
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
        $0.platform = lifecycle
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
    }
    store.exhaustivity = .off
    await store.send(.systemWillSleep(7))
    await store.receive(.lifecycle(.delegate(.sleeping)))
    while sleeps.value == 0 {
        await Task.yield()
    }
    await store.send(.systemDidWake)
    await store.receive(.lifecycle(.delegate(.woke)))
    let console = RegistrationFlow.ConsoleTarget(address: "192.0.2.5", kind: .ps5, id: UUID())
    await store.send(.stream(.startConsole(account: UUID(), console: console, route: .local)))
    let resumed = try #require(store.state.stream.session.id)
    await store.send(.stream(.event(resumed, .firstFrame)))
    #expect(store.state.stream.session == .playing(resumed))
    sleeping.continuation.yield(true)
    await store.receive(.lifecycle(.sleepStoppedStream(nil, guestJoin: nil)))
    await store.receive(.lifecycle(.delegate(.sleepStoppedStream(nil, guestJoin: nil))))
    await store.skipReceivedActions(strict: false)
    #expect(store.state.stream.session == .playing(resumed))
    await store.send(.stream(.stop))
}

@MainActor @Test(.enabled(if: KakusanBuild.included))
func aGuestSessionJoinedAfterWakeSurvivesALateSleepAnswer() async {
    let sleeping = AsyncStream.makeStream(of: Bool.self)
    let sleeps = LockIsolated(0)
    let lifecycle = PlatformClient(
        shutdown: {},
        sleep: { _ in
            sleeps.withValue {
                $0 += 1
            }
            for await stopped in sleeping.stream {
                return stopped
            }
            return false
        }
    )
    let store = TestStore(initialState: RootFeature.State(route: .library)) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
        $0.platform = lifecycle
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
    }
    store.exhaustivity = .off
    await store.send(.systemWillSleep(7))
    await store.receive(.lifecycle(.delegate(.sleeping)))
    while sleeps.value == 0 {
        await Task.yield()
    }
    await store.send(.systemDidWake)
    await store.receive(.lifecycle(.delegate(.woke)))
    await store.send(.view(.joinGame))
    await store.receive(.route(.kakusanGuest(.open)))
    #expect(store.state.guestPresented)
    sleeping.continuation.yield(true)
    await store.receive(\.lifecycle.delegate.sleepStoppedStream)
    await store.skipReceivedActions(strict: false)
    #expect(store.state.guestPresented)
}

@MainActor @Test(.enabled(if: KakusanBuild.included))
func aGuestJoinShownAsSleepBeganIsLeftWhenSleepStopsIt() async {
    let store = TestStore(initialState: RootFeature.State(route: .library)) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.platform = PlatformClient(shutdown: {}, sleep: { _ in
            true
        })
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
    }
    store.exhaustivity = .off
    await store.send(.view(.joinGame))
    await store.receive(.route(.kakusanGuest(.open)))
    #expect(store.state.guestPresented)
    await store.send(.systemWillSleep(7))
    await store.receive(\.lifecycle.delegate.sleepStoppedStream)
    await store.receive(.route(.kakusanGuest(.leave)))
    #expect(!store.state.guestPresented)
}

private func heldSleepLifecycle(
    _ answers: AsyncStream<Bool>,
    sleeps: LockIsolated<Int>
) -> PlatformClient {
    PlatformClient(
        shutdown: {},
        sleep: { _ in
            sleeps.withValue {
                $0 += 1
            }
            for await stopped in answers {
                return stopped
            }
            return false
        }
    )
}

@MainActor
private func guestRootStore(
    _ state: RootFeature.State,
    lifecycle: PlatformClient
) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = TestClock()
        $0.platform = lifecycle
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.kakusan.stopGuest = {}
        $0.idleKakusanHosting()
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func aGuestWhosePlayEndedBeforeALateSleepAnswerIsStillLeft() async {
    let sleeping = AsyncStream.makeStream(of: Bool.self)
    let sleeps = LockIsolated(0)
    let session = UUID()
    var guest = KakusanGuestFeature.State()
    guest.join.phase = .streaming(session, KakusanGuestStream(seat: 2, video: .playing(fps: 60)))
    guest.joinID = UUID()
    let store = guestRootStore(
        RootFeature.State(route: .kakusanGuest(guest)),
        lifecycle: heldSleepLifecycle(sleeping.stream, sleeps: sleeps)
    )
    await store.send(.systemWillSleep(7))
    await store.receive(.lifecycle(.delegate(.sleeping)))
    while sleeps.value == 0 {
        await Task.yield()
    }
    await store.send(.route(.kakusanGuest(.playEnded(session))))
    #expect(store.state.route[case: \.kakusanGuest]?.join.session == nil)
    #expect(store.state.guestPresented)
    sleeping.continuation.yield(true)
    await store.receive(\.lifecycle.delegate.sleepStoppedStream)
    await store.receive(.route(.kakusanGuest(.leave)))
    #expect(!store.state.guestPresented)
}

@MainActor @Test(.enabled(if: KakusanBuild.included))
func aJoinOpenedAfterLeavingTheOneShownAtSleepSurvivesALateSleepAnswer() async {
    let sleeping = AsyncStream.makeStream(of: Bool.self)
    let sleeps = LockIsolated(0)
    let store = guestRootStore(
        RootFeature.State(route: .library),
        lifecycle: heldSleepLifecycle(sleeping.stream, sleeps: sleeps)
    )
    await store.send(.view(.joinGame))
    await store.receive(.route(.kakusanGuest(.open)))
    await store.send(.systemWillSleep(7))
    await store.receive(.lifecycle(.delegate(.sleeping)))
    while sleeps.value == 0 {
        await Task.yield()
    }
    await store.send(.systemDidWake)
    await store.receive(.lifecycle(.delegate(.woke)))
    await store.send(.route(.kakusanGuest(.leave)))
    #expect(!store.state.guestPresented)
    await store.send(.view(.joinGame))
    await store.receive(.route(.kakusanGuest(.open)))
    #expect(store.state.guestPresented)
    sleeping.continuation.yield(true)
    await store.receive(\.lifecycle.delegate.sleepStoppedStream)
    await store.skipReceivedActions(strict: false)
    #expect(store.state.guestPresented)
}
