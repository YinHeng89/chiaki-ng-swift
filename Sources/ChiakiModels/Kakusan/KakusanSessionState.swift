/// The native Kakusan session's state; the raw values are its state names.
public enum KakusanSessionState: String, Equatable, Sendable, CaseIterable {
    /// Waiting for the peer.
    case waiting

    /// Connecting to the peer.
    case connecting

    /// Comparing verification codes.
    case verifying

    /// The host is admitting the guest.
    case admitting

    /// Waiting for the guest to be ready.
    case readyWait

    /// Playing.
    case active

    /// Closing.
    case closing

    /// Closed.
    case closed
}
