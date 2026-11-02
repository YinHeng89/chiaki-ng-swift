/// The load and save workflow of one ``PersistedSettingValue``.
///
/// The machine starts ``unloaded`` and accepts edits only once a value has been loaded, so an edit made
/// before the stored value arrives can never write defaults over it. Every load and save carries the
/// ``OperationID`` that started it, and a completion with another id is ignored. While a save runs, further
/// edits replace the draft; when the save finishes, the newer draft is saved next. A draft that does not
/// validate is held in ``saveFailed(saved:draft:failure:)`` and is committed by the next valid edit.
public enum PersistedSetting<Value: PersistedSettingValue>: Equatable, Sendable {
    /// Nothing has been loaded yet.
    case unloaded

    /// The stored value is being read.
    case loading(OperationID)

    /// The stored value could not be read; edits stay refused.
    case loadFailed(PersistedSettingFailure)

    /// The stored value is shown and matches what is saved.
    case ready(saved: Value)

    /// A save is running; `draft` is the newest edit, which may be newer than the value being saved.
    case saving(OperationID, saved: Value, draft: Value)

    /// The last edit was not committed, because it did not validate or the write failed.
    case saveFailed(saved: Value, draft: Value, failure: PersistedSettingFailure)

    /// What an edit asks the owner to do.
    public enum Edit: Equatable, Sendable {
        /// Nothing: the setting is not loaded, so the edit was refused.
        case refused

        /// Nothing: the edit matches the saved value.
        case unchanged

        /// Nothing yet: a save is running, and the edit is saved after it.
        case queued

        /// Nothing: the edit did not validate and is held as a draft.
        case invalid

        /// Start a save of this validated value with ``beginSave(_:value:)``.
        case save(Value)
    }

    /// The value the user sees and edits: the draft when there is one, else the saved value.
    public var value: Value? {
        switch self {
        case .unloaded, .loading, .loadFailed:
            nil
        case let .ready(saved):
            saved
        case let .saving(_, _, draft), let .saveFailed(_, draft, _):
            draft
        }
    }

    /// The value known to be stored.
    public var saved: Value? {
        switch self {
        case .unloaded, .loading, .loadFailed:
            nil
        case let .ready(saved), let .saving(_, saved, _), let .saveFailed(saved, _, _):
            saved
        }
    }

    /// Whether edits are accepted.
    public var isLoaded: Bool {
        saved != nil
    }

    /// Whether a load or save is running.
    public var isBusy: Bool {
        switch self {
        case .loading, .saving:
            true
        case .unloaded, .loadFailed, .ready, .saveFailed:
            false
        }
    }

    /// Why the last load or save did not go through, if it did not.
    public var failure: PersistedSettingFailure? {
        switch self {
        case let .loadFailed(failure), let .saveFailed(_, _, failure):
            failure
        case .unloaded, .loading, .ready, .saving:
            nil
        }
    }

    /// Starts reading the stored value.
    ///
    /// A load starts when nothing is loaded, after a failed load, and when the shown value is the saved one.
    /// It never starts while a draft is pending, so a reload cannot discard an edit.
    ///
    /// - Parameter id: The id the load's completion carries.
    /// - Returns: Whether the load started.
    public mutating func beginLoad(_ id: OperationID) -> Bool {
        switch self {
        case .unloaded, .loadFailed, .ready:
            self = .loading(id)
            return true
        case .loading, .saving, .saveFailed:
            return false
        }
    }

    /// Finishes a load.
    ///
    /// - Parameters:
    ///   - id: The id the load was started with.
    ///   - result: The stored value, or why it could not be read.
    /// - Returns: Whether the completion belonged to the running load.
    @discardableResult
    public mutating func finishLoad(_ id: OperationID,
                                    _ result: Result<Value, PersistedSettingFailure>) -> Bool {
        guard case .loading(id) = self else {
            return false
        }
        switch result {
        case let .success(value):
            self = .ready(saved: value)
        case let .failure(failure):
            self = .loadFailed(failure)
        }
        return true
    }

    /// Applies an edit.
    ///
    /// - Parameter edited: The edited value; it is normalised first.
    /// - Returns: What the owner does next.
    public mutating func edit(_ edited: Value) -> Edit {
        let draft = edited.normalized()
        switch self {
        case .unloaded, .loading, .loadFailed:
            return .refused
        case let .saving(id, saved, _):
            self = .saving(id, saved: saved, draft: draft)
            return .queued
        case let .ready(saved), let .saveFailed(saved, _, _):
            return commit(draft, over: saved)
        }
    }

    /// Starts saving a value that ``edit(_:)`` or ``finishSave(_:_:)`` returned.
    ///
    /// - Parameters:
    ///   - id: The id the save's completion carries.
    ///   - value: The validated value to store.
    public mutating func beginSave(_ id: OperationID, value: Value) {
        guard let saved else {
            return
        }
        self = .saving(id, saved: saved, draft: value)
    }

    /// Finishes a save.
    ///
    /// - Parameters:
    ///   - id: The id the save was started with.
    ///   - result: The stored value, or why it could not be written.
    /// - Returns: The newer draft to save next, when the draft moved on during the save.
    public mutating func finishSave(_ id: OperationID,
                                    _ result: Result<Value, PersistedSettingFailure>) -> Value? {
        guard case let .saving(running, saved, draft) = self, running == id else {
            return nil
        }
        switch result {
        case let .failure(failure):
            self = .saveFailed(saved: saved, draft: draft, failure: failure)
            return nil
        case let .success(stored):
            self = .ready(saved: stored)
            guard case let .save(next) = commit(draft, over: stored) else {
                return nil
            }
            return next
        }
    }

    /// Takes a newer stored value from elsewhere, such as the stream menu, when no draft is pending.
    ///
    /// - Parameter stored: The value now stored.
    public mutating func adopt(_ stored: Value) {
        if case .ready = self {
            self = .ready(saved: stored)
        }
    }

    private mutating func commit(_ draft: Value, over saved: Value) -> Edit {
        guard draft != saved else {
            self = .ready(saved: saved)
            return .unchanged
        }
        do {
            let checked = try draft.validated()
            self = .ready(saved: saved)
            return .save(checked)
        } catch {
            self = .saveFailed(saved: saved, draft: draft, failure: .invalid)
            return .invalid
        }
    }
}

/// Why a persisted setting could not be loaded or saved.
public enum PersistedSettingFailure: Error, Equatable, Sendable {
    /// The settings storage could not be read or written.
    case unavailable

    /// The value did not validate, so it was not stored.
    case invalid
}
