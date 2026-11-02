import ChiakiClients
import ChiakiModels
import Dependencies
import Foundation

/// The one native stream lease, keyed by the `ChiakiModels/StreamSessionID` of the session that holds it.
///
/// Only one stream may use the native player at a time. A session acquires the lease with its own id before
/// it touches the player, binds the stops the player offers once it starts, and releases the lease when the
/// player has closed. Stopping, sleeping and quitting go through the lease, so they reach whichever session is
/// live and wait until its player has really closed.
///
/// ```
/// idle --acquire--> active --stop / stopForSleep--> stopping --release--> idle
/// active, stopping --shutdown--> terminating --release--> terminated
/// idle --shutdown--> terminated
/// terminating --shutdown limit passes--> terminating (the app quits anyway)
/// ```
@MainActor
public final class StreamLeases {
    /// A stop the player offers.
    public typealias Stop = @MainActor () -> Void

    private struct Lease {
        let id: StreamSessionID
        let kind: StreamKind
        var stop: Stop?
        var sleep: Stop?
        var rest: Stop?
        var sleepRest: Stop?
        var session: LiveStreamSession?
        var restRefused = false
        var restInFlight = false

        var outcome: StreamExitOutcome {
            restRefused
                ? .restRefused
                : .left
        }
    }

    private typealias Waiter = CheckedContinuation<StreamExitOutcome, Never>

    private enum State {
        case idle
        case active(Lease)
        case stopping(Lease, [Waiter])
        case terminating(Lease, [Waiter])
        case terminated
    }

    private var state = State.idle
    private var releaseWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private let activity: @MainActor () -> Stop
    private var endActivity: Stop?

    /// Creates the lease.
    ///
    /// - Parameter activity: Starts whatever must last while a stream holds the lease, such as keeping the
    ///   display awake, and returns how to end it.
    public nonisolated init(activity: @escaping @MainActor () -> Stop = {
        {}
    }) {
        self.activity = activity
    }

    /// The live session, while one holds the lease and has not started stopping.
    public var current: LiveStreamSession? {
        if case .active(let lease) = state {
            return lease.session
        }
        return nil
    }

    /// The live session with the given id.
    ///
    /// - Parameter id: A session id.
    /// - Returns: The session, or `nil` when `id` does not hold the lease or is stopping.
    public func session(_ id: StreamSessionID) -> LiveStreamSession? {
        guard case .active(let lease) = state, lease.id == id else {
            return nil
        }
        return lease.session
    }

    /// Takes the lease for a new session.
    ///
    /// - Parameters:
    ///   - id: The session's id.
    ///   - kind: What the session streams.
    /// - Returns: `true` when no other session held the lease and the app is not quitting.
    public func acquire(_ id: StreamSessionID, kind: StreamKind) -> Bool {
        guard case .idle = state else {
            return false
        }
        state = .active(Lease(id: id, kind: kind))
        endActivity = activity()
        return true
    }

    /// Records the live session that holds the lease, so commands can reach it.
    ///
    /// - Parameter session: The session.
    /// - Returns: `true` when the session's id holds the lease.
    @discardableResult
    public func attach(_ session: LiveStreamSession) -> Bool {
        guard case .active(var lease) = state, lease.id == session.id else {
            return false
        }
        lease.session = session
        state = .active(lease)
        return true
    }

    /// Records the stops the player offers once it starts.
    ///
    /// - Parameters:
    ///   - id: The session.
    ///   - stop: The normal stop.
    ///   - sleep: The stop used when the computer sleeps.
    ///   - rest: The stop that also puts the console in rest mode.
    ///   - sleepRest: The sleep stop that also puts the console in rest mode.
    /// - Returns: `false` when the session no longer holds an active lease, so the player must not start.
    public func bind(
        _ id: StreamSessionID,
        stop: @escaping Stop,
        sleep: Stop? = nil,
        rest: Stop? = nil,
        sleepRest: Stop? = nil
    ) -> Bool {
        guard case .active(var lease) = state, lease.id == id else {
            return false
        }
        lease.stop = stop
        lease.sleep = sleep
        lease.rest = rest
        lease.sleepRest = sleepRest
        state = .active(lease)
        return true
    }

    /// Gives the lease back once the session's player has closed.
    ///
    /// - Parameter id: The session.
    public func release(_ id: StreamSessionID) {
        switch state {
        case .active(let lease) where lease.id == id:
            state = .idle
            finishActivity()
        case .stopping(let lease, let waiters) where lease.id == id:
            state = .idle
            finishActivity()
            for waiter in waiters {
                waiter.resume(returning: lease.outcome)
            }
        case .terminating(let lease, let waiters) where lease.id == id:
            state = .terminated
            finishActivity()
            for waiter in waiters {
                waiter.resume(returning: lease.outcome)
            }
        case .idle, .active, .stopping, .terminating, .terminated:
            break
        }
    }

    /// Waits until no session holds the lease.
    ///
    /// - Parameters:
    ///   - limit: How long to wait at most.
    ///   - clock: The clock the limit is measured on.
    /// - Returns: `true` when the lease was released within the limit.
    public func waitUntilReleased(
        within limit: Duration,
        clock: any Clock<Duration> = ContinuousClock()
    ) async -> Bool {
        switch state {
        case .idle, .terminated:
            return true
        case .active, .stopping, .terminating:
            break
        }
        let id = UUID()
        let timeout = Task { @MainActor [weak self] in
            try? await clock.sleep(for: limit)
            self?.releaseWaiters.removeValue(forKey: id)?.resume(returning: false)
        }
        let released = await withCheckedContinuation { continuation in
            releaseWaiters[id] = continuation
        }
        timeout.cancel()
        return released
    }

    /// Records that the console refused to enter rest mode for a session.
    ///
    /// - Parameter id: The session.
    public func noteRestRefused(_ id: StreamSessionID) {
        switch state {
        case .active(var lease) where lease.id == id:
            lease.restRefused = true
            state = .active(lease)
        case .stopping(var lease, let waiters) where lease.id == id:
            lease.restRefused = true
            state = .stopping(lease, waiters)
        case .terminating(var lease, let waiters) where lease.id == id:
            lease.restRefused = true
            state = .terminating(lease, waiters)
        case .idle, .active, .stopping, .terminating, .terminated:
            break
        }
    }

    /// Whether events from a session should still be delivered.
    ///
    /// - Parameter id: The session.
    /// - Returns: `true` while `id` holds an active lease that is not stopping.
    public func acceptsEvents(_ id: StreamSessionID) -> Bool {
        if case .active(let lease) = state {
            return lease.id == id
        }
        return false
    }

    /// Stops a session and waits until its player has closed.
    ///
    /// - Parameters:
    ///   - id: The session to stop, or `nil` for whichever holds the lease.
    ///   - exit: How the user leaves.
    /// - Returns: What happened to the console; `ChiakiModels/StreamExitOutcome/left` when nothing was
    ///   running or `id` does not hold the lease.
    @discardableResult
    public func stop(_ id: StreamSessionID? = nil,
                     exit: StreamExitAction = .disconnect) async -> StreamExitOutcome {
        if let id {
            switch state {
            case .active(let lease), .stopping(let lease, _), .terminating(let lease, _):
                guard lease.id == id else {
                    return .left
                }
            case .idle, .terminated:
                return .left
            }
        }
        return await waitForRelease(exit: exit)
    }

    /// Stops the live session because the computer is going to sleep, without waiting.
    ///
    /// - Parameter rest: Whether the console should also go to rest mode.
    /// - Returns: `true` when a session was stopped.
    public func stopForSleep(rest: Bool = false) -> Bool {
        guard case .active(let lease) = state else {
            return false
        }
        var stopping = lease
        let restStop = rest
            ? lease.sleepRest
            : nil
        if rest, restStop == nil {
            stopping.restRefused = true
        }
        stopping.restInFlight = restStop != nil
        state = .stopping(stopping, [])
        (restStop ?? lease.sleep ?? lease.stop)?()
        return true
    }

    /// Stops any session and refuses every later stream, waiting at most `limit` for its player to close.
    ///
    /// The app quits after this returns whether or not the player closed, so a native session that never
    /// finishes cannot hold up quitting.
    ///
    /// - Parameters:
    ///   - limit: How long to wait at most.
    ///   - clock: The clock the limit is measured on.
    /// - Returns: `true` when no session was running or its player closed within the limit.
    public func shutdown(within limit: Duration,
                         clock: any Clock<Duration> = ContinuousClock()) async -> Bool {
        switch state {
        case .idle:
            state = .terminated
            return true
        case .terminated:
            return true
        case .active(var lease):
            lease.restInFlight = false
            state = .terminating(lease, [])
            lease.stop?()
        case .stopping(let lease, let waiters):
            state = .terminating(lease, waiters)
        case .terminating:
            break
        }
        return await waitUntilReleased(within: limit, clock: clock)
    }

    private func waitForRelease(exit: StreamExitAction) async -> StreamExitOutcome {
        await withCheckedContinuation { continuation in
            switch state {
            case .idle, .terminated:
                continuation.resume(returning: .left)
            case .active(var lease):
                let rest = exit == .restMode
                    ? lease.rest
                    : nil
                if exit == .restMode, rest == nil {
                    lease.restRefused = true
                }
                lease.restInFlight = rest != nil
                state = .stopping(lease, [continuation])
                if let rest {
                    rest()
                } else {
                    lease.stop?()
                }
            case .stopping(var lease, var waiters):
                if exit == .restMode, !lease.restInFlight {
                    lease.restRefused = true
                }
                waiters.append(continuation)
                state = .stopping(lease, waiters)
            case .terminating(let lease, var waiters):
                waiters.append(continuation)
                state = .terminating(lease, waiters)
            }
        }
    }

    private func finishActivity() {
        let end = endActivity
        endActivity = nil
        end?()
        let waiters = releaseWaiters
        releaseWaiters = [:]
        for waiter in waiters.values {
            waiter.resume(returning: true)
        }
    }
}

private enum StreamLeasesKey: TestDependencyKey {
    static var testValue: StreamLeases {
        StreamLeases()
    }
}

extension DependencyValues {
    /// The one native stream lease; the composition root installs one that keeps the display awake.
    public var streamLeases: StreamLeases {
        get {
            self[StreamLeasesKey.self]
        }
        set {
            self[StreamLeasesKey.self] = newValue
        }
    }
}
