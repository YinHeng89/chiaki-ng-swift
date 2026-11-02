/// Why a Kakusan session closed without an error.
///
/// The raw values are the native session's reason names.
public enum KakusanReason: String, Equatable, Sendable, CaseIterable {
    /// A participant chose to end it.
    case user

    /// No seat was free.
    case capacity

    /// The host's stream ended.
    case source

    /// It timed out.
    case timeout

    /// The network dropped.
    case network

    /// The peer broke the protocol.
    case `protocol`

    /// The message shown for the reason.
    ///
    /// - Parameter byPeer: Whether the other participant ended it.
    /// - Returns: The message.
    public func label(byPeer: Bool) -> String {
        switch self {
        case .user:
            byPeer
                ? "Left the game"
                : "Removed"
        case .capacity:
            "No free seat"
        case .source:
            "The stream ended"
        case .timeout:
            "Timed out"
        case .network:
            "Connection lost"
        case .protocol:
            "Connection error"
        }
    }
}
