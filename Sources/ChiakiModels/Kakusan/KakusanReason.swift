import Foundation

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
    public func label(byPeer: Bool) -> LocalizedStringResource {
        switch self {
        case .user:
            byPeer
                ? .kakusanReasonLeftGame
                : .kakusanReasonRemoved
        case .capacity:
            .kakusanReasonNoFreeSeat
        case .source:
            .kakusanReasonStreamEnded
        case .timeout:
            .kakusanReasonTimedOut
        case .network:
            .kakusanReasonConnectionLost
        case .protocol:
            .kakusanReasonConnectionError
        }
    }
}
