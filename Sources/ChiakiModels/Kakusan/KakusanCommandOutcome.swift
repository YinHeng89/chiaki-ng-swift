/// The native session's answer to a command.
public enum KakusanCommandOutcome: Equatable, Sendable {
    /// The command was accepted.
    case accepted

    /// The command was refused.
    case rejected(KakusanError)

    /// The refusal, if any.
    public var error: KakusanError? {
        switch self {
        case .accepted:
            nil
        case .rejected(let error):
            error
        }
    }
}
