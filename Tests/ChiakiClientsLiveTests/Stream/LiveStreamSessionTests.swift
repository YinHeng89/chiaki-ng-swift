import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiModels
import Foundation
import Testing

private let console = StreamSource.console(
    ConsoleStreamTarget(profile: ProfileID(), console: nil, address: "10.0.0.2", kind: .ps5),
    route: .home
)

@MainActor
private func collect(
    _ iterator: inout AsyncThrowingStream<StreamSessionEvent, any Error>.AsyncIterator
) async -> (events: [StreamSessionEvent], failure: (any Error)?) {
    var events: [StreamSessionEvent] = []
    do {
        while let event = try await iterator.next(isolation: MainActor.shared) {
            events.append(event)
        }
        return (events, nil)
    } catch {
        return (events, error)
    }
}

@MainActor @Test func liveSessionReportsPlayerSignalsInOrderAndEndsWithThePlayer() async throws {
    let launcher = FakeStreamLauncher()
    let client = StreamSessionClient.live(leases: StreamLeases(), launcher: launcher)
    let id = StreamSessionID()
    var iterator = client.start(id, console).makeAsyncIterator()
    #expect(try await iterator.next() == .presented(launcher.player.surface))
    await launcher.waitUntilRunning()
    launcher.player.fire(.event(.startRetried(attempt: 1)))
    launcher.player.fire(.event(.firstFrame))
    launcher.player.fire(.gameLight(pad: 1, color: 0xFF0000))
    launcher.player.fire(.event(.firstFrame))
    launcher.player.fire(.event(.reconnecting(attempt: 1)))
    launcher.player.fire(.event(.reconnected))
    launcher.player.end()
    let rest = await collect(&iterator)
    #expect(rest.failure == nil)
    #expect(rest.events == [.startRetried(attempt: 1), .firstFrame, .reconnecting(attempt: 1), .reconnected])
    #expect(launcher.observed.contains(.gameLight(pad: 1, color: 0xFF0000)))
    #expect(launcher.observed.filter { $0 == .event(.firstFrame) }.count == 1)
}

@MainActor @Test func leavingIsTerminalForTheSessionsEventsAndInput() async throws {
    let launcher = FakeStreamLauncher()
    let client = StreamSessionClient.live(leases: StreamLeases(), launcher: launcher)
    let id = StreamSessionID()
    var iterator = client.start(id, console).makeAsyncIterator()
    _ = try await iterator.next()
    await launcher.waitUntilRunning()
    let relay = try #require(launcher.session?.relay)
    #expect(await client.leave(id, .disconnect) == .left)
    relay.receive(.event(.firstFrame))
    let rest = await collect(&iterator)
    #expect(rest.events.isEmpty)
    #expect(!launcher.observed.contains(.event(.firstFrame)))
    #expect(launcher.player.calls == ["start", "stop"])
    #expect(!launcher.player.connected)
}

@MainActor @Test func leavingWithRestReportsTheConsolesRefusal() async throws {
    let launcher = FakeStreamLauncher()
    launcher.player.restRefused = true
    let client = StreamSessionClient.live(leases: StreamLeases(), launcher: launcher)
    let id = StreamSessionID()
    var iterator = client.start(id, console).makeAsyncIterator()
    _ = try await iterator.next()
    await launcher.waitUntilRunning()
    #expect(await client.leave(id, .restMode) == .restRefused)
    #expect(launcher.player.calls == ["start", "rest"])
}

@MainActor @Test func aSecondSessionIsRefusedWhileTheFirstHoldsTheLease() async throws {
    let launcher = FakeStreamLauncher()
    let client = StreamSessionClient.live(leases: StreamLeases(), launcher: launcher)
    let first = StreamSessionID()
    var iterator = client.start(first, console).makeAsyncIterator()
    _ = try await iterator.next()
    await launcher.waitUntilRunning()
    var second = client.start(StreamSessionID(), console).makeAsyncIterator()
    let refused = await collect(&second)
    #expect(refused.failure as? StreamFailure == .busy)
    #expect(launcher.launched == 1)
    launcher.player.end()
    _ = await collect(&iterator)
}

@MainActor @Test func commandsReachOnlyTheLiveSession() async throws {
    let launcher = FakeStreamLauncher()
    let client = StreamSessionClient.live(leases: StreamLeases(), launcher: launcher)
    let id = StreamSessionID()
    var iterator = client.start(id, console).makeAsyncIterator()
    _ = try await iterator.next()
    await launcher.waitUntilRunning()
    let code = try #require(StreamAccessCode("1234"))
    #expect(!(await client.goHome(StreamSessionID())))
    #expect(await client.goHome(id))
    #expect(await client.submitAccessCode(id, .loginPIN(retry: false), code))
    #expect(await client.selectDatacenter(id, "Tokyo"))
    await client.tune(id, StreamTuningConfiguration())
    launcher.player.end()
    _ = await collect(&iterator)
    #expect(!(await client.goHome(id)))
    #expect(launcher.player.calls == ["start", "home", "pin 1234", "datacenter Tokyo", "tune"])
}

@MainActor @Test func aLauncherFailureFailsTheEventStream() async throws {
    let launcher = FakeStreamLauncher()
    launcher.failure = .stream(.finished, overInternet: false)
    let client = StreamSessionClient.live(leases: StreamLeases(), launcher: launcher)
    var iterator = client.start(StreamSessionID(), console).makeAsyncIterator()
    _ = try await iterator.next()
    await launcher.waitUntilRunning()
    launcher.player.end(3)
    let rest = await collect(&iterator)
    #expect(rest.failure as? StreamFailure == .stream(.finished, overInternet: false))
}

@MainActor @Test func cancellingTheEventStreamStopsTheSession() async throws {
    let leases = StreamLeases()
    let launcher = FakeStreamLauncher()
    let client = StreamSessionClient.live(leases: leases, launcher: launcher)
    let id = StreamSessionID()
    let events = client.start(id, console)
    let listening = Task {
        for try await _ in events {
        }
    }
    await launcher.waitUntilRunning()
    listening.cancel()
    #expect(await leases.waitUntilReleased(within: .seconds(5)))
    #expect(launcher.player.calls == ["start", "stop"])
}

@MainActor @Test func theRelayDropsSignalsOnceClosed() {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: StreamSessionEvent.self)
    _ = stream
    let relay = PlayerEventRelay(session: StreamSessionID(), continuation: continuation)
    var seen: [PlayerSignal] = []
    relay.observe { seen.append($0) }
    relay.receive(.event(.firstFrame))
    relay.close()
    relay.receive(.event(.reconnected))
    relay.report(.videoDisabled(true))
    #expect(seen == [.event(.firstFrame)])
    #expect(!relay.isOpen)
}
