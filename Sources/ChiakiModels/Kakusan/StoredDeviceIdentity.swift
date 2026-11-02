/// This installation's Kakusan identity: the secret seed and the key and fingerprint derived from it.
public final class StoredDeviceIdentity: Sendable {
    /// The length of the seed in bytes.
    public static let seedLength = 32

    /// The seed, in a wiping buffer.
    public let seed: SecretBytes

    /// The public key derived from the seed.
    public let key: DeviceIdentityKey

    /// The fingerprint derived from the key.
    public let fingerprint: DeviceKeyFingerprint

    /// Describes an identity.
    ///
    /// - Parameters:
    ///   - seed: Exactly ``seedLength`` seed bytes.
    ///   - key: The derived public key.
    ///   - fingerprint: The derived fingerprint.
    public init?(seed: consuming SecretBytes, key: DeviceIdentityKey, fingerprint: DeviceKeyFingerprint) {
        guard seed.count == Self.seedLength else {
            return nil
        }
        self.seed = seed
        self.key = key
        self.fingerprint = fingerprint
    }
}

/// The 32-byte public key a Kakusan device is known by.
public struct DeviceIdentityKey: Hashable, Sendable {
    /// The length of a key in bytes.
    public static let byteCount = 32

    /// The key's bytes.
    public let bytes: [UInt8]

    /// Reads a key from exactly ``byteCount`` bytes.
    ///
    /// - Parameter bytes: The key's bytes.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        self.bytes = Array(bytes)
    }
}

/// The 32-byte fingerprint a Kakusan device's key is shown as.
public struct DeviceKeyFingerprint: Hashable, Sendable {
    /// The length of a fingerprint in bytes.
    public static let byteCount = 32

    /// A fingerprint of zeros, written before the core derived the real one.
    public static let underived = DeviceKeyFingerprint(zeros: ())

    /// The fingerprint's bytes.
    public let bytes: [UInt8]

    /// Reads a fingerprint from exactly ``byteCount`` bytes.
    ///
    /// - Parameter bytes: The fingerprint's bytes.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == Self.byteCount else {
            return nil
        }
        self.bytes = Array(bytes)
    }

    private init(zeros _: Void) {
        bytes = [UInt8](repeating: 0, count: Self.byteCount)
    }

    /// Whether this is the placeholder written before the core derived the fingerprint.
    public var isUnderived: Bool {
        self == Self.underived
    }
}
