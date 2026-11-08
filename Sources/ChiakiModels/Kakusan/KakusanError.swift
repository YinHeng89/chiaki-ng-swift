import Foundation

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
    public var label: LocalizedStringResource {
        switch self {
        case .invalidBlock:
            .kakusanErrorInvalidBlock
        case .expired:
            .kakusanErrorExpired
        case .version:
            .kakusanErrorVersion
        case .identityChanged:
            .kakusanErrorIdentityChanged
        case .transcript:
            .kakusanErrorTranscript
        case .pairingFailed:
            .kakusanErrorPairingFailed
        case .noPath:
            .kakusanErrorNoPath
        case .noCapacity:
            .kakusanReasonNoFreeSeat
        case .sourceJoinFailed:
            .kakusanErrorSourceJoinFailed
        case .codec:
            .kakusanErrorCodec
        case .timeout:
            .kakusanReasonTimedOut
        case .protocol:
            .kakusanReasonConnectionError
        case .sourceFormat:
            .kakusanErrorSourceFormat
        case .congestion:
            .kakusanErrorCongestion
        case .sourceEnded:
            .kakusanErrorSourceEnded
        case .cryptoUnavailable:
            .kakusanErrorCryptoUnavailable
        case .internal:
            .kakusanErrorInternal
        }
    }

    /// The message shown to the host, which explains what the host can change.
    public var hostingLabel: LocalizedStringResource {
        switch self {
        case .codec:
            .kakusanErrorHostCodec
        case .version:
            .kakusanErrorHostVersion
        default:
            label
        }
    }
}
