import ChiakiModels

/// The façade the C++ store adapters in `ChiakiStoreAdapters` call to reach persistence.
///
/// The class is exposed to C++ through the generated `ChiakiPersistence-Swift.h` header. Each adapter takes the
/// gateway of its own store: ``consoles``, ``credentials``, ``datacenters`` or ``devices``. Those take and
/// return only what that header can represent: strings, integers, Booleans, byte arrays, raw pointers,
/// optionals, the `Core` enums and the record, draft and ledger types. Fixed-length identifiers arrive as raw
/// pointers to exactly their byte count. Failures come back as `false` or `nil`; the cause is reported by the
/// store itself.
///
/// Swift hands a gateway to C++ with ``withUnsafeHandle(_:)``; the adapter turns the handle back into a
/// strong reference with ``adopting(_:)`` before the closure returns.
public final class CoreStoreGateway {
    /// The console store's gateway.
    public let consoles: CoreConsoleGateway

    /// The credential store's gateway.
    public let credentials: CoreCredentialGateway

    /// The datacenter store's gateway.
    public let datacenters: CoreDatacenterGateway

    /// The device store's gateway.
    public let devices: CoreDeviceGateway

    /// Creates a gateway over the core's stores.
    ///
    /// - Parameters:
    ///   - consoles: Where consoles and pairings are persisted.
    ///   - credentials: Where signed-in accounts and home users are persisted.
    ///   - datacenters: Where datacenter measurements are persisted.
    ///   - devices: Where the Kakusan identity and remembered devices are persisted.
    public init(
        consoles: any ConsoleStoring,
        credentials: any CredentialStoring,
        datacenters: any DatacenterStoring,
        devices: any DeviceStoring
    ) {
        self.consoles = CoreConsoleGateway(consoles: consoles)
        self.credentials = CoreCredentialGateway(credentials: credentials)
        self.datacenters = CoreDatacenterGateway(datacenters: datacenters)
        self.devices = CoreDeviceGateway(devices: devices)
    }

    /// Turns a handle made by ``withUnsafeHandle(_:)`` back into the gateway.
    ///
    /// - Parameter handle: The handle, valid only while the closure that produced it runs.
    /// - Returns: A strong reference to the gateway.
    public static func adopting(_ handle: UnsafeMutableRawPointer) -> CoreStoreGateway {
        Unmanaged<CoreStoreGateway>.fromOpaque(handle).takeUnretainedValue()
    }

    /// Lends an unretained handle to the gateway for a C++ adapter to adopt.
    ///
    /// - Parameter body: Passes the handle to C++, which adopts it before returning.
    /// - Returns: What `body` returns.
    /// - Throws: The error `body` throws.
    public func withUnsafeHandle<Result>(_ body: (UnsafeMutableRawPointer) throws -> Result) rethrows
        -> Result {
        try withExtendedLifetime(self) {
            try body(Unmanaged.passUnretained(self).toOpaque())
        }
    }
}

/// Reads the fixed-length identifiers and keys the C++ store adapters pass as raw pointers.
///
/// Each pointer refers to exactly the byte count of its type; keys are copied straight into wiping buffers.
enum CoreRawBytes {
    /// Reads an account id.
    ///
    /// - Parameter bytes: Exactly eight account id bytes, least significant first.
    /// - Returns: The account id, or `nil` when the bytes are not one.
    static func account(_ bytes: UnsafeRawPointer) -> AccountID? {
        AccountID(bytes: UnsafeRawBufferPointer(start: bytes, count: AccountID.byteCount))
    }

    /// Reads a console's hardware id.
    ///
    /// - Parameter bytes: Exactly six hardware id bytes.
    /// - Returns: The hardware id, or `nil` when the bytes are not one.
    static func hardware(_ bytes: UnsafeRawPointer) -> HardwareID? {
        HardwareID(bytes: UnsafeRawBufferPointer(start: bytes, count: HardwareID.byteCount))
    }

    /// Reads a Kakusan device's public key.
    ///
    /// - Parameter bytes: Exactly 32 public key bytes.
    /// - Returns: The key, or `nil` when the bytes are not one.
    static func deviceKey(_ bytes: UnsafeRawPointer) -> DeviceIdentityKey? {
        DeviceIdentityKey(bytes: UnsafeRawBufferPointer(start: bytes, count: DeviceIdentityKey.byteCount))
    }

    /// Reads a Kakusan device's key fingerprint.
    ///
    /// - Parameter bytes: Exactly 32 fingerprint bytes.
    /// - Returns: The fingerprint, or `nil` when the bytes are not one.
    static func fingerprint(_ bytes: UnsafeRawPointer) -> DeviceKeyFingerprint? {
        DeviceKeyFingerprint(bytes: UnsafeRawBufferPointer(
            start: bytes,
            count: DeviceKeyFingerprint.byteCount
        ))
    }

    /// Copies a pairing key into a wiping buffer.
    ///
    /// - Parameter bytes: Exactly `ChiakiModels/PairingCredentials/keyLength` key bytes.
    /// - Returns: The key.
    static func pairingKey(_ bytes: UnsafeRawPointer) -> SecretBytes {
        SecretBytes(count: PairingCredentials.keyLength) { buffer in
            buffer.copyMemory(from: UnsafeRawBufferPointer(start: bytes, count: PairingCredentials.keyLength))
        }
    }
}
