import ChiakiClients
import ChiakiModels

/// Turns one session's player signals into one ordered event stream.
///
/// Signals arrive on the main actor in the order the player fired them and are yielded straight into the
/// session's continuation, with no task per signal, so their order is kept. The session's input sees every
/// signal first through its observer. Once the relay is closed, because the session is stopping or has ended,
/// nothing more is delivered, so a late handler cannot move the next session.
@MainActor
public final class PlayerEventRelay {
    /// The session the events belong to.
    public let session: StreamSessionID

    private let continuation: AsyncThrowingStream<StreamSessionEvent, any Error>.Continuation
    private var observers: [@MainActor (PlayerSignal) -> Void] = []
    private var open = true
    private var framed = false

    /// Creates a relay for one session.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - continuation: Where the session's events go.
    public init(
        session: StreamSessionID,
        continuation: AsyncThrowingStream<StreamSessionEvent, any Error>.Continuation
    ) {
        self.session = session
        self.continuation = continuation
    }

    /// Whether signals are still delivered.
    public var isOpen: Bool {
        open
    }

    /// Adds an observer that sees every signal before it becomes an event, such as the session's input.
    ///
    /// - Parameter observer: Called on the main actor for each delivered signal.
    public func observe(_ observer: @escaping @MainActor (PlayerSignal) -> Void) {
        observers.append(observer)
    }

    /// Delivers one signal from the player.
    ///
    /// Only the first `ChiakiModels/StreamSessionEvent/firstFrame` of a session is delivered.
    ///
    /// - Parameter signal: The signal.
    public func receive(_ signal: PlayerSignal) {
        guard open else {
            return
        }
        if case .event(.firstFrame) = signal {
            guard !framed else {
                return
            }
            framed = true
        }
        for observer in observers {
            observer(signal)
        }
        if case .event(let event) = signal {
            continuation.yield(event)
        }
    }

    /// Delivers an event the session itself produced, such as an applied picture route.
    ///
    /// - Parameter event: The event.
    public func report(_ event: StreamSessionEvent) {
        receive(.event(event))
    }

    /// Stops delivering signals.
    public func close() {
        open = false
        observers = []
    }
}
