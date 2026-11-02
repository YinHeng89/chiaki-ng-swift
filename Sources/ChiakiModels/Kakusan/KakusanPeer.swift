import Foundation

/// A remembered Kakusan participant.
public struct KakusanPeer: Equatable, Sendable, Identifiable {
    /// The longest nickname allowed.
    public static let maximumNicknameLength = 40

    /// The participant's public key.
    public let publicKey: KakusanPublicKey

    /// The participant's fingerprint.
    public let fingerprint: KakusanFingerprint

    /// The nickname the user gave them.
    public let nickname: String

    /// When they were first verified.
    public let firstVerifiedAt: Date

    /// When they were last seen.
    public let lastSeenAt: Date

    /// Creates a peer.
    ///
    /// - Parameters:
    ///   - publicKey: The public key.
    ///   - fingerprint: The fingerprint.
    ///   - nickname: The nickname.
    ///   - firstVerifiedAt: When they were first verified.
    ///   - lastSeenAt: When they were last seen.
    public init(
        publicKey: KakusanPublicKey,
        fingerprint: KakusanFingerprint,
        nickname: String,
        firstVerifiedAt: Date,
        lastSeenAt: Date
    ) {
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.nickname = nickname
        self.firstVerifiedAt = firstVerifiedAt
        self.lastSeenAt = lastSeenAt
    }

    /// The peer's identity, its public key.
    public var id: KakusanPublicKey {
        publicKey
    }
}

/// Whether an incoming participant is someone remembered.
public enum KakusanRecognition: Equatable, Sendable {
    /// Not remembered.
    case unknown

    /// Remembered with the same key.
    case recognised(KakusanPeer)

    /// A remembered hint whose key has changed, which may be an impostor.
    case changedKey(KakusanPeer)

    /// The remembered nickname, when recognised.
    public var name: String? {
        if case .recognised(let peer) = self {
            return peer.nickname
        }
        return nil
    }
}

/// What happened when a participant was remembered.
public enum KakusanRememberResult: Equatable, Sendable {
    /// Saved.
    case saved(KakusanPeer)

    /// Not saved because another remembered peer already has the nickname.
    case nicknameTaken(KakusanPeer)
}
