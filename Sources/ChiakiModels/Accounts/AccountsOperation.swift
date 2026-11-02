import Foundation

/// The one account operation that may run at a time, as a finite state machine.
///
/// Loading, saving an account added by id, and deleting exclude each other. Every running operation carries
/// the ``OperationID`` that started it, and ``finish(_:failure:)`` accepts only that id, so a cancelled or
/// superseded operation cannot move the machine. Refreshing runs beside it as ``AccountsRefresh``.
///
/// ```
/// idle, failed --startLoading--> loading --finish--> idle | failed(loadFailed)
/// idle, failed --startSaving---> saving  --finish--> idle | failed
/// idle, failed --requestDeletion--> confirmingDeletion --confirm--> deleting --finish--> idle | failed
///                                   confirmingDeletion --cancelDeletion--> idle
/// ```
public enum AccountsOperation: Hashable, Sendable {
    /// Nothing is running.
    case idle

    /// The saved accounts are being read.
    case loading(OperationID)

    /// An account added by account id is being saved.
    case saving(OperationID)

    /// The user is asked to confirm deleting an account.
    case confirmingDeletion(UUID)

    /// An account is being deleted.
    case deleting(OperationID, UUID)

    /// The last operation failed.
    case failed(AccountsFailure)

    /// The running operation's id, if one is running.
    public var running: OperationID? {
        switch self {
        case .loading(let id), .saving(let id), .deleting(let id, _):
            id
        case .idle, .confirmingDeletion, .failed:
            nil
        }
    }

    /// Whether a new operation may start: nothing runs and no deletion waits for confirmation.
    public var isSettled: Bool {
        switch self {
        case .idle, .failed:
            true
        case .loading, .saving, .confirmingDeletion, .deleting:
            false
        }
    }

    /// The failure the machine shows, if it failed.
    public var failure: AccountsFailure? {
        if case .failed(let failure) = self {
            return failure
        }
        return nil
    }

    /// Starts reading the saved accounts.
    ///
    /// - Parameter id: The new operation's id.
    /// - Returns: `true` when the load started.
    @discardableResult
    public mutating func startLoading(_ id: OperationID) -> Bool {
        guard isSettled else {
            return false
        }
        self = .loading(id)
        return true
    }

    /// Starts saving an account added by account id.
    ///
    /// - Parameter id: The new operation's id.
    /// - Returns: `true` when the save started.
    @discardableResult
    public mutating func startSaving(_ id: OperationID) -> Bool {
        guard isSettled else {
            return false
        }
        self = .saving(id)
        return true
    }

    /// Asks to confirm deleting an account.
    ///
    /// - Parameter profile: The account to delete.
    /// - Returns: `true` when the confirmation is shown.
    @discardableResult
    public mutating func requestDeletion(of profile: UUID) -> Bool {
        guard isSettled else {
            return false
        }
        self = .confirmingDeletion(profile)
        return true
    }

    /// Withdraws a deletion that waits for confirmation.
    ///
    /// - Returns: `true` when a confirmation was withdrawn.
    @discardableResult
    public mutating func cancelDeletion() -> Bool {
        guard case .confirmingDeletion = self else {
            return false
        }
        self = .idle
        return true
    }

    /// Starts the deletion that waits for confirmation.
    ///
    /// - Parameter id: The deletion's operation id.
    /// - Returns: The account being deleted, or `nil` when no deletion waited for confirmation.
    public mutating func confirmDeletion(_ id: OperationID) -> UUID? {
        guard case .confirmingDeletion(let profile) = self else {
            return nil
        }
        self = .deleting(id, profile)
        return profile
    }

    /// Ends the running operation.
    ///
    /// - Parameters:
    ///   - id: The operation that finished.
    ///   - failure: Why it failed, or `nil` when it succeeded.
    /// - Returns: `true` when `id` is the running operation.
    @discardableResult
    public mutating func finish(_ id: OperationID, failure: AccountsFailure?) -> Bool {
        guard running == id else {
            return false
        }
        self = failure.map(AccountsOperation.failed) ?? .idle
        return true
    }

    /// Abandons whatever runs or waits, keeping a shown failure.
    public mutating func stop() {
        switch self {
        case .loading, .saving, .confirmingDeletion, .deleting:
            self = .idle
        case .idle, .failed:
            break
        }
    }
}

/// The account refresh, which runs beside ``AccountsOperation`` as its own machine.
///
/// ```
/// idle, failed --start--> refreshing --finish--> idle | failed
/// refreshing --stop--> idle
/// ```
public enum AccountsRefresh: Hashable, Sendable {
    /// No refresh runs, and the last one, if any, found nothing wrong.
    case idle

    /// A refresh runs.
    case refreshing(OperationID)

    /// The last refresh failed, or some account could not be refreshed.
    case failed

    /// The running refresh's id, if one runs.
    public var running: OperationID? {
        if case .refreshing(let id) = self {
            return id
        }
        return nil
    }

    /// Starts a refresh unless one runs.
    ///
    /// - Parameter id: The refresh's operation id.
    /// - Returns: `true` when the refresh started.
    @discardableResult
    public mutating func start(_ id: OperationID) -> Bool {
        guard running == nil else {
            return false
        }
        self = .refreshing(id)
        return true
    }

    /// Ends the running refresh.
    ///
    /// - Parameters:
    ///   - id: The refresh that finished.
    ///   - clean: Whether every account was refreshed.
    /// - Returns: `true` when `id` is the running refresh.
    @discardableResult
    public mutating func finish(_ id: OperationID, clean: Bool) -> Bool {
        guard running == id else {
            return false
        }
        self = clean
            ? .idle
            : .failed
        return true
    }

    /// Abandons a running refresh.
    public mutating func stop() {
        if running != nil {
            self = .idle
        }
    }
}

/// Why the accounts are being refreshed.
public enum AccountsRefreshReason: Hashable, Sendable {
    /// An account was just added or signed in again.
    case accountAdded

    /// The first refresh since the accounts were loaded.
    case firstSinceLoad

    /// The periodic check found the last refresh at least a minute old.
    case periodic(secondsSinceLast: Int)
}
