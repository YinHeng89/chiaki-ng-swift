/// What refreshing one cloud title's ownership found.
public enum CloudTitleRefreshOutcome: Equatable, Sendable {
    /// The account owns the title, as it now reads.
    case owned(CloudGame)

    /// The account does not own the title.
    case notOwned

    /// The check failed.
    case failed(CloudTitleRefreshFailure)

    /// The outcome as a log label.
    public var logLabel: String {
        switch self {
        case .owned:
            "owned"
        case .notOwned:
            "not owned"
        case .failed:
            "failed"
        }
    }
}

/// Why refreshing one cloud title's ownership failed, as the text the app shows.
public struct CloudTitleRefreshFailure: Error, Equatable, Sendable {
    /// The message to show.
    public let message: String

    /// Describes a failure.
    ///
    /// - Parameter message: The message to show.
    public init(_ message: String) {
        self.message = message
    }
}
