/// How far reading the saved console pairings has got, as a finite state machine.
///
/// The first read moves from ``pending`` through ``loading(_:)``; later reads are ``reloading(_:after:)`` and
/// keep the outcome of the read before them, so the library keeps its consoles while a reload runs. Only the
/// running read's ``OperationID`` finishes it.
///
/// ```
/// pending --start--> loading --finish--> loaded | failed
/// loaded, failed --start--> reloading(after:) --finish--> loaded | failed
/// ```
public enum ConsoleCatalogLoad: Hashable, Sendable {
    /// How a finished read ended.
    public enum Outcome: Hashable, Sendable {
        /// The pairings were read.
        case loaded

        /// The pairings could not be read.
        case failed
    }

    /// Nothing has been read yet.
    case pending

    /// The first read runs.
    case loading(OperationID)

    /// A later read runs; `after` is how the previous one ended.
    case reloading(OperationID, after: Outcome)

    /// The last read found the pairings.
    case loaded

    /// The last read failed.
    case failed

    /// The running read, if one runs.
    public var running: OperationID? {
        switch self {
        case .loading(let id), .reloading(let id, _):
            id
        case .pending, .loaded, .failed:
            nil
        }
    }

    /// How the last finished read ended, or `nil` before any read finished.
    public var outcome: Outcome? {
        switch self {
        case .pending, .loading:
            nil
        case .reloading(_, let outcome):
            outcome
        case .loaded:
            .loaded
        case .failed:
            .failed
        }
    }

    /// Starts a read, superseding one that runs.
    ///
    /// - Parameter id: The read's operation id.
    public mutating func start(_ id: OperationID) {
        switch self {
        case .pending, .loading:
            self = .loading(id)
        case .reloading(_, let outcome):
            self = .reloading(id, after: outcome)
        case .loaded:
            self = .reloading(id, after: .loaded)
        case .failed:
            self = .reloading(id, after: .failed)
        }
    }

    /// Ends the running read.
    ///
    /// - Parameters:
    ///   - id: The read that finished.
    ///   - outcome: How it ended.
    /// - Returns: `true` when `id` is the running read.
    @discardableResult
    public mutating func finish(_ id: OperationID, _ outcome: Outcome) -> Bool {
        guard running == id else {
            return false
        }
        self = outcome == .loaded
            ? .loaded
            : .failed
        return true
    }

    /// Abandons a running read, returning to the last outcome.
    public mutating func stop() {
        switch self {
        case .loading:
            self = .pending
        case .reloading(_, let outcome):
            self = outcome == .loaded
                ? .loaded
                : .failed
        case .pending, .loaded, .failed:
            break
        }
    }
}

/// Why the saved console pairings could not be read.
public enum ConsoleCatalogFailure: Error, Hashable, Sendable {
    /// The database could not be opened or read.
    case unavailable
}
