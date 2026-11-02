import Foundation

/// The identifier of one stream session, from its start until it has ended.
///
/// It is also the native lease: the live session refuses a second start while one id is held, and every event,
/// command and completion carries the id of the session it belongs to, so a stopped or superseded session
/// cannot move the next one.
public struct StreamSessionID: UUIDIdentifier {
    /// The underlying `UUID`.
    public let uuid: UUID

    /// Wraps an existing `UUID`.
    ///
    /// - Parameter uuid: The `UUID` to wrap.
    public init(uuid: UUID) {
        self.uuid = uuid
    }
}
