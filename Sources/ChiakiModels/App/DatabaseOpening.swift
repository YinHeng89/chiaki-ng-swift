/// The lifecycle of opening the app database, as a finite state machine.
///
/// ```
/// closed --begin--> opening --finish(success)--> open
///                     |
///                     +--finish(failure)--> failed --begin--> opening
/// ```
///
/// A failed open can be retried. A completion is accepted only from the attempt that is running, so a
/// superseded attempt cannot reopen or fail the database.
public enum DatabaseOpening: Hashable, Sendable {
    /// Nothing has tried to open the database.
    case closed

    /// An open attempt is running.
    case opening(OperationID)

    /// The database is open and migrated.
    case open

    /// The last attempt failed.
    case failed(DatabaseOpenFailure)

    /// Starts an open attempt.
    ///
    /// - Parameter id: The attempt's operation id.
    /// - Returns: `true` from ``closed`` or ``failed(_:)``; `false` while opening or once open.
    @discardableResult
    public mutating func begin(_ id: OperationID) -> Bool {
        switch self {
        case .closed, .failed:
            self = .opening(id)
            return true
        case .opening, .open:
            return false
        }
    }

    /// Ends the running attempt.
    ///
    /// - Parameters:
    ///   - id: The attempt that finished.
    ///   - failure: Why it failed, or `nil` when the database opened.
    /// - Returns: `true` when `id` is the running attempt.
    @discardableResult
    public mutating func finish(_ id: OperationID, failure: DatabaseOpenFailure?) -> Bool {
        guard case .opening(let running) = self, running == id else {
            return false
        }
        self = failure.map(DatabaseOpening.failed) ?? .open
        return true
    }
}

/// Why the app database could not be opened.
public enum DatabaseOpenFailure: Error, Hashable, Sendable {
    /// The database location could not be created or the file could not be opened.
    case unavailable

    /// The file was written by a newer version of the app.
    case unsupportedVersion

    /// The file's schema or migration ledger is inconsistent.
    case corrupt

    /// The encryption key could not be read from the Keychain.
    case keyUnavailable

    /// The process is a test harness and the location is live user data.
    case refusedLiveData
}
