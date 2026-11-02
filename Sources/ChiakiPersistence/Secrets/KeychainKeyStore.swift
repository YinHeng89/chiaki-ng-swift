import ChiakiModels
import CryptoKit
import Foundation
import Synchronization

/// Holds the credential encryption key for the life of the process, read from its ``KeySource`` once.
///
/// The cached key lives in `ChiakiModels/SecretBytes`, so it is wiped when the store is destroyed. Every
/// cipher operation borrows it through ``withKey(creatingIfMissing:_:)`` while the store's lock is held, so
/// concurrent operations unlock the Keychain only once.
public final class KeychainKeyStore: Sendable {
    /// The length of the key in bytes.
    public static let keyLength = 32

    private let source: KeySource
    private let cached = Mutex<SecretBytes?>(nil)

    /// Creates a store over a key source.
    ///
    /// - Parameter source: Where the key is read from and created in.
    public init(source: KeySource) {
        self.source = source
    }

    /// Lends the key to a closure, reading it from the source the first time.
    ///
    /// - Parameters:
    ///   - creatingIfMissing: Whether a new key may be generated and stored when the source has none.
    ///   - body: Uses the key bytes. The pointer is valid only for the duration of `body`.
    /// - Returns: What `body` returns.
    /// - Throws: ``PersistenceError/missingKey`` when no key exists and none may be created,
    ///   ``PersistenceError/keyUnavailable(status:)`` when the source fails or returns a key of the wrong
    ///   length, or the error `body` throws.
    public func withKey<Result: ~Copyable>(
        creatingIfMissing: Bool,
        _ body: (UnsafeRawBufferPointer) throws(PersistenceError) -> Result
    ) throws(PersistenceError) -> Result {
        var outcome: Result?
        try cached.withLock { (key: inout SecretBytes?) throws(PersistenceError) in
            if key == nil {
                key = try load(creatingIfMissing: creatingIfMissing)
            }
            switch key {
            case .some(let loaded):
                outcome = try loaded.withUnsafeBytes(body)
            case .none:
                throw .missingKey
            }
        }
        switch consume outcome {
        case .some(let result):
            return result
        case .none:
            throw .missingKey
        }
    }

    private func load(creatingIfMissing: Bool) throws(PersistenceError) -> SecretBytes? {
        switch try source.read() {
        case .some(let stored):
            return try Self.adopt(stored)
        case .none:
            break
        }
        guard creatingIfMissing else {
            return nil
        }
        let generated = SymmetricKey(size: .bits256)
        let proposed = SecretBytes(count: Self.keyLength) { buffer in
            generated.withUnsafeBytes { key in
                buffer.copyMemory(from: key)
            }
        }
        return try Self.adopt(source.create(proposed))
    }

    private static func adopt(_ material: consuming SecretBytes) throws(PersistenceError) -> SecretBytes {
        guard material.count == keyLength else {
            throw .keyUnavailable(status: nil)
        }
        return material
    }
}
