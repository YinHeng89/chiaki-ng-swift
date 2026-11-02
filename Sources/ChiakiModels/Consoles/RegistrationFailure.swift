/// Why an account or console step failed, in the terms the legacy screens show.
public enum RegistrationFailure: Error, Equatable, Sendable {
    /// The address or PIN was invalid, the console refused, it did not answer, PlayStation's remote
    /// registration refused, the service was down, saving failed, or a session is playing.
    case invalidInput, rejected, unreachable, remoteRejected, unavailable, storage, sessionPlaying
    /// Whether the failure came from PlayStation's remote registration service.
    public var isRemote: Bool {
        switch self {
        case .remoteRejected:
            true
        default:
            false
        }
    }
}
