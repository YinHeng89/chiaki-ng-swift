/// A Kakusan identity: a public key and its fingerprint, either this installation's own or the one the
/// native session bound to the other participant.
public struct KakusanIdentity: Equatable, Sendable {
    /// The public key.
    public let publicKey: KakusanPublicKey

    /// The fingerprint.
    public let fingerprint: KakusanFingerprint

    /// Creates an identity.
    ///
    /// - Parameters:
    ///   - publicKey: The public key.
    ///   - fingerprint: The fingerprint.
    public init(publicKey: KakusanPublicKey, fingerprint: KakusanFingerprint) {
        self.publicKey = publicKey
        self.fingerprint = fingerprint
    }
}
