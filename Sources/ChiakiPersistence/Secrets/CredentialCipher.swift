import ChiakiModels
import CryptoKit
import Foundation

/// Seals secrets for storage with AES-GCM under the key in a ``KeychainKeyStore``.
///
/// An envelope is a one-byte version, ``envelopeVersion``, followed by the combined nonce, ciphertext and
/// tag. The `context` string is authenticated with the ciphertext, so an envelope copied to another row
/// fails to open. CryptoKit takes the key only as a `SymmetricKey`, so one is built from the borrowed bytes
/// inside each operation and released when the operation ends.
public struct CredentialCipher: Sendable {
    /// The version byte every envelope starts with.
    public static let envelopeVersion: UInt8 = 1

    private let keys: KeychainKeyStore

    /// Creates a cipher over a key store.
    ///
    /// - Parameter keys: Where the encryption key is held.
    public init(keys: KeychainKeyStore) {
        self.keys = keys
    }

    /// Encrypts a secret into an envelope.
    ///
    /// - Parameters:
    ///   - plaintext: The secret to seal.
    ///   - context: The row identity the envelope is bound to.
    ///   - allowKeyCreation: Whether a key may be created when none exists yet. Callers allow it only while
    ///     no other credential is stored, so a lost key is never silently replaced.
    /// - Returns: The envelope to store.
    /// - Throws: ``PersistenceError/missingKey`` or ``PersistenceError/keyUnavailable(status:)`` when the
    ///   key cannot be had, ``PersistenceError/corruptData`` when encryption fails.
    public func seal(
        _ plaintext: borrowing SecretBytes,
        context: String,
        allowKeyCreation: Bool
    ) throws(PersistenceError) -> Data {
        try keys.withKey(creatingIfMissing: allowKeyCreation) { (material) throws(PersistenceError) -> Data in
            let sealed: AES.GCM.SealedBox
            do {
                sealed = try plaintext.withUnsafeBytes { bytes in
                    try AES.GCM.seal(
                        bytes,
                        using: SymmetricKey(data: material),
                        authenticating: Data(context.utf8)
                    )
                }
            } catch {
                throw .corruptData
            }
            guard let combined = sealed.combined else {
                throw .corruptData
            }
            return Data([Self.envelopeVersion]) + combined
        }
    }

    /// Decrypts an envelope.
    ///
    /// - Parameters:
    ///   - envelope: The stored envelope.
    ///   - context: The row identity the envelope must be bound to.
    /// - Returns: The secret, in a wiping buffer.
    /// - Throws: ``PersistenceError/unsupportedVersion(found:supported:)`` for an unknown envelope version,
    ///   ``PersistenceError/missingKey`` when no key exists, ``PersistenceError/corruptData`` when the
    ///   envelope does not authenticate.
    public func open(_ envelope: Data, context: String) throws(PersistenceError) -> SecretBytes {
        guard let version = envelope.first, version == Self.envelopeVersion else {
            throw .unsupportedVersion(found: Int(envelope.first ?? 0), supported: Int(Self.envelopeVersion))
        }
        return try keys
            .withKey(creatingIfMissing: false) { (material) throws(PersistenceError) -> SecretBytes in
                do {
                    var opened = try AES.GCM.open(
                        AES.GCM.SealedBox(combined: envelope.dropFirst()),
                        using: SymmetricKey(data: material),
                        authenticating: Data(context.utf8)
                    )
                    return SecretBytes(wiping: &opened)
                } catch {
                    throw .corruptData
                }
            }
    }
}
