import ChiakiModels
@testable import ChiakiFeatures
import ChiakiClients
import ComposableArchitecture
import Foundation
import Testing

private let account = UUID()
private let otherAccount = UUID()
private let consoleID = UUID()
private let console = RegistrationFlow.ConsoleTarget(
    address: "192.0.2.5", kind: .ps5, remoteDeviceID: Data(repeating: 1, count: 32), id: consoleID,
    name: "Living Room", hardwareID: "aabbccddeeff"
)
private let registered = RegisteredConsole(
    hardwareID: "aabbccddeeff", id: consoleID, name: "Living Room", accountID: account, address: "192.0.2.5",
    ps5: true, remoteDeviceID: Data(repeating: 1, count: 32)
)
private let plan = AutoConnect.Plan(
    account: account,
    consoleID: consoleID,
    console: console,
    mode: .stream(.local)
)

private func discovered(standby: Bool, address: String = "192.0.2.77") -> DiscoverySnapshot {
    let found = DiscoveredConsole(
        id: "AABBCCDDEEFF", name: "Living Room", address: address, kind: .ps5, standby: standby
    )
    return DiscoverySnapshot(consoles: [found], networkAvailable: true)
}

private func libraryPage(
    selected: UUID = account,
    loaded: Bool = true,
    catalogLoading: UUID? = nil
) -> RootFeature.State {
    var flow = RegistrationFlow()
    flow.restoreProfiles(
        [
            .init(id: account, name: "Demo", kind: .npsso, accountID: nil),
            .init(id: otherAccount, name: "Other", kind: .npsso, accountID: nil)
        ],
        selected: selected
    )
    flow.restoreRegistrations([.init(profileID: account, console: console)])
    var state = RootFeature.State(route: .library)
    state.appData = flow
    if loaded {
        state.accounts = AccountsFeature.State(loaded: [])
    }
    if let catalogLoading {
        state.consoleCatalog.load = .loading(OperationID(uuid: catalogLoading))
    } else if loaded {
        state.catalogStatus = .loaded
        state.autoConnection.library = .ready(flow.registrations, selected: selected)
    }
    return state
}

private final class Scans: Sendable {
    let continuations = LockIsolated<[AsyncThrowingStream<DiscoverySnapshot, Error>.Continuation]>([])

    func scan(_: DiscoverySettings) -> AsyncThrowingStream<DiscoverySnapshot, Error> {
        let pair = AsyncThrowingStream<DiscoverySnapshot, Error>.makeStream()
        continuations.withValue {
            $0.append(pair.continuation)
        }
        return pair.stream
    }

    func yield(_ snapshot: DiscoverySnapshot, scan index: Int = 0) {
        _ = continuations.value[index].yield(snapshot)
    }

    var count: Int {
        continuations.value.count
    }

    var events: @Sendable () async -> AsyncStream<ConsoleScanEvent> {
        { [self] in
            let source = scan(DiscoverySettings())
            return AsyncStream { continuation in
                let task = Task {
                    do {
                        for try await snapshot in source {
                            continuation.yield(.snapshot(snapshot))
                        }
                    } catch {}
                    continuation.yield(.failed)
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
    }
}

private enum WakeBehaviour {
    case succeeds, fails, hangs
}

@MainActor private func autoConnectStore(
    _ state: RootFeature.State = libraryPage(),
    clock: TestClock<Duration>,
    scans: Scans,
    wakes: LockIsolated<[String]> = LockIsolated([]),
    wake: WakeBehaviour = .succeeds,
    launchConsole: UUID? = consoleID,
    launchFails: Bool = false
) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.idleKakusanHosting()
        $0.uuid = .incrementing
        $0.continuousClock = clock
        $0.consoles.scanEvents = scans.events
        $0.consoles.launchConsole = {
            if launchFails {
                throw PlaybackFailure.renderer
            }
            return launchConsole
        }
        $0.consoles.wake = { _, _, address in
            wakes.withValue {
                $0.append(address)
            }
            switch wake {
            case .succeeds:
                break
            case .fails:
                throw PlaybackFailure.renderer
            case .hangs:
                try await Task.never()
            }
        }
        $0.streamSession = StreamSessionCalls().client(on: $0.streamSession)
        $0.idleKakusanHosting()
    }
    store.exhaustivity = .off
    return store
}

@MainActor private func scanID(_ store: TestStoreOf<RootFeature>) -> OperationID? {
    if let id = store.state.discovery.phase.scan {
        return id
    }
    return nil
}

@MainActor private func report(
    _ snapshot: DiscoverySnapshot,
    to store: TestStoreOf<RootFeature>,
    via scans: Scans
) async {
    if scanID(store) == nil {
        await store.receive(.discovery(.acquire(.autoConnect)))
    }
    guard let id = scanID(store) else {
        Issue.record("Discovery is not scanning")
        return
    }
    while scans.count == 0 {
        await Task.yield()
    }
    scans.yield(snapshot, scan: scans.count - 1)
    await store.receive(.discovery(.scanned(id, .snapshot(snapshot))))
    await store.receive(.autoConnect(.discovered(snapshot)))
}

@MainActor private func run(_ store: TestStoreOf<RootFeature>) -> UUID {
    store.state.autoConnection.machine.run ?? UUID()
}

private let wakePlan = AutoConnect.Plan(account: account, consoleID: consoleID, console: console, mode: .wake)

@MainActor @Test func launchChecksTheSavedConsoleOnceAfterTheLibraryLoadsAndStreamsWhenAwake() async {
    let clock = TestClock(), scans = Scans(), load = UUID()
    let store = autoConnectStore(libraryPage(catalogLoading: load), clock: clock, scans: scans)
    await store.send(.autoConnect(.launch)) {
        $0.autoConnection.launchCheck = .done
        $0.autoConnection.machine = .awaitingLibrary(UUID(0), .launchSetting)
    }
    await store.send(.autoConnect(.launch))
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: UUID()), .success([registered]))))
    #expect(store.state.autoConnection.machine == .awaitingLibrary(UUID(0), .launchSetting))
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: load), .success([registered]))))
    await store.receive(\.autoConnect.libraryChanged)
    #expect(store.state.autoConnection.machine == .checkingLaunchSetting(UUID(1)))
    await store.receive(.autoConnect(.launchSettingLoaded(UUID(1), consoleID)))
    #expect(store.state.autoConnection.machine == .discovering(UUID(2), plan))
    await store.receive(.discovery(.acquire(.autoConnect)))
    #expect(store.state.discovery.leases == [.autoConnect])
    await report(discovered(standby: true), to: store, via: scans)
    #expect(store.state.autoConnection.machine == .waking(UUID(2), plan))
    await store.receive(.autoConnect(.wakeSent(UUID(2), true)))
    #expect(store.state.autoConnection.machine == .awaitingWake(UUID(2), plan))
    await report(discovered(standby: false), to: store, via: scans)
    await store.receive(.discovery(.release(.autoConnect)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    #expect(store.state.autoConnection.machine == .idle)
    #expect(store.state.discovery.leases.isEmpty)
    #expect(store.state.discovery.phase == .idle)
    #expect(store.state.route == .stream)
    #expect(scans.count == 1)
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func launchIsNotArmedWhenTheLibraryCannotLoad() async {
    let clock = TestClock(), scans = Scans()
    var failed = libraryPage(loaded: false)
    failed.catalogStatus = .failed
    failed.autoConnection.library = .unavailable
    let store = autoConnectStore(failed, clock: clock, scans: scans)
    await store.send(.autoConnect(.launch))
    #expect(store.state.autoConnection.launchCheck == .done)
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: UUID()), .success([]))))
    #expect(store.state.autoConnection.machine == .idle)

    var preview = libraryPage()
    preview.appData.selectStream(profile: account, console: console)
    preview.route = .stream
    let streaming = autoConnectStore(preview, clock: clock, scans: scans)
    await streaming.send(.autoConnect(.launch))
    #expect(streaming.state.autoConnection.machine == .idle)
    #expect(streaming.state.autoConnection.launchCheck == .done)
    await streaming.finish()
}

@MainActor @Test func aLaunchCheckThatWaitsTooLongIsDropped() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(libraryPage(loaded: false), clock: clock, scans: scans)
    await store.send(.autoConnect(.launch))
    #expect(store.state.autoConnection.machine == .awaitingLibrary(UUID(0), .launchSetting))
    await clock.advance(by: AutoConnect.libraryTimeout)
    await store.receive(.autoConnect(.deadline(UUID(0), .library)))
    #expect(store.state.autoConnection.machine == .idle)
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: UUID()), .success([registered]))))
    #expect(store.state.autoConnection.machine == .idle)

    let request = autoConnectStore(libraryPage(loaded: false), clock: clock, scans: scans)
    await request.send(.autoConnect(.start(consoleID, .wake)))
    await clock.advance(by: AutoConnect.libraryTimeout)
    await request.receive(.autoConnect(.deadline(UUID(0), .library)))
    #expect(request.state.autoConnection.machine == .failed(nil, .storage))
    #expect(scans.count == 0)
}

@MainActor @Test func noSavedLaunchConsoleLeavesTheLibraryAlone() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans, launchConsole: nil)
    await store.send(.autoConnect(.launch))
    #expect(store.state.autoConnection.machine == .checkingLaunchSetting(UUID(0)))
    await store.receive(.autoConnect(.launchSettingLoaded(UUID(0), nil)))
    #expect(store.state.autoConnection.machine == .idle)
    #expect(store.state.route == .library)
    await store.finish()
    #expect(scans.count == 0)
}

@MainActor @Test func aRunningDiscoveryIsBorrowedAndLeftRunning() async {
    let clock = TestClock(), scans = Scans(), wakes = LockIsolated<[String]>([])
    let store = autoConnectStore(clock: clock, scans: scans, wakes: wakes)
    await store.send(.discovery(.acquire(.library)))
    await report(discovered(standby: true), to: store, via: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    let current = run(store)
    await store.receive(.discovery(.acquire(.autoConnect)))
    await store.receive(\.autoConnect.discovered)
    #expect(store.state.discovery.leases == [.library, .autoConnect])
    #expect(store.state.autoConnection.machine == .waking(current, plan))
    await store.receive(.autoConnect(.wakeSent(current, true)))
    #expect(wakes.value == ["192.0.2.77"])
    await report(discovered(standby: false), to: store, via: scans)
    #expect(scanID(store) != nil)
    #expect(scans.count == 1)
    await store.send(.discovery(.release(.library)))
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func aConsoleThatNeverWakesStillGetsAStreamAttemptAfterTwentyFiveSeconds() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    let current = run(store)
    await report(discovered(standby: true), to: store, via: scans)
    await store.receive(.autoConnect(.wakeSent(current, true)))
    await clock.advance(by: AutoConnect.wakeTimeout - .seconds(1))
    #expect(store.state.autoConnection.machine == .awaitingWake(current, plan))
    await clock.advance(by: .seconds(1))
    await store.receive(.autoConnect(.deadline(current, .wake)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func aHungWakeRequestTimesOutAndDiscoveryEndingWhileWakingIsIgnored() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans, wake: .hangs)
    await store.send(.autoConnect(.start(consoleID, .wake)))
    let current = run(store)
    await report(discovered(standby: true), to: store, via: scans)
    #expect(store.state.autoConnection.machine == .waking(current, wakePlan))
    if let id = scanID(store) {
        await store.send(.discovery(.scanned(id, .failed)))
    }
    #expect(store.state.autoConnection.machine == .waking(current, wakePlan))
    await clock.advance(by: AutoConnect.wakeTimeout)
    await store.receive(.autoConnect(.deadline(current, .wake)))
    #expect(store.state.autoConnection.machine == .failed("Living Room", .wakeTimedOut))
    #expect(store.state.route == .library)
    await store.finish()
}

@MainActor @Test func wakeOnlyModeReportsATimeoutAndAFailedWakeRequest() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .wake)))
    let current = run(store)
    await report(discovered(standby: true), to: store, via: scans)
    await store.receive(.autoConnect(.wakeSent(current, true)))
    #expect(store.state.autoConnection.machine == .awaitingWake(current, wakePlan))
    await clock.advance(by: AutoConnect.wakeTimeout)
    await store.receive(.autoConnect(.deadline(current, .wake)))
    #expect(store.state.autoConnection.machine == .failed("Living Room", .wakeTimedOut))
    await store.send(.autoConnect(.dismiss))
    #expect(store.state.autoConnection.machine == .idle)
    await store.finish()

    let failingScans = Scans()
    let failing = autoConnectStore(clock: clock, scans: failingScans, wake: .fails)
    await failing.send(.autoConnect(.start(consoleID, .wake)))
    let failingRun = run(failing)
    await report(discovered(standby: true), to: failing, via: failingScans)
    await failing.receive(.autoConnect(.wakeSent(failingRun, false)))
    #expect(failing.state.autoConnection.machine == .failed("Living Room", .wakeFailed))
    await failing.finish()
}

@MainActor @Test func wakeOnlyModeFinishesQuietlyWhenTheConsoleIsAlreadyAwake() async {
    let clock = TestClock(), scans = Scans(), wakes = LockIsolated<[String]>([])
    let store = autoConnectStore(clock: clock, scans: scans, wakes: wakes)
    await store.send(.autoConnect(.start(consoleID, .wake)))
    await report(discovered(standby: false), to: store, via: scans)
    #expect(store.state.autoConnection.machine == .idle)
    #expect(store.state.route == .library)
    #expect(wakes.value.isEmpty)
    await store.finish()
}

@MainActor @Test func wakeOnlyModeReportsAConsoleThatIsNeverSeen() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .wake)))
    let current = run(store)
    await clock.advance(by: AutoConnect.discoveryTimeout)
    await store.receive(.autoConnect(.deadline(current, .discovery)))
    #expect(store.state.autoConnection.machine == .failed("Living Room", .notFound))
    await store.finish()
}

@MainActor @Test func cancellingDuringWakeIgnoresLateCompletionsAndStopsDiscovery() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    let current = run(store)
    await report(discovered(standby: true), to: store, via: scans)
    await store.receive(.autoConnect(.wakeSent(current, true)))
    await store.send(.autoConnect(.cancel))
    await store.receive(.discovery(.release(.autoConnect)))
    #expect(store.state.autoConnection.machine == .idle)
    #expect(store.state.discovery.phase == .idle)
    await store.send(.autoConnect(.wakeSent(current, true)))
    await store.send(.autoConnect(.deadline(current, .wake)))
    await clock.advance(by: .seconds(60))
    #expect(store.state.autoConnection.machine == .idle)
    #expect(store.state.stream.status == .idle)
    #expect(store.state.route == .library)
    await store.finish()
}

@MainActor @Test func anyUserActionCancelsEveryStep() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(libraryPage(loaded: false), clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    #expect(store.state.autoConnection.machine == .awaitingLibrary(
        UUID(0),
        .console(consoleID, .stream(.local))
    ))
    await store.send(.view(.addConsole))
    await store.receive(.autoConnect(.interrupted))
    #expect(store.state.autoConnection.machine == .idle)
    await store.send(.route(.addConsole(.view(.back))))
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: UUID()), .success([]))))
    #expect(store.state.autoConnection.machine == .idle)
    await store.finish()

    let discovering = autoConnectStore(clock: clock, scans: Scans())
    await discovering.send(.autoConnect(.start(consoleID, .stream(.local))))
    await discovering.send(.view(.addAccount))
    await discovering.receive(.autoConnect(.interrupted))
    #expect(discovering.state.autoConnection.machine == .idle)
    await clock.advance(by: AutoConnect.discoveryTimeout)
    #expect(discovering.state.stream.status == .idle)
    await discovering.finish()

    let sleepingScans = Scans()
    let sleeping = autoConnectStore(clock: clock, scans: sleepingScans)
    await sleeping.send(.autoConnect(.start(consoleID, .stream(.local))))
    await report(discovered(standby: true), to: sleeping, via: sleepingScans)
    await sleeping.send(.lifecycle(.delegate(.sleeping)))
    await sleeping.receive(.autoConnect(.interrupted))
    #expect(sleeping.state.autoConnection.machine == .idle)
    await sleeping.finish()
}

@MainActor @Test func restartingReplacesTheRunAndIgnoresTheOldOne() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    let first = run(store)
    await store.send(.autoConnect(.start(consoleID, .wake)))
    let second = run(store)
    #expect(first != second)
    #expect(store.state.autoConnection.machine == .discovering(second, wakePlan))
    await store.send(.autoConnect(.deadline(first, .discovery)))
    await store.send(.autoConnect(.wakeSent(first, true)))
    #expect(store.state.autoConnection.machine == .discovering(second, wakePlan))
    #expect(store.state.route == .library)
    await store.send(.autoConnect(.cancel))
    await store.finish()
}

@MainActor @Test func anUnseenConsoleStillGetsAStreamAttemptAfterDiscoveryTimesOut() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    let current = run(store)
    await clock.advance(by: AutoConnect.discoveryTimeout)
    await store.receive(.autoConnect(.deadline(current, .discovery)))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func remoteStartSkipsDiscoveryAndSelectsTheRegisteredAccount() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(libraryPage(selected: otherAccount), clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.remote))))
    await store.receive(.stream(.startConsole(account: account, console: console, route: .remote)))
    #expect(store.state.selectedAccount == account)
    #expect(scans.count == 0)
    await store.send(.stream(.stop))
    await store.finish()
}

@MainActor @Test func unknownBusyOrUnloadableStartsFailWithoutStreaming() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(UUID(), .stream(.local))))
    #expect(store.state.autoConnection.machine == .failed(nil, .notRegistered))
    await store.send(.autoConnect(.dismiss))

    var streaming = libraryPage()
    streaming.stream.session = .playing(StreamSessionID())
    let busy = autoConnectStore(streaming, clock: clock, scans: scans)
    await busy.send(.autoConnect(.start(consoleID, .stream(.local))))
    #expect(busy.state.autoConnection.machine == .failed("Living Room", .busy))

    let load = UUID()
    let loading = libraryPage(catalogLoading: load)
    let failing = autoConnectStore(loading, clock: clock, scans: scans)
    await failing.send(.autoConnect(.start(consoleID, .stream(.local))))
    await failing.send(.consoleCatalog(.loadFinished(OperationID(uuid: load), .failure(.unavailable))))
    await failing.receive(\.autoConnect.libraryChanged)
    #expect(failing.state.autoConnection.machine == .failed(nil, .storage))
    #expect(scans.count == 0)
}

@MainActor @Test func launchStorageFailuresStaySilent() async {
    let clock = TestClock(), scans = Scans(), load = UUID()
    let store = autoConnectStore(libraryPage(catalogLoading: load), clock: clock, scans: scans)
    await store.send(.autoConnect(.launch))
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: load), .failure(.unavailable))))
    await store.receive(\.autoConnect.libraryChanged)
    #expect(store.state.autoConnection.machine == .idle)
    await store.finish()

    let unreadable = autoConnectStore(clock: clock, scans: scans, launchFails: true)
    await unreadable.send(.autoConnect(.launch))
    await unreadable.receive(.autoConnect(.launchSettingFailed(UUID(0))))
    #expect(unreadable.state.autoConnection.machine == .idle)
    await unreadable.finish()
    #expect(scans.count == 0)
}

@MainActor @Test func aStreamStartedElsewhereOrAFailedAccountLoadEndsTheWait() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    await store.send(.stream(.startConsole(account: account, console: console, route: .local)))
    await store.receive(.autoConnect(.interrupted))
    #expect(store.state.autoConnection.machine == .idle)
    await store.send(.stream(.stop))

    let accountLoad = UUID()
    var unloadedState = libraryPage(loaded: false)
    unloadedState.accounts.operation = .loading(OperationID(uuid: accountLoad))
    let unloaded = autoConnectStore(unloadedState, clock: clock, scans: scans)
    unloaded.exhaustivity = .off
    await unloaded.send(.autoConnect(.launch))
    await unloaded.send(.accounts(.loadFinished(OperationID(uuid: UUID()), .failure(.loadFailed))))
    #expect(unloaded.state.autoConnection.machine.isActive)
    await unloaded.send(.accounts(.loadFinished(OperationID(uuid: accountLoad), .failure(.loadFailed))))
    await unloaded.skipReceivedActions()
    #expect(unloaded.state.autoConnection.machine == .idle)

    var secondState = libraryPage(loaded: false)
    secondState.accounts.operation = .loading(OperationID(uuid: accountLoad))
    let second = autoConnectStore(secondState, clock: clock, scans: scans)
    second.exhaustivity = .off
    await second.send(.autoConnect(.start(consoleID, .wake)))
    await second.send(.accounts(.loadFinished(OperationID(uuid: accountLoad), .failure(.loadFailed))))
    await second.skipReceivedActions()
    #expect(second.state.autoConnection.machine == .failed(nil, .storage))
}

@MainActor @Test func registrationsThatLoadBeforeTheAccountsKeepTheRequestWaiting() async {
    let clock = TestClock(), scans = Scans()
    let store = autoConnectStore(libraryPage(loaded: false), clock: clock, scans: scans)
    await store.send(.autoConnect(.start(consoleID, .stream(.local))))
    await store.send(.consoleCatalog(.loadFinished(OperationID(uuid: UUID()), .success([registered]))))
    #expect(store.state.autoConnection.machine == .awaitingLibrary(
        UUID(0),
        .console(consoleID, .stream(.local))
    ))
    #expect(scans.count == 0)
    await clock.advance(by: AutoConnect.libraryTimeout)
    await store.receive(.autoConnect(.deadline(UUID(0), .library)))
    #expect(store.state.autoConnection.machine == .failed(nil, .storage))
}

@Test func aPairedConsoleMatchesItsHardwareIDWhateverTheSeparatorsAndCase() {
    func snapshot(_ id: String) -> DiscoverySnapshot {
        DiscoverySnapshot(
            consoles: [DiscoveredConsole(
                id: id,
                name: "Den",
                address: "192.0.2.77",
                kind: .ps5,
                standby: false
            )],
            networkAvailable: true
        )
    }
    func target(_ hardwareID: String) -> RegistrationFlow.ConsoleTarget {
        RegistrationFlow.ConsoleTarget(
            address: "192.0.2.5", kind: .ps5, id: consoleID, name: "Living Room", hardwareID: hardwareID
        )
    }
    #expect(snapshot("AA:BB:CC:DD:EE:FF").match(for: target("aabbccddeeff"))?.address == "192.0.2.77")
    #expect(snapshot("AABBCCDDEEFF").match(for: target("aa-bb-cc-dd-ee-ff-zz"))?.address == "192.0.2.77")
    #expect(snapshot("\u{FF21}\u{FF22}").match(for: target("\u{FF41}\u{FF42}"))?.address == "192.0.2.77")
    #expect(snapshot("AB").match(for: target("\u{FF41}\u{FF42}")) == nil)
    #expect(snapshot("AABBCCDDEEFF").match(for: target("aabbccddeef0")) == nil)
}
