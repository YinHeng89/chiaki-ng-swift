/// What a Kakusan state machine did with an input.
public enum KakusanTransition: Equatable, Sendable {
    /// The input changed the state.
    case accepted

    /// The input was stale or repeated and changed nothing.
    case ignored

    /// The input is not valid in the current state.
    case rejected
}
