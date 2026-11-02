import Foundation

/// Editing and deleting one console, as a finite state machine.
///
/// A deletion asked for from the editor keeps the editor's draft, so withdrawing it or a failed deletion
/// returns to the editor with every change intact; a deletion asked for from the library returns to the
/// library. A failed save also returns to the editor with the draft. Only the running operation's
/// ``OperationID`` finishes it.
///
/// ```
/// closed --open--> loading --loaded--> editing --save--> saving --success--> closed
///                  loading --fail--> failed(loadFailed) --dismiss--> closed
/// editing --requestDeletion--> confirmingDeletion(returning: draft)
/// closed --requestDeletion--> confirmingDeletion(returning: nil)
/// confirmingDeletion --cancel--> editing(draft) | closed
/// confirmingDeletion --confirm--> deleting --success--> closed
/// saving, deleting --failure--> failed(returning:) --dismiss--> editing(draft) | closed
/// ```
public enum ConsoleEditFlow: Hashable, Sendable {
    /// No console is being edited.
    case closed

    /// The console's saved options are being read for the draft.
    case loading(OperationID, ConsoleDraft)

    /// The editor shows the draft.
    case editing(ConsoleDraft)

    /// The user is asked to confirm deleting a console; `returning` is the editor's draft, if it was open.
    case confirmingDeletion(UUID, returning: ConsoleDraft?)

    /// The draft is being saved.
    case saving(OperationID, ConsoleDraft)

    /// A console is being deleted; `returning` is the editor's draft, if it was open.
    case deleting(OperationID, UUID, returning: ConsoleDraft?)

    /// An operation failed; `returning` is the draft to edit again, if there is one.
    case failed(ConsoleEditFailure, returning: ConsoleDraft?)

    /// The running operation, if one runs.
    public var running: OperationID? {
        switch self {
        case .loading(let id, _), .saving(let id, _), .deleting(let id, _, _):
            id
        case .closed, .editing, .confirmingDeletion, .failed:
            nil
        }
    }

    /// The draft the editor shows, while it shows one.
    public var draft: ConsoleDraft? {
        if case .editing(let draft) = self {
            return draft
        }
        return nil
    }

    /// Starts reading a console's options to edit it.
    ///
    /// - Parameters:
    ///   - draft: The console as the library knows it.
    ///   - id: The read's operation id.
    /// - Returns: `true` when the read started.
    @discardableResult
    public mutating func open(_ draft: ConsoleDraft, id: OperationID) -> Bool {
        guard self == .closed else {
            return false
        }
        self = .loading(id, draft)
        return true
    }

    /// Shows the draft with the options that were read.
    ///
    /// - Parameters:
    ///   - options: The console's saved options.
    ///   - id: The read that finished.
    /// - Returns: `true` when `id` is the running read.
    @discardableResult
    public mutating func loaded(_ options: ConsoleLaunchOptions, id: OperationID) -> Bool {
        guard case .loading(id, let draft) = self else {
            return false
        }
        self = .editing(draft.applying(options))
        return true
    }

    /// Changes the draft the editor shows.
    ///
    /// - Parameter change: Edits the draft.
    /// - Returns: `true` when the editor shows a draft.
    @discardableResult
    public mutating func edit(_ change: (inout ConsoleDraft) -> Void) -> Bool {
        guard case .editing(var draft) = self else {
            return false
        }
        change(&draft)
        self = .editing(draft)
        return true
    }

    /// Asks to confirm deleting a console, from the library or from its editor.
    ///
    /// - Parameter console: The console to delete.
    /// - Returns: `true` when the confirmation is shown.
    @discardableResult
    public mutating func requestDeletion(of console: UUID) -> Bool {
        switch self {
        case .closed:
            self = .confirmingDeletion(console, returning: nil)
        case .editing(let draft) where draft.id == console:
            self = .confirmingDeletion(console, returning: draft)
        default:
            return false
        }
        return true
    }

    /// Starts saving the draft, or the deletion waiting for confirmation.
    ///
    /// - Parameter id: The operation's id.
    /// - Returns: `true` when an operation started; a draft that does not validate is not saved.
    @discardableResult
    public mutating func confirm(_ id: OperationID) -> Bool {
        switch self {
        case .editing(let draft) where draft.isValid:
            self = .saving(id, draft)
        case let .confirmingDeletion(console, draft):
            self = .deleting(id, console, returning: draft)
        default:
            return false
        }
        return true
    }

    /// Ends the running save or deletion.
    ///
    /// - Parameters:
    ///   - id: The operation that finished.
    ///   - failure: Why it failed, or `nil` when it succeeded.
    /// - Returns: `true` when `id` is the running operation.
    @discardableResult
    public mutating func finish(_ id: OperationID, failure: ConsoleEditFailure?) -> Bool {
        switch self {
        case .loading(id, _):
            self = .failed(failure ?? .loadFailed, returning: nil)
        case .saving(id, let draft):
            self = failure.map { .failed($0, returning: draft) } ?? .closed
        case .deleting(id, _, let draft):
            self = failure.map { .failed($0, returning: draft) } ?? .closed
        default:
            return false
        }
        return true
    }

    /// Steps back: a confirmation or failure returns to the editor's draft, anything else closes.
    ///
    /// A running save or deletion is not abandoned.
    ///
    /// - Returns: `true` when the machine moved.
    @discardableResult
    public mutating func cancel() -> Bool {
        switch self {
        case .closed, .saving, .deleting:
            return false
        case .loading, .editing:
            self = .closed
        case .confirmingDeletion(_, let draft), .failed(_, let draft):
            self = draft.map(ConsoleEditFlow.editing) ?? .closed
        }
        return true
    }
}

/// Why a console edit did not finish.
public enum ConsoleEditFailure: Error, Hashable, Sendable {
    /// The console's saved settings could not be read.
    case loadFailed

    /// The edit could not be saved; nothing was changed.
    case saveFailed

    /// The console could not be deleted.
    case deleteFailed
}
