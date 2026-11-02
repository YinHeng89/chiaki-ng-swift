import ChiakiClients
import ChiakiModels

/// One live stream: the player it owns, the relay that reports it, and the lease it holds.
///
/// A launcher prepares the player, then calls ``run(rest:_:)`` with the native start. The session presents the
/// player's surface, connects its handlers through the ``PlayerEventRelay``, binds its stops to the lease and
/// waits for the native completion. Commands such as ``submit(_:for:)`` reach the player only while the
/// session is live.
@MainActor
public final class LiveStreamSession {
    /// The session's id, which is also its lease.
    public let id: StreamSessionID

    /// The player the session owns.
    public let player: any StreamPlayer

    /// The relay that reports the session.
    public let relay: PlayerEventRelay

    private let leases: StreamLeases

    /// Creates a session for a player.
    ///
    /// - Parameters:
    ///   - id: The session's id; it must already hold the lease.
    ///   - player: The player.
    ///   - leases: The lease the session holds.
    ///   - continuation: Where the session's events go.
    public init(
        id: StreamSessionID,
        player: any StreamPlayer,
        leases: StreamLeases,
        continuation: AsyncThrowingStream<StreamSessionEvent, any Error>.Continuation
    ) {
        self.id = id
        self.player = player
        self.leases = leases
        relay = PlayerEventRelay(session: id, continuation: continuation)
        leases.attach(self)
    }

    /// Whether the session still holds a live lease.
    public var isLive: Bool {
        leases.acceptsEvents(id) && relay.isOpen
    }

    /// Reports an event the launcher produced.
    ///
    /// - Parameter event: The event.
    public func report(_ event: StreamSessionEvent) {
        relay.report(event)
    }

    /// Runs the player from its start until the native completion.
    ///
    /// - Parameters:
    ///   - rest: Whether the stream can put the console in rest mode when it stops.
    ///   - start: Starts the native stream and calls its argument once, when the stream has ended.
    /// - Returns: The native ending, or `nil` when the session was stopped before the player could start.
    public func run<Ending: Sendable>(
        rest: Bool,
        _ start: (@escaping @Sendable (Ending) -> Void) -> Void
    ) async -> Ending? {
        player.connect { [relay] signal in
            relay.receive(signal)
        }
        relay.report(.presented(player.surface))
        defer {
            player.disconnect()
            relay.close()
        }
        guard bindStops(rest: rest) else {
            return nil
        }
        let ending: Ending = await withCheckedContinuation { continuation in
            start { ending in
                continuation.resume(returning: ending)
            }
        }
        if player.restRefused {
            leases.noteRestRefused(id)
        }
        return ending
    }

    /// Sends a code the console asked for.
    ///
    /// - Parameters:
    ///   - code: The code.
    ///   - prompt: The prompt it answers.
    /// - Returns: Whether the console accepted or was sent it; `false` once the session is not live.
    public func submit(_ code: StreamAccessCode, for prompt: StreamAccessPrompt) async -> Bool {
        guard isLive else {
            return false
        }
        switch prompt {
        case .loginPIN:
            return await player.submitLoginPIN(code)
        case .controllerPasscode(let pad, _):
            return player.submitControllerPasscode(code, pad: pad)
        }
    }

    /// Asks the console to show its home screen.
    ///
    /// - Returns: Whether the request was sent.
    public func goHome() -> Bool {
        isLive && player.goHome()
    }

    /// Sends a change to the console's on-screen keyboard.
    ///
    /// - Parameter command: The change.
    /// - Returns: Whether it was sent.
    public func send(_ command: ConsoleKeyboardCommand) -> Bool {
        isLive && player.send(command)
    }

    /// Chooses an offered cloud datacenter.
    ///
    /// - Parameter name: The datacenter's name.
    /// - Returns: Whether the core took it.
    public func selectDatacenter(_ name: String) -> Bool {
        isLive && player.selectDatacenter(name)
    }

    /// Applies picture and sound settings the stream menu changed.
    ///
    /// - Parameter tuning: The settings.
    public func apply(_ tuning: StreamTuningConfiguration) {
        guard isLive else {
            return
        }
        player.apply(tuning)
    }

    private func bindStops(rest: Bool) -> Bool {
        let player = player
        let relay = relay
        let stop: (@escaping @MainActor () -> Void) -> StreamLeases.Stop = { native in
            {
                relay.close()
                native()
            }
        }
        return leases.bind(
            id,
            stop: stop(player.stop),
            sleep: stop(player.stopForSleep),
            rest: rest
                ? stop(player.stopWithRest)
                : nil,
            sleepRest: rest
                ? stop(player.stopForSleepWithRest)
                : nil
        )
    }
}
