import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiModels
import Foundation
import Testing

@MainActor @Test func theLeaseWaitsForCleanupBeforeAnotherSessionCanStart() async throws {
    let leases = StreamLeases()
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    let started = AsyncStream<Void>.makeStream()
    var observed = started.stream.makeAsyncIterator()
    var stops = 0
    let bound = leases.bind(id) {
        stops += 1
        started.continuation.yield()
    }
    #expect(bound)
    #expect(await leases.stop(StreamSessionID()) == .left)
    #expect(stops == 0 && leases.acceptsEvents(id))
    let closing = Task {
        await leases.stop(id)
    }
    await observed.next()
    #expect(stops == 1)
    #expect(!leases.acceptsEvents(id))
    #expect(!leases.acquire(StreamSessionID(), kind: .cloud))
    let rebound = leases.bind(id) {}
    #expect(!rebound)
    leases.release(StreamSessionID())
    #expect(!leases.acquire(StreamSessionID(), kind: .cloud))
    leases.release(id)
    _ = await closing.value
    let next = StreamSessionID()
    #expect(leases.acquire(next, kind: .guest))
    leases.release(id)
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
    leases.release(next)
}

@MainActor @Test func shutdownStopsTheSessionAndRefusesNewOnes() async throws {
    let leases = StreamLeases()
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    let started = AsyncStream<Void>.makeStream()
    var observed = started.stream.makeAsyncIterator()
    var stops = 0
    let bound = leases.bind(id) {
        stops += 1
        started.continuation.yield()
    }
    #expect(bound)
    let terminating = Task {
        await leases.shutdown(within: .seconds(30))
    }
    await observed.next()
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
    leases.release(id)
    #expect(await terminating.value)
    #expect(stops == 1)
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
}

@MainActor @Test func shutdownGivesUpWaitingAfterTheLimitAndStillRefusesNewSessions() async throws {
    let leases = StreamLeases()
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    var stops = 0
    let bound = leases.bind(id) {
        stops += 1
    }
    #expect(bound)
    #expect(!(await leases.shutdown(within: .milliseconds(20))))
    #expect(stops == 1)
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
    #expect(!(await leases.shutdown(within: .milliseconds(20))))
    #expect(stops == 1)
    leases.release(id)
    #expect(await leases.shutdown(within: .milliseconds(20)))
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
}

@MainActor @Test func shutdownWithNothingRunningReturnsAtOnceAndRefusesNewSessions() async throws {
    let leases = StreamLeases()
    #expect(await leases.shutdown(within: .seconds(30)))
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
}

@MainActor @Test func shutdownTakesOverASessionAlreadyStoppingForSleep() async throws {
    let leases = StreamLeases()
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    var calls: [String] = []
    let bound = leases.bind(id, stop: { calls.append("stop") }, sleep: { calls.append("sleep") })
    #expect(bound)
    #expect(leases.stopForSleep())
    #expect(!(await leases.shutdown(within: .milliseconds(20))))
    #expect(calls == ["sleep"])
    leases.release(id)
    #expect(!leases.acquire(StreamSessionID(), kind: .console))
}

@MainActor @Test func aSessionStoppedBeforeItStartsCannotBindItsPlayer() async throws {
    let leases = StreamLeases()
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    #expect(leases.stopForSleep())
    let bound = leases.bind(id) {}
    #expect(!bound)
    leases.release(id)
    #expect(leases.acquire(StreamSessionID(), kind: .console))
}

@MainActor @Test func sleepUsesTheSleepStopsAndRestOnlyWhenOffered() async throws {
    let leases = StreamLeases()
    var calls: [String] = []
    let resting = StreamSessionID()
    #expect(leases.acquire(resting, kind: .console))
    let restBound = leases.bind(
        resting,
        stop: { calls.append("stop") },
        sleep: { calls.append("sleep") },
        sleepRest: { calls.append("sleep rest") }
    )
    #expect(restBound)
    #expect(leases.stopForSleep(rest: true))
    #expect(!leases.stopForSleep())
    leases.release(resting)
    let plain = StreamSessionID()
    #expect(leases.acquire(plain, kind: .cloud))
    let plainBound = leases.bind(plain, stop: { calls.append("stop") }, sleep: { calls.append("sleep") })
    #expect(plainBound)
    #expect(leases.stopForSleep(rest: true))
    leases.release(plain)
    #expect(calls == ["sleep rest", "sleep"])
}

@MainActor @Test func aRestExitWithoutARestStopIsReportedAsRefused() async throws {
    let leases = StreamLeases()
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .cloud))
    let started = AsyncStream<Void>.makeStream()
    var observed = started.stream.makeAsyncIterator()
    let bound = leases.bind(id) {
        started.continuation.yield()
    }
    #expect(bound)
    let closing = Task {
        await leases.stop(id, exit: .restMode)
    }
    await observed.next()
    leases.release(id)
    #expect(await closing.value == .restRefused)
}

@MainActor @Test func theActivityLastsFromAcquireUntilRelease() async throws {
    var held = 0
    var released = 0
    let leases = StreamLeases {
        held += 1
        return {
            released += 1
        }
    }
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    #expect(held == 1 && released == 0)
    leases.release(StreamSessionID())
    #expect(released == 0)
    leases.release(id)
    leases.release(id)
    #expect(released == 1)
}

@MainActor @Test func waitingForReleaseEndsOnReleaseOrAfterTheLimit() async throws {
    let leases = StreamLeases()
    #expect(await leases.waitUntilReleased(within: .milliseconds(10)))
    let id = StreamSessionID()
    #expect(leases.acquire(id, kind: .console))
    #expect(leases.stopForSleep())
    #expect(!(await leases.waitUntilReleased(within: .milliseconds(20))))
    let waiting = Task {
        await leases.waitUntilReleased(within: .seconds(30))
    }
    await Task.yield()
    leases.release(id)
    #expect(await waiting.value)
}
