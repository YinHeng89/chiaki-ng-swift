import ChiakiModels
import Foundation
import Security
import Synchronization

/// Where the 32-byte credential encryption key is read from and created in.
///
/// ``keychain(service:in:)`` is the user's login Keychain; ``memory(scope:)`` and ``memory()`` keep the key
/// in the process for scratch locations and tests. ``KeychainKeyStore`` caches what a source returns. Every
/// copy of the key a source makes is a wiping `ChiakiModels/SecretBytes`; the buffers the Security framework
/// keeps for its own calls are outside its reach.
public struct KeySource: Sendable {
    /// The Keychain service the app stores its key under.
    public static let defaultService = AppIdentity.keychainService

    /// Reads the stored key, or returns `nil` when none exists.
    public let read: @Sendable () throws(PersistenceError) -> SecretBytes?

    /// Stores a proposed key unless one exists already, and returns the key that is stored.
    public let create: @Sendable (borrowing SecretBytes) throws(PersistenceError) -> SecretBytes

    /// Builds a source from its two operations.
    ///
    /// - Parameters:
    ///   - read: Reads the stored key.
    ///   - create: Stores a proposed key and returns the stored one.
    public init(
        read: @escaping @Sendable () throws(PersistenceError) -> SecretBytes?,
        create: @escaping @Sendable (borrowing SecretBytes) throws(PersistenceError) -> SecretBytes
    ) {
        self.read = read
        self.create = create
    }

    /// The user's login Keychain, under `service`.
    ///
    /// - Parameters:
    ///   - service: The Keychain service name.
    ///   - process: The process asking.
    /// - Returns: The Keychain source.
    /// - Throws: ``PersistenceError/refusedLiveData`` in a test harness.
    public static func keychain(
        service: String = defaultService,
        in process: HostProcess = .current
    ) throws(PersistenceError) -> KeySource {
        guard !process.isHarness else {
            throw .refusedLiveData
        }
        return KeySource(
            read: { () throws(PersistenceError) -> SecretBytes? in
                try readKeychain(service: service)
            },
            create: { (proposed: borrowing SecretBytes) throws(PersistenceError) -> SecretBytes in
                try createKeychain(service: service, proposed: proposed)
            }
        )
    }

    /// A key kept only in this process, created on first use and shared by every source with the same scope.
    ///
    /// Two databases opened at one scratch location in one process must read each other's envelopes, so the
    /// key is held per scope for the life of the process, as the Keychain holds it per service.
    ///
    /// - Parameter scope: The location the key belongs to, such as the scratch support folder.
    /// - Returns: The source for that scope.
    public static func memory(scope: String) -> KeySource {
        let slot = scopedMemory.withLock { slots in
            if let existing = slots[scope] {
                return existing
            }
            let created = MemorySlot()
            slots[scope] = created
            return created
        }
        return memory(slot)
    }

    /// A key kept only in this process, created on first use and shared with no other source.
    ///
    /// - Returns: A source no other call shares.
    public static func memory() -> KeySource {
        memory(MemorySlot())
    }

    private final class MemorySlot: Sendable {
        let material = Mutex<SecretBytes?>(nil)
    }

    private static let scopedMemory = Mutex<[String: MemorySlot]>([:])

    private static func memory(_ slot: MemorySlot) -> KeySource {
        KeySource(
            read: { () throws(PersistenceError) -> SecretBytes? in
                slot.material.withLock { stored in
                    switch stored {
                    case .some(let held):
                        held.clone()
                    case .none:
                        nil
                    }
                }
            },
            create: { (proposed: borrowing SecretBytes) throws(PersistenceError) -> SecretBytes in
                slot.material.withLock { stored in
                    let held = switch stored.take() {
                    case .some(let existing):
                        existing
                    case .none:
                        proposed.clone()
                    }
                    let handed = held.clone()
                    stored = consume held
                    return handed
                }
            }
        )
    }

    private static func query(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "encryption-key-v1"
        ]
    }

    private static func readKeychain(service: String) throws(PersistenceError) -> SecretBytes? {
        var request = query(service: service)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let result, CFGetTypeID(result) == CFDataGetTypeID() else {
            throw .keyUnavailable(status: status)
        }
        return adopt(unsafeDowncast(result, to: CFData.self))
    }

    private static func adopt(_ data: CFData) -> SecretBytes {
        let length = CFDataGetLength(data)
        return SecretBytes(count: length) { buffer in
            guard let base = buffer.baseAddress else {
                return
            }
            CFDataGetBytes(
                data,
                CFRange(location: 0, length: length),
                base.assumingMemoryBound(to: UInt8.self)
            )
        }
    }

    private static func createKeychain(
        service: String,
        proposed: borrowing SecretBytes
    ) throws(PersistenceError) -> SecretBytes {
        let status = proposed.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  let borrowed = CFDataCreateWithBytesNoCopy(nil, base, bytes.count, kCFAllocatorNull)
            else {
                return errSecAllocate
            }
            var request = query(service: service)
            request[kSecValueData as String] = borrowed
            request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(request as CFDictionary, nil)
        }
        if status == errSecDuplicateItem, let existing = try readKeychain(service: service) {
            return existing
        }
        guard status == errSecSuccess else {
            throw .keyUnavailable(status: status)
        }
        return proposed.clone()
    }
}
