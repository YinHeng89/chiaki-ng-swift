/// What happened when a stream was ended.
public enum StreamExitOutcome: Equatable, Sendable {
    /// The stream ended as asked.
    case left

    /// The stream ended but the console refused to enter rest mode.
    case restRefused
}

/// How one particular stream is ended.
public enum StreamExitAction: Equatable, Sendable {
    /// Disconnect and leave the console on.
    case disconnect

    /// Disconnect and put the console in rest mode.
    case restMode
}
