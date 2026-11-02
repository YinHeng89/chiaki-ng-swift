/// One stream session over any ``StreamSource``, as a finite state machine.
///
/// Every transition names the ``StreamSessionID`` it is for and is refused for any other session, so a late
/// event from a stopped or superseded session cannot move the current one. The id is also the native lease:
/// the live client holds it from ``begin(_:source:)`` until the session ends.
///
/// ```
/// idle, ended, failed --begin--> starting
/// starting --updateStage--> starting
/// starting --requestAccess--> awaitingAccess --accessGranted--> starting
/// starting, awaitingAccess --firstFrame--> playing
/// playing --reconnecting--> reconnecting --reconnected--> playing
/// playing --relaunch--> relaunching --relaunched--> starting (a new id, the same source)
/// starting, awaitingAccess, playing, reconnecting, relaunching --stop--> stopping --stopped--> ended(left)
/// starting, awaitingAccess, playing, reconnecting --end--> ended(finished)
/// starting, awaitingAccess, playing, reconnecting --fail--> failed
/// ended, failed --dismiss / stop--> idle
/// ```
public enum StreamSession: Equatable, Sendable {
    /// No session.
    case idle

    /// The session is starting and has not shown a frame.
    case starting(StreamSessionID, StreamStartStage)

    /// The start is paused until the console's login PIN is given; it resumes at `resuming`.
    case awaitingAccess(StreamSessionID, StreamAccessPrompt, resuming: StreamStartStage)

    /// Video is playing.
    case playing(StreamSessionID)

    /// The connection dropped and the core is reconnecting.
    case reconnecting(StreamSessionID, attempt: Int)

    /// The playing session is closing so the same source can start again with changed launch settings.
    case relaunching(StreamSessionID)

    /// The user left and the session is closing.
    case stopping(StreamSessionID, StreamExitAction)

    /// The session ended without failing.
    case ended(StreamSessionID, StreamEnding)

    /// The session failed.
    case failed(StreamSessionID, StreamFailure)

    /// The session's id, while there is one.
    public var id: StreamSessionID? {
        switch self {
        case .idle:
            nil
        case .starting(let id, _), .awaitingAccess(let id, _, _), .playing(let id), .reconnecting(let id, _),
             .relaunching(let id), .stopping(let id, _), .ended(let id, _), .failed(let id, _):
            id
        }
    }

    /// The id of a session that is starting, playing or reconnecting, and so still accepts events.
    public var liveID: StreamSessionID? {
        switch self {
        case .starting(let id, _), .awaitingAccess(let id, _, _), .playing(let id), .reconnecting(let id, _):
            id
        case .idle, .relaunching, .stopping, .ended, .failed:
            nil
        }
    }

    /// Whether `id` is the live session.
    ///
    /// - Parameter id: A session id.
    /// - Returns: `true` when `id` is starting, playing or reconnecting.
    public func accepts(_ id: StreamSessionID) -> Bool {
        liveID == id
    }

    /// Whether the session has shown video and not yet stopped.
    public var isStreaming: Bool {
        switch self {
        case .playing, .reconnecting:
            true
        case .idle, .starting, .awaitingAccess, .relaunching, .stopping, .ended, .failed:
            false
        }
    }

    /// Whether the session has not shown its first frame yet.
    public var isStarting: Bool {
        switch self {
        case .starting, .awaitingAccess:
            true
        case .idle, .playing, .reconnecting, .relaunching, .stopping, .ended, .failed:
            false
        }
    }

    /// Whether the session is closing to start again with changed launch settings.
    public var isRelaunching: Bool {
        if case .relaunching = self {
            return true
        }
        return false
    }

    /// Whether a new session can begin.
    public var canBegin: Bool {
        switch self {
        case .idle, .ended, .failed:
            true
        case .starting, .awaitingAccess, .playing, .reconnecting, .relaunching, .stopping:
            false
        }
    }

    /// The start stage, while the session is starting or paused for access.
    public var stage: StreamStartStage? {
        switch self {
        case .starting(_, let stage), .awaitingAccess(_, _, let stage):
            stage
        case .idle, .playing, .reconnecting, .relaunching, .stopping, .ended, .failed:
            nil
        }
    }

    /// The reconnection attempt, while reconnecting.
    public var reconnectAttempt: Int? {
        if case .reconnecting(_, let attempt) = self {
            return attempt
        }
        return nil
    }

    /// The failure, once failed.
    public var failure: StreamFailure? {
        if case .failed(_, let failure) = self {
            return failure
        }
        return nil
    }

    /// Begins a session.
    ///
    /// - Parameters:
    ///   - id: The new session's id.
    ///   - source: What it plays.
    /// - Returns: `true` when no session was running; an ended or failed session is replaced.
    @discardableResult
    public mutating func begin(_ id: StreamSessionID, source: StreamSource) -> Bool {
        guard canBegin else {
            return false
        }
        self = .starting(id, source.firstStage)
        return true
    }

    /// Moves the start stage of a starting session.
    ///
    /// The stage's own transitions, such as ``StreamStartStage/advance(to:)`` or
    /// ``StreamStartStage/retried(_:)``, decide whether it moves.
    ///
    /// - Parameters:
    ///   - id: The session.
    ///   - change: Applies one stage transition and returns whether it moved.
    /// - Returns: `true` when session `id` is starting or paused for access and `change` moved its stage.
    @discardableResult
    public mutating func updateStage(for id: StreamSessionID,
                                     _ change: (inout StreamStartStage) -> Bool) -> Bool {
        switch self {
        case .starting(id, var stage):
            guard change(&stage) else {
                return false
            }
            self = .starting(id, stage)
        case .awaitingAccess(id, let prompt, var stage):
            guard change(&stage) else {
                return false
            }
            self = .awaitingAccess(id, prompt, resuming: stage)
        default:
            return false
        }
        return true
    }

    /// Pauses the start until the console's login PIN is given, or asks for it again.
    ///
    /// - Parameters:
    ///   - prompt: The prompt; only ``StreamAccessPrompt/loginPIN(retry:)`` pauses a start.
    ///   - id: The session.
    /// - Returns: `true` when the starting session `id` is now waiting for the prompt.
    @discardableResult
    public mutating func requestAccess(_ prompt: StreamAccessPrompt, for id: StreamSessionID) -> Bool {
        guard prompt.isLoginPIN else {
            return false
        }
        switch self {
        case .starting(id, let stage):
            self = .awaitingAccess(id, prompt, resuming: stage)
        case .awaitingAccess(id, _, let stage):
            self = .awaitingAccess(id, prompt, resuming: stage)
        default:
            return false
        }
        return true
    }

    /// Resumes the start after the login PIN was taken.
    ///
    /// - Parameter id: The session.
    /// - Returns: `true` when session `id` was waiting for access.
    @discardableResult
    public mutating func accessGranted(for id: StreamSessionID) -> Bool {
        guard case .awaitingAccess(id, _, let stage) = self else {
            return false
        }
        self = .starting(id, stage)
        return true
    }

    /// Records the first video frame.
    ///
    /// - Parameter id: The session.
    /// - Returns: `true` when session `id` was starting and is now playing.
    @discardableResult
    public mutating func firstFrame(for id: StreamSessionID) -> Bool {
        switch self {
        case .starting(id, _), .awaitingAccess(id, _, _):
            self = .playing(id)
            return true
        default:
            return false
        }
    }

    /// Records a reconnection attempt.
    ///
    /// - Parameters:
    ///   - attempt: The core's attempt number.
    ///   - id: The session.
    /// - Returns: `true` when session `id` is playing or already reconnecting.
    @discardableResult
    public mutating func reconnecting(_ attempt: Int, for id: StreamSessionID) -> Bool {
        switch self {
        case .playing(id), .reconnecting(id, _):
            self = .reconnecting(id, attempt: attempt)
            return true
        default:
            return false
        }
    }

    /// Records that the core reconnected.
    ///
    /// - Parameter id: The session.
    /// - Returns: `true` when session `id` was reconnecting.
    @discardableResult
    public mutating func reconnected(for id: StreamSessionID) -> Bool {
        guard case .reconnecting(id, _) = self else {
            return false
        }
        self = .playing(id)
        return true
    }

    /// Starts closing a playing session so the same source can start again.
    ///
    /// - Parameter id: The session.
    /// - Returns: `true` when session `id` was playing and is now relaunching.
    @discardableResult
    public mutating func relaunch(_ id: StreamSessionID) -> Bool {
        guard case .playing(id) = self else {
            return false
        }
        self = .relaunching(id)
        return true
    }

    /// Starts the same source again under a new session once the relaunching one has closed.
    ///
    /// - Parameters:
    ///   - id: The session that closed.
    ///   - next: The new session's id.
    ///   - source: What it plays.
    /// - Returns: `true` when session `id` was relaunching and `next` is now starting.
    @discardableResult
    public mutating func relaunched(_ id: StreamSessionID, as next: StreamSessionID,
                                    source: StreamSource) -> Bool {
        guard case .relaunching(id) = self else {
            return false
        }
        self = .starting(next, source.firstStage)
        return true
    }

    /// Leaves the session.
    ///
    /// A live session starts stopping; an ended or failed one is dismissed.
    ///
    /// - Parameter exit: How the user leaves.
    /// - Returns: The id of the session that is now stopping, or `nil` when nothing needs stopping.
    @discardableResult
    public mutating func stop(_ exit: StreamExitAction) -> StreamSessionID? {
        switch self {
        case .starting(let id, _), .awaitingAccess(let id, _, _), .playing(let id), .reconnecting(let id, _),
             .relaunching(let id):
            self = .stopping(id, exit)
            return id
        case .ended, .failed:
            self = .idle
            return nil
        case .idle, .stopping:
            return nil
        }
    }

    /// Records that a stopping session closed.
    ///
    /// - Parameters:
    ///   - id: The session.
    ///   - outcome: What happened to the console.
    /// - Returns: `true` when session `id` was stopping.
    @discardableResult
    public mutating func stopped(_ id: StreamSessionID, outcome: StreamExitOutcome) -> Bool {
        guard case .stopping(id, _) = self else {
            return false
        }
        self = .ended(id, .left(outcome))
        return true
    }

    /// Records that the console or service ended a live session.
    ///
    /// - Parameter id: The session.
    /// - Returns: `true` when session `id` was live.
    @discardableResult
    public mutating func end(_ id: StreamSessionID) -> Bool {
        guard accepts(id) else {
            return false
        }
        self = .ended(id, .finished)
        return true
    }

    /// Records that a live session failed.
    ///
    /// - Parameters:
    ///   - id: The session.
    ///   - failure: Why it failed.
    /// - Returns: `true` when session `id` was live.
    @discardableResult
    public mutating func fail(_ id: StreamSessionID, with failure: StreamFailure) -> Bool {
        guard accepts(id) else {
            return false
        }
        self = .failed(id, failure)
        return true
    }

    /// Forgets an ended or failed session.
    ///
    /// - Returns: `true` when there was one.
    @discardableResult
    public mutating func dismiss() -> Bool {
        switch self {
        case .ended, .failed:
            self = .idle
            return true
        case .idle, .starting, .awaitingAccess, .playing, .reconnecting, .relaunching, .stopping:
            return false
        }
    }
}

/// How a stream session that did not fail ended.
public enum StreamEnding: Equatable, Sendable {
    /// The console or service ended the stream.
    case finished

    /// The user left, with what happened to the console.
    case left(StreamExitOutcome)
}
