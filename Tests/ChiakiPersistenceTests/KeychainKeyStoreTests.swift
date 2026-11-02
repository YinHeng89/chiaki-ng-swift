import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import Synchronization
import Testing

@Suite struct KeychainKeyStoreTests {
    final class Calls: Sendable {
        let reads = Mutex(0)
        let creates = Mutex(0)
    }

    func source(_ calls: Calls, stored: [UInt8]?) -> KeySource {
        KeySource(
            read: { () throws(PersistenceError) -> SecretBytes? in
                calls.reads.withLock {
                    $0 += 1
                }
                guard var copy = stored else {
                    return nil
                }
                return SecretBytes(wiping: &copy)
            },
            create: { (proposed: borrowing SecretBytes) throws(PersistenceError) -> SecretBytes in
                calls.creates.withLock {
                    $0 += 1
                }
                return proposed.clone()
            }
        )
    }

    func secret(_ text: String) -> SecretBytes {
        var bytes = Array(text.utf8)
        return SecretBytes(wiping: &bytes)
    }

    @Test func concurrentCipherOperationsReadTheKeyOnce() async throws {
        let calls = Calls()
        let cipher = CredentialCipher(keys: KeychainKeyStore(source: source(
            calls,
            stored: Array(repeating: 7, count: 32)
        )))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    let envelope = try cipher.seal(
                        secret("synthetic credentials"),
                        context: "test",
                        allowKeyCreation: false
                    )
                    let opened = try cipher.open(envelope, context: "test").withUnsafeBytes {
                        Data($0)
                    }
                    #expect(opened == Data("synthetic credentials".utf8))
                }
            }
            try await group.waitForAll()
        }
        #expect(calls.reads.withLock { $0 } == 1)
        #expect(calls.creates.withLock { $0 } == 0)
    }

    @Test func aKeyIsCreatedOnlyWhenAllowedAndThenCached() throws {
        let calls = Calls()
        let store = KeychainKeyStore(source: source(calls, stored: nil))
        let cipher = CredentialCipher(keys: store)
        #expect(throws: PersistenceError.missingKey) {
            try cipher.seal(secret("synthetic"), context: "test", allowKeyCreation: false)
        }
        let envelope = try cipher.seal(secret("synthetic"), context: "test", allowKeyCreation: true)
        _ = try cipher.open(envelope, context: "test")
        #expect(calls.creates.withLock { $0 } == 1)
        #expect(calls.reads.withLock { $0 } == 2)
    }

    @Test func anEnvelopeOpensOnlyInItsOwnContext() throws {
        let cipher = CredentialCipher(keys: KeychainKeyStore(source: .memory()))
        let envelope = try cipher.seal(secret("synthetic"), context: "row:1", allowKeyCreation: true)
        #expect(throws: PersistenceError.corruptData) {
            _ = try cipher.open(envelope, context: "row:2")
        }
        #expect(throws: PersistenceError.unsupportedVersion(found: 2, supported: 1)) {
            _ = try cipher.open(Data([2]) + envelope.dropFirst(), context: "row:1")
        }
    }

    @Test func aKeyOfTheWrongLengthIsRefusedAndNotCached() throws {
        let calls = Calls()
        let store = KeychainKeyStore(source: source(calls, stored: Array(repeating: 1, count: 16)))
        for _ in 0 ..< 2 {
            #expect(throws: PersistenceError.keyUnavailable(status: nil)) {
                try store.withKey(creatingIfMissing: false) { _ in
                }
            }
        }
        #expect(calls.reads.withLock { $0 } == 2)
    }

    @Test func memoryKeysAreSharedWithinAScopeOnly() throws {
        let scope = UUID().uuidString
        let first = CredentialCipher(keys: KeychainKeyStore(source: .memory(scope: scope)))
        let second = CredentialCipher(keys: KeychainKeyStore(source: .memory(scope: scope)))
        let stranger = CredentialCipher(keys: KeychainKeyStore(source: .memory(scope: UUID().uuidString)))
        let envelope = try first.seal(secret("synthetic"), context: "test", allowKeyCreation: true)
        _ = try second.open(envelope, context: "test")
        #expect(throws: PersistenceError.missingKey) {
            _ = try stranger.open(envelope, context: "test")
        }
    }

    @Test func theLiveKeychainIsRefusedInATestProcess() {
        #expect(throws: PersistenceError.refusedLiveData) {
            try KeySource.keychain()
        }
    }
}
