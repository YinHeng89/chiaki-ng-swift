/// Why a Kakusan operation failed, as the native session reports it.
///
/// The raw values are the native session's error names.
public enum KakusanError: String, Error, Equatable, Sendable, CaseIterable {
    /// The pasted block is not valid.
    case invalidBlock

    /// The invitation expired.
    case expired

    /// The other app speaks a different protocol version.
    case version

    /// A remembered participant's identity changed.
    case identityChanged

    /// The handshake transcript could not be checked.
    case transcript

    /// The verification codes did not match.
    case pairingFailed

    /// No network path joins the two participants.
    case noPath

    /// No seat is free.
    case noCapacity

    /// The console would not add the player.
    case sourceJoinFailed

    /// The video format is unsupported.
    case codec

    /// The operation timed out.
    case timeout

    /// The peer broke the protocol.
    case `protocol`

    /// The host's stream format cannot be shared.
    case sourceFormat

    /// The connection was too slow.
    case congestion

    /// The host's stream ended.
    case sourceEnded

    /// Encryption is unavailable.
    case cryptoUnavailable

    /// An internal failure.
    case `internal`

    /// The message shown to a guest.
    public var label: String {
        switch self {
        case .invalidBlock:
            "The pasted text isn’t valid"
        case .expired:
            "The invitation expired"
        case .version:
            "The other app uses a different version"
        case .identityChanged:
            "The device’s identity changed"
        case .transcript:
            "The connection couldn’t be checked"
        case .pairingFailed:
            "The codes didn’t match"
        case .noPath:
            "No direct path between your networks"
        case .noCapacity:
            "No free seat"
        case .sourceJoinFailed:
            "The console couldn’t add the player"
        case .codec:
            "Unsupported video format"
        case .timeout:
            "Timed out"
        case .protocol:
            "Connection error"
        case .sourceFormat:
            "Unsupported stream format"
        case .congestion:
            "The connection was too slow"
        case .sourceEnded:
            "The host’s stream ended"
        case .cryptoUnavailable:
            "Encryption is unavailable"
        case .internal:
            "Something went wrong"
        }
    }

    /// The message shown to the host, which explains what the host can change.
    public var hostingLabel: String {
        switch self {
        case .codec:
            "Use H.264 or H.265 without HDR, at 1080p and 60 fps or lower"
        case .version:
            "This console connection can’t be shared"
        default:
            label
        }
    }
}
