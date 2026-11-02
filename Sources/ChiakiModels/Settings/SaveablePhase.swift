import Foundation

/// Where an editable setting is: loading, ready to edit, saving, or refused.
///
/// Loading and saving carry the id of the operation that started them, so a completion for an operation that is
/// no longer current changes nothing.
public enum SaveablePhase: Equatable, Sendable {
    /// Nothing has been loaded yet.
    case idle
    /// The operation with the id is loading the stored value.
    case loading(UUID)
    /// The stored value is shown and can be edited.
    case ready
    /// The operation with the id is saving the edit.
    case saving(UUID)
    /// The edit does not validate.
    case invalid
    /// Loading or saving failed.
    case failed

    /// Whether an operation is running, so the edit cannot change.
    public var busy: Bool {
        switch self {
        case .loading, .saving:
            true
        case .idle, .ready, .invalid, .failed:
            false
        }
    }
}
