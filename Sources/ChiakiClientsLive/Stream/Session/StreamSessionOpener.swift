import ChiakiClients
import ChiakiModels

/// What a ``StreamLauncher`` is handed to open the live session once its player exists.
@MainActor
public struct StreamSessionOpener {
    /// The session being launched; it already holds the lease.
    public let id: StreamSessionID

    private let leases: StreamLeases
    private let continuation: AsyncThrowingStream<StreamSessionEvent, any Error>.Continuation

    /// Creates an opener.
    ///
    /// - Parameters:
    ///   - id: The session being launched.
    ///   - leases: The lease it holds.
    ///   - continuation: Where its events go.
    public init(
        id: StreamSessionID,
        leases: StreamLeases,
        continuation: AsyncThrowingStream<StreamSessionEvent, any Error>.Continuation
    ) {
        self.id = id
        self.leases = leases
        self.continuation = continuation
    }

    /// Whether the session was stopped while the launcher was still preparing.
    public var isStopped: Bool {
        !leases.acceptsEvents(id)
    }

    /// Opens the live session around a prepared player.
    ///
    /// - Parameter player: The player.
    /// - Returns: The session, attached to the lease so commands reach it.
    public func open(_ player: any StreamPlayer) -> LiveStreamSession {
        LiveStreamSession(id: id, player: player, leases: leases, continuation: continuation)
    }
}

/// Prepares and runs the player for one kind of stream.
///
/// The live ``ChiakiClients/StreamSessionClient`` takes the lease, hands the launcher a ``StreamSessionOpener`` and reports
/// the launcher's outcome as the end of the session's event stream: returning ends it normally, throwing a
/// `ChiakiModels/StreamFailure` fails it. A launcher returns without an error once
/// ``StreamSessionOpener/isStopped`` is set or its task is cancelled.
@MainActor
public protocol StreamLauncher: AnyObject, Sendable {
    /// Prepares the player for a source, opens the session and runs it until it ends.
    ///
    /// - Parameters:
    ///   - source: What to stream.
    ///   - opener: Opens the live session once the player exists.
    /// - Throws: Why the stream failed.
    func launch(_ source: StreamSource, opening opener: StreamSessionOpener) async throws(StreamFailure)
}
