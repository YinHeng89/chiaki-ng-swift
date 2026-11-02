import ChiakiModels

/// The Kakusan device store as the C++ device store adapter reaches it through ``CoreStoreGateway``.
///
/// Every method takes and returns only what the generated C++ header can represent. Failures come back as
/// `false` or `nil`; the cause is reported by the store itself.
public final class CoreDeviceGateway {
    private let devices: any DeviceStoring

    /// Creates the gateway over the device store.
    ///
    /// - Parameter devices: Where the Kakusan identity and remembered devices are persisted.
    init(devices: any DeviceStoring) {
        self.devices = devices
    }

    /// Copies the Kakusan identity into buffers the caller owns.
    ///
    /// - Parameters:
    ///   - seed: A buffer of at least `ChiakiModels/StoredDeviceIdentity/seedLength` bytes.
    ///   - key: A buffer of at least `ChiakiModels/DeviceIdentityKey/byteCount` bytes.
    /// - Returns: Whether the identity was copied, is absent, or could not be read.
    public func loadDeviceIdentity(seed: UnsafeMutableRawPointer,
                                   key: UnsafeMutableRawPointer) -> CoreIdentityLoad {
        let identity: StoredDeviceIdentity?
        do {
            identity = try devices.identity()
        } catch {
            return .unavailable
        }
        guard let identity else {
            return .absent
        }
        identity.seed.withUnsafeBytes {
            UnsafeMutableRawBufferPointer(start: seed, count: $0.count).copyMemory(from: $0)
        }
        identity.key.bytes.withUnsafeBytes {
            UnsafeMutableRawBufferPointer(start: key, count: $0.count).copyMemory(from: $0)
        }
        return .present
    }

    /// Saves the Kakusan identity, copying its seed straight into a wiping buffer.
    ///
    /// - Parameters:
    ///   - seed: Exactly `ChiakiModels/StoredDeviceIdentity/seedLength` seed bytes.
    ///   - key: Exactly 32 public key bytes.
    ///   - fingerprint: Exactly 32 fingerprint bytes.
    /// - Returns: `true` when the identity was saved.
    public func saveDeviceIdentity(
        seed: UnsafeRawPointer,
        key: UnsafeRawPointer,
        fingerprint: UnsafeRawPointer
    ) -> Bool {
        let length = StoredDeviceIdentity.seedLength
        let secret = SecretBytes(count: length) { buffer in
            buffer.copyMemory(from: UnsafeRawBufferPointer(start: seed, count: length))
        }
        guard let identityKey = CoreRawBytes.deviceKey(key),
              let print = CoreRawBytes.fingerprint(fingerprint),
              let identity = StoredDeviceIdentity(seed: secret, key: identityKey, fingerprint: print)
        else {
            return false
        }
        do {
            try devices.save(identity)
            return true
        } catch {
            return false
        }
    }

    /// Loads every remembered Kakusan device.
    ///
    /// - Returns: The ledger, or `nil` when the store could not be read.
    public func loadDevices() -> CoreDeviceLedger? {
        do {
            return try CoreDeviceLedger(devices.rememberedDevices())
        } catch {
            return nil
        }
    }

    /// Saves a remembered Kakusan device.
    ///
    /// - Parameters:
    ///   - key: Exactly 32 public key bytes.
    ///   - fingerprint: Exactly 32 fingerprint bytes.
    ///   - nickname: The nickname.
    ///   - firstVerifiedAt: When it was first verified, in milliseconds since 1970.
    ///   - lastSeenAt: When it was last seen, in milliseconds since 1970.
    /// - Returns: `true` when the device was saved.
    public func saveDevice(
        key: UnsafeRawPointer,
        fingerprint: UnsafeRawPointer,
        nickname: String,
        firstVerifiedAt: Int64,
        lastSeenAt: Int64
    ) -> Bool {
        guard let identityKey = CoreRawBytes.deviceKey(key),
              let print = CoreRawBytes.fingerprint(fingerprint) else {
            return false
        }
        do {
            try devices.save(
                RememberedDevice(
                    key: identityKey,
                    fingerprint: print,
                    nickname: nickname,
                    firstVerified: Timestamp.date(milliseconds: firstVerifiedAt),
                    lastSeen: Timestamp.date(milliseconds: lastSeenAt)
                )
            )
            return true
        } catch {
            return false
        }
    }

    /// Forgets a remembered Kakusan device.
    ///
    /// - Parameter key: Exactly 32 public key bytes.
    /// - Returns: `true` when the delete succeeded.
    public func forgetDevice(key: UnsafeRawPointer) -> Bool {
        guard let identityKey = CoreRawBytes.deviceKey(key) else {
            return false
        }
        do {
            try devices.forget(identityKey)
            return true
        } catch {
            return false
        }
    }
}

/// Every remembered Kakusan device, handed to a C++ store adapter in one load.
public final class CoreDeviceLedger {
    /// The devices in the order they were first saved.
    public let devices: [CoreDeviceRecord]

    /// Mirrors a load from the device store.
    ///
    /// - Parameter devices: The loaded devices.
    init(_ devices: [RememberedDevice]) {
        self.devices = devices.map(CoreDeviceRecord.init)
    }
}

/// A remembered Kakusan device as the C++ store adapters read it. Times are milliseconds since 1970.
public struct CoreDeviceRecord {
    /// The 32 public key bytes.
    public let key: [UInt8]

    /// The 32 fingerprint bytes.
    public let fingerprint: [UInt8]

    /// The nickname.
    public let nickname: String

    /// When the device was first verified.
    public let firstVerifiedAt: Int64

    /// When the device was last seen.
    public let lastSeenAt: Int64

    /// Mirrors a remembered device.
    ///
    /// - Parameter device: The device.
    init(_ device: RememberedDevice) {
        key = device.key.bytes
        fingerprint = device.fingerprint.bytes
        nickname = device.nickname
        firstVerifiedAt = Timestamp.milliseconds(of: device.firstVerified)
        lastSeenAt = Timestamp.milliseconds(of: device.lastSeen)
    }
}

/// What loading the Kakusan identity found, as the C++ store adapters see it.
public enum CoreIdentityLoad {
    /// The store could not be read or the seed did not open.
    case unavailable

    /// No identity was created yet.
    case absent

    /// The identity was copied into the caller's buffers.
    case present
}
