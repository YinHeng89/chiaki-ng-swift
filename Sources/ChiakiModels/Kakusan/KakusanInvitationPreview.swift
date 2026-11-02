import Foundation

/// What a guest learns from an invitation before joining.
public struct KakusanInvitationPreview: Equatable, Sendable {
    /// The host's identity hint.
    public let hostHint: KakusanIdentityHint

    /// The name the host claims, unverified.
    public let claimedHostName: String?

    /// The host's seat count.
    public let capacity: Int

    /// When the invitation expires.
    public let expiresAt: Date

    /// Creates a preview.
    ///
    /// - Parameters:
    ///   - hostHint: The host's hint.
    ///   - claimedHostName: The claimed name.
    ///   - capacity: The seat count.
    ///   - expiresAt: The expiry.
    public init(
        hostHint: KakusanIdentityHint,
        claimedHostName: String?,
        capacity: Int,
        expiresAt: Date
    ) {
        self.hostHint = hostHint
        self.claimedHostName = claimedHostName
        self.capacity = capacity
        self.expiresAt = expiresAt
    }
}

/// An invitation a guest pasted, with what its preview revealed.
public struct KakusanInvitationSummary: Equatable, Sendable {
    /// The invitation block.
    public let invitation: KakusanBlock

    /// The preview.
    public let preview: KakusanInvitationPreview

    /// Creates a summary.
    ///
    /// - Parameters:
    ///   - invitation: The block.
    ///   - preview: The preview.
    public init(invitation: KakusanBlock, preview: KakusanInvitationPreview) {
        self.invitation = invitation
        self.preview = preview
    }
}

/// The 8-byte hint a guest sends so the host can find a remembered identity before verifying it.
public struct KakusanIdentityHint: Hashable, Sendable, CustomStringConvertible {
    /// The hint's length in bytes.
    public static let length = 8

    /// The hint's bytes.
    public let bytes: Data

    /// Validates a hint.
    ///
    /// - Parameter bytes: The bytes; any other length is refused.
    public init?(_ bytes: Data) {
        guard bytes.count == Self.length else {
            return nil
        }
        self.bytes = Data(bytes)
    }

    /// The first four bytes in hex.
    public var description: String {
        Hex.encode(bytes.prefix(4))
    }
}
