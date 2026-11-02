import Foundation

/// A Kakusan device this installation has verified and remembers.
public struct RememberedDevice: Hashable, Sendable {
    /// The device's public key.
    public let key: DeviceIdentityKey

    /// The device's fingerprint.
    public let fingerprint: DeviceKeyFingerprint

    /// The name the user gave it.
    public let nickname: String

    /// When it was first verified.
    public let firstVerified: Date

    /// When it was last seen.
    public let lastSeen: Date

    /// Describes a remembered device.
    ///
    /// - Parameters:
    ///   - key: The public key.
    ///   - fingerprint: The fingerprint.
    ///   - nickname: The name the user gave it.
    ///   - firstVerified: When it was first verified.
    ///   - lastSeen: When it was last seen.
    public init(
        key: DeviceIdentityKey,
        fingerprint: DeviceKeyFingerprint,
        nickname: String,
        firstVerified: Date,
        lastSeen: Date
    ) {
        self.key = key
        self.fingerprint = fingerprint
        self.nickname = nickname
        self.firstVerified = firstVerified
        self.lastSeen = lastSeen
    }
}
