/// What a stream session plays.
public enum StreamSource: Equatable, Sendable {
    /// A paired console, reached over the given route.
    case console(ConsoleStreamTarget, route: ConsoleRoute)

    /// A cloud title.
    case cloud(CloudStreamRequest)

    /// Another player's console, joined with a Kakusan invitation.
    case guest(KakusanGuestConfiguration)

    /// The kind of stream.
    public var kind: StreamKind {
        switch self {
        case .console:
            .console
        case .cloud:
            .cloud
        case .guest:
            .guest
        }
    }

    /// The stage a session for this source starts in.
    public var firstStage: StreamStartStage {
        switch self {
        case .console, .guest:
            .connecting(attempt: 0)
        case .cloud:
            .cloud(.checking)
        }
    }

    /// The same source as a retry starts it: a cloud request drops its clearance so it is checked again.
    public var retried: StreamSource {
        switch self {
        case .cloud(let request):
            .cloud(request.uncleared)
        case .console, .guest:
            self
        }
    }
}

/// Which kind of stream a session plays.
public enum StreamKind: Hashable, Sendable, CaseIterable {
    /// A paired console of the user's.
    case console

    /// A PlayStation cloud title.
    case cloud

    /// Another player's console, joined as a Kakusan guest.
    case guest
}
