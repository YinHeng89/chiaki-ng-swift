import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures
@testable import ChiakiClientsLive
@testable import ChiakiNG

private func operation(_ value: Int) -> OperationID {
    OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
}

private let den = DiscoveredConsole(
    id: "AABBCCDDEEFF", name: "Den", address: "192.0.2.4", kind: .ps5, standby: false
)

private final class Subscriptions: Sendable {
    let continuations = LockIsolated<[AsyncStream<ConsoleScanEvent>.Continuation]>([])

    var events: @Sendable () async -> AsyncStream<ConsoleScanEvent> {
        { [continuations] in
            let (stream, continuation) = AsyncStream.makeStream(of: ConsoleScanEvent.self)
            continuations.withValue {
                $0.append(continuation)
            }
            return stream
        }
    }
}

@MainActor @Test func leasesShareOneSubscriptionUntilTheLastIsReleased() async {
    let subscriptions = Subscriptions()
    let store = TestStore(initialState: DiscoveryFeature.State()) {
        DiscoveryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.scanEvents = subscriptions.events
        $0.continuousClock = TestClock()
    }
    await store.send(.acquire(.library)) {
        $0.leases = [.library]
        $0.phase = .scanning(operation(0))
    }
    let snapshot = DiscoverySnapshot(consoles: [den], networkAvailable: true)
    while subscriptions.continuations.value.isEmpty {
        await Task.yield()
    }
    subscriptions.continuations.value[0].yield(.snapshot(snapshot))
    await store.receive(.scanned(operation(0), .snapshot(snapshot))) {
        $0.snapshot = snapshot
        $0.phase = .listening(operation(0))
    }
    await store.receive(.delegate(.updated(snapshot)))
    await store.send(.acquire(.autoConnect)) {
        $0.leases = [.library, .autoConnect]
    }
    await store.receive(.delegate(.updated(snapshot)))
    await store.receive(.delegate(.searched(false)))
    await store.send(.release(.library)) {
        $0.leases = [.autoConnect]
    }
    #expect(subscriptions.continuations.value.count == 1)
    await store.send(.release(.autoConnect)) {
        $0.leases = []
        $0.phase = .idle
        $0.snapshot = DiscoverySnapshot()
    }
}

@MainActor @Test func aFailedScanStopsUntilRetriedAndIgnoresStaleEvents() async {
    let subscriptions = Subscriptions()
    let store = TestStore(initialState: DiscoveryFeature.State()) {
        DiscoveryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.scanEvents = subscriptions.events
    }
    await store.send(.acquire(.addConsole)) {
        $0.leases = [.addConsole]
        $0.phase = .scanning(operation(0))
    }
    await store.send(.scanned(operation(5), .failed))
    await store.send(.scanned(operation(0), .failed)) {
        $0.phase = .failed
    }
    await store.receive(.delegate(.failed))
    await store.send(.retry) {
        $0.phase = .scanning(operation(1))
    }
    await store.send(.stop) {
        $0.leases = []
        $0.phase = .idle
    }
}

@Test func subscribersShareOneScanThatStopsWithTheLast() async {
    let scans = LockIsolated(0)
    let feed = AsyncThrowingStream<DiscoverySnapshot, Error>.makeStream()
    let scanner = SharedConsoleScanner(
        scan: { _ in
            scans.withValue {
                $0 += 1
            }
            return feed.stream
        },
        settings: {
            DiscoverySettings()
        },
        cache: { _, _ in
            false
        },
        catalogChanged: {},
        clock: TestClock()
    )
    let first = await scanner.events()
    let second = await scanner.events()
    let snapshot = DiscoverySnapshot(consoles: [den], networkAvailable: true)
    while scans.value == 0 {
        await Task.yield()
    }
    feed.continuation.yield(snapshot)
    var firstIterator = first.makeAsyncIterator()
    var secondIterator = second.makeAsyncIterator()
    #expect(await firstIterator.next() == .snapshot(snapshot))
    #expect(await secondIterator.next() == .snapshot(snapshot))
    #expect(scans.value == 1)
    #expect(await scanner.subscriberCount == 2)
}

@Test func anAddressSavedByAnyScanTellsTheCatalog() async {
    let changes = LockIsolated(0)
    let feed = AsyncThrowingStream<DiscoverySnapshot, Error>.makeStream()
    let scanner = SharedConsoleScanner(
        scan: { _ in
            feed.stream
        },
        settings: {
            DiscoverySettings()
        },
        cache: { consoles, reported in
            consoles == [den] && reported == [den.id]
        },
        catalogChanged: {
            changes.withValue {
                $0 += 1
            }
        },
        clock: TestClock()
    )
    let events = await scanner.events()
    var iterator = events.makeAsyncIterator()
    try? await Task.sleep(for: .milliseconds(20))
    feed.continuation.yield(DiscoverySnapshot(consoles: [den], networkAvailable: true))
    _ = await iterator.next()
    while changes.value == 0 {
        await Task.yield()
    }
    #expect(changes.value == 1)
}

@Test func aScanThatEndsIsReportedAsFailed() async {
    let scanner = SharedConsoleScanner(
        scan: { _ in
            AsyncThrowingStream {
                $0.finish()
            }
        },
        settings: {
            DiscoverySettings()
        },
        cache: { _, _ in
            false
        },
        catalogChanged: {},
        clock: TestClock()
    )
    let events = await scanner.events()
    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() == .failed)
}

@MainActor @Test func theLibraryLeaseSharesTheScanWithOtherHolders() async {
    let subscriptions = Subscriptions()
    let store = TestStore(initialState: DiscoveryFeature.State()) {
        DiscoveryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.scanEvents = subscriptions.events
    }
    await store.send(.acquire(.library)) {
        $0.leases = [.library]
        $0.phase = .scanning(operation(0))
    }
    await store.send(.acquire(.addConsole)) {
        $0.leases = [.library, .addConsole]
    }
    await store.receive(.delegate(.updated(DiscoverySnapshot())))
    await store.receive(.delegate(.searched(false)))
    await store.send(.release(.library)) {
        $0.leases = [.addConsole]
    }
    await store.send(.release(.addConsole)) {
        $0.leases = []
        $0.phase = .idle
    }
}

@MainActor @Test func discoveryCountsAsSearchedOnlyAfterAWindowWithANetwork() async {
    let subscriptions = Subscriptions()
    let clock = TestClock()
    let store = TestStore(initialState: DiscoveryFeature.State()) {
        DiscoveryFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.scanEvents = subscriptions.events
        $0.continuousClock = clock
    }
    store.exhaustivity = .off
    let id = operation(0)
    await store.send(.acquire(.library)) {
        $0.phase = .scanning(id)
    }
    while subscriptions.continuations.value.isEmpty {
        await Task.yield()
    }
    await clock.advance(by: DiscoveryFeature.searchWindow * 2)
    #expect(store.state.phase == .scanning(id))
    let offline = DiscoverySnapshot(networkAvailable: false)
    subscriptions.continuations.value[0].yield(.snapshot(offline))
    await store.receive(.scanned(id, .snapshot(offline)))
    #expect(store.state.phase == .scanning(id))
    let online = DiscoverySnapshot(networkAvailable: true)
    subscriptions.continuations.value[0].yield(.snapshot(online))
    await store.receive(.scanned(id, .snapshot(online))) {
        $0.phase = .listening(id)
    }
    await clock.advance(by: DiscoveryFeature.searchWindow)
    await store.receive(.searchWindowElapsed(id)) {
        $0.phase = .searched(id)
    }
    await store.receive(.delegate(.searched(true)))
    await store.send(.searchWindowElapsed(operation(9)))
    #expect(store.state.phase == .searched(id))
    subscriptions.continuations.value[0].yield(.snapshot(offline))
    await store.receive(.scanned(id, .snapshot(offline))) {
        $0.phase = .scanning(id)
    }
    await store.receive(.delegate(.searched(false)))
    await store.send(.stop) {
        $0.leases = []
        $0.phase = .idle
        $0.snapshot = DiscoverySnapshot()
    }
}

@Test func aConsoleIsOnlyNotNearbyOnceDiscoveryHasSearched() {
    let console = RegistrationFlow.ConsoleTarget(address: "192.168.1.20", kind: .ps5)
    let empty = DiscoverySnapshot(networkAvailable: true)
    #expect(ConsolePresence.of(console, in: empty, searched: false) == .unknown)
    #expect(ConsolePresence.of(console, in: empty, searched: true) == .notNearby)
    #expect(LibraryDiscovery.watching(empty).hasSearched == false)
    #expect(LibraryDiscovery.failed(empty).hasSearched == false)
    #expect(LibraryDiscovery.searched(empty).hasSearched)
}

@MainActor @Test func theLibraryFollowsWhetherDiscoverySearched() async {
    var state = LibraryFeature.State(section: .consoles)
    state.discovery = .watching(DiscoverySnapshot())
    let store = TestStore(initialState: state) {
        LibraryFeature()
    }
    let online = DiscoverySnapshot(networkAvailable: true)
    await store.send(.discoverySearched(true)) {
        $0.discovery = .searched(DiscoverySnapshot())
    }
    await store.send(.discoveryUpdated(online)) {
        $0.discovery = .searched(online)
    }
    await store.send(.discoverySearched(false)) {
        $0.discovery = .watching(online)
    }
}

private func scannerHoldingItsFirstSettingsRead(
    _ pendingRead: LockIsolated<CheckedContinuation<Void, Never>?>,
    scans: LockIsolated<Int>,
    stoppedScans: LockIsolated<Int>
) -> SharedConsoleScanner {
    let reads = LockIsolated(0)
    return SharedConsoleScanner(
        scan: { _ in
            scans.withValue {
                $0 += 1
            }
            return AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in
                    stoppedScans.withValue {
                        $0 += 1
                    }
                }
            }
        },
        settings: {
            let read = reads.withValue {
                $0 += 1
                return $0
            }
            if read == 1 {
                await withCheckedContinuation { continuation in
                    pendingRead.setValue(continuation)
                }
                throw CancellationError()
            }
            return DiscoverySettings()
        },
        cache: { _, _ in
            false
        },
        catalogChanged: {},
        clock: TestClock()
    )
}

@Test func aCancelledScansLateSettingsFailureLeavesTheNextScanRunning() async {
    let pendingRead = LockIsolated<CheckedContinuation<Void, Never>?>(nil)
    let scans = LockIsolated(0)
    let stoppedScans = LockIsolated(0)
    let scanner = scannerHoldingItsFirstSettingsRead(pendingRead, scans: scans, stoppedScans: stoppedScans)
    let firstEvents = await scanner.events()
    let first = Task {
        for await _ in firstEvents {
        }
    }
    while pendingRead.value == nil {
        await Task.yield()
    }
    first.cancel()
    while await scanner.subscriberCount > 0 {
        await Task.yield()
    }
    let secondEvents = await scanner.events()
    let received = LockIsolated<[ConsoleScanEvent]>([])
    let second = Task {
        for await event in secondEvents {
            received.withValue {
                $0.append(event)
            }
        }
    }
    while scans.value == 0 {
        await Task.yield()
    }
    pendingRead.value?.resume()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(!received.value.contains(.failed))
    second.cancel()
    for _ in 0..<200 where stoppedScans.value == 0 {
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(stoppedScans.value == 1)
}
