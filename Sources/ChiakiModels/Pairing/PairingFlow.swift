/// The pairing workflow for one console, as a finite state machine.
///
/// A home target starts in ``enteringPIN(_:failure:)`` and an internet target in ``ready(_:)``.
/// ``start(_:)`` begins an attempt, ``report(_:for:)`` and ``finish(_:with:)`` accept only the attempt that
/// is running, and ``cancel()`` steps back. The workflow ends in ``paired(_:)`` or ``left(_:failure:)``.
///
/// ```
/// enteringPIN --start--> pairing --finish(success)--> paired
///      ^                  |  |
///      +--finish(fail)----+  +--cancel / finish(fail), internet--> left
/// ready --start--> pairing
/// enteringPIN, ready --cancel--> left
/// ```
public enum PairingFlow: Hashable, Sendable {
    /// Waiting for the PIN of a home target, showing why the last attempt failed, if it did.
    case enteringPIN(PairingTarget, failure: PairingFailure?)

    /// An internet target waiting for its attempt to start.
    case ready(PairingTarget)

    /// An attempt is running.
    case pairing(PairingAttempt)

    /// The console was paired and saved.
    case paired(PairedConsole)

    /// The user left the workflow, or an internet attempt failed, without a pairing.
    case left(PairingTarget, failure: PairingFailure?)

    /// The workflow's first state for a target.
    ///
    /// - Parameter target: The console to pair.
    public init(target: PairingTarget) {
        self = target.needsPIN
            ? .enteringPIN(target, failure: nil)
            : .ready(target)
    }

    /// The console the workflow is about.
    public var target: PairingTarget? {
        switch self {
        case .enteringPIN(let target, _), .ready(let target), .left(let target, _):
            target
        case .pairing(let attempt):
            attempt.target
        case .paired:
            nil
        }
    }

    /// The running attempt, if one is running.
    public var attempt: PairingAttempt? {
        if case .pairing(let attempt) = self {
            return attempt
        }
        return nil
    }

    /// Starts an attempt from PIN entry or from ready.
    ///
    /// - Parameter id: The new attempt's operation id.
    /// - Returns: `true` when the attempt started; `false` when an attempt is running or the workflow ended.
    @discardableResult
    public mutating func start(_ id: OperationID) -> Bool {
        switch self {
        case .enteringPIN(let target, _), .ready(let target):
            self = .pairing(PairingAttempt(id: id, target: target))
            return true
        case .pairing, .paired, .left:
            return false
        }
    }

    /// Records a progress report from the running attempt.
    ///
    /// - Parameters:
    ///   - progress: The report.
    ///   - id: The attempt that sent it.
    /// - Returns: `true` when `id` is the running attempt; reports from any other attempt are ignored.
    @discardableResult
    public mutating func report(_ progress: PairingProgress, for id: OperationID) -> Bool {
        guard case .pairing(var attempt) = self, attempt.id == id else {
            return false
        }
        attempt.progress = progress
        self = .pairing(attempt)
        return true
    }

    /// Ends the running attempt with its result.
    ///
    /// Success moves to ``paired(_:)``. A failed home attempt returns to PIN entry with the failure; a failed
    /// internet attempt leaves the workflow with it. A ``PairingFailure/cancelled`` result never moves the
    /// workflow, because ``cancel()`` already did.
    ///
    /// - Parameters:
    ///   - id: The attempt that finished.
    ///   - result: The paired console or why the attempt failed.
    /// - Returns: `true` when `id` is the running attempt and the result moved the workflow.
    @discardableResult
    public mutating func finish(_ id: OperationID,
                                with result: Result<PairedConsole, PairingFailure>) -> Bool {
        guard case .pairing(let attempt) = self, attempt.id == id else {
            return false
        }
        switch result {
        case .success(let console):
            self = .paired(console)
        case .failure(.cancelled):
            return false
        case .failure(let failure):
            self = attempt.target.needsPIN
                ? .enteringPIN(attempt.target, failure: failure)
                : .left(attempt.target, failure: failure)
        }
        return true
    }

    /// Steps back: a running home attempt returns to PIN entry, anything else not yet ended leaves.
    ///
    /// - Returns: `true` when the workflow moved; `false` once it has ended.
    @discardableResult
    public mutating func cancel() -> Bool {
        switch self {
        case .pairing(let attempt):
            self = attempt.target.needsPIN
                ? .enteringPIN(attempt.target, failure: nil)
                : .left(attempt.target, failure: nil)
        case .enteringPIN(let target, _), .ready(let target):
            self = .left(target, failure: nil)
        case .paired, .left:
            return false
        }
        return true
    }
}

/// One running pairing attempt: its operation id, its target and the latest progress it reported.
public struct PairingAttempt: Hashable, Sendable {
    /// The operation id every report and completion of the attempt carries.
    public let id: OperationID

    /// The console being paired.
    public let target: PairingTarget

    /// The latest progress report, once the core has sent one.
    public var progress: PairingProgress?

    /// Describes an attempt that has just started.
    ///
    /// - Parameters:
    ///   - id: The attempt's operation id.
    ///   - target: The console being paired.
    ///   - progress: The latest report, if any.
    public init(id: OperationID, target: PairingTarget, progress: PairingProgress? = nil) {
        self.id = id
        self.target = target
        self.progress = progress
    }
}
