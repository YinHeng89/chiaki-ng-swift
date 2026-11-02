import ChiakiBridge
import ChiakiModels
import ChiakiPersistence
import ChiakiStoreAdapters
import CxxStdlib
import Foundation

/// The opened streaming core.
///
/// Opening hands the core its persistent stores as C++ store adapters over one
/// `ChiakiPersistence/CoreStoreGateway`: consoles and pairings, signed-in accounts, datacenter measurements
/// and the Kakusan identity are read and written by the Swift stores passed in. The core itself lives in
/// the bridge's one process slot, so only one session can be open at a time; ``close()`` releases it.
public final class CoreSession: Sendable {
    private init() {}

    /// Opens the core with its stores.
    ///
    /// - Parameters:
    ///   - catalog: The folder the core keeps its catalog records in.
    ///   - consoles: Where consoles and pairings are persisted.
    ///   - credentials: Where signed-in accounts and home users are persisted.
    ///   - datacenters: Where datacenter measurements are persisted.
    ///   - devices: Where the Kakusan identity and remembered devices are persisted.
    /// - Returns: The open session.
    /// - Throws: ``CoreOpenFailure/alreadyOpen`` when a session is open, ``CoreOpenFailure/unavailable``
    ///   when the core refused to open.
    public static func open(
        catalog: URL,
        consoles: any ConsoleStoring,
        credentials: any CredentialStoring,
        datacenters: any DatacenterStoring,
        devices: any DeviceStoring
    ) throws(CoreOpenFailure) -> CoreSession {
        guard !chiaki_bridge.CoreSession.is_open() else {
            throw .alreadyOpen
        }
        let gateway = CoreStoreGateway(
            consoles: consoles, credentials: credentials, datacenters: datacenters, devices: devices
        )
        let opened = gateway.withUnsafeHandle { handle in
            chiaki_bridge.CoreSession.open(
                std.string(catalog.path),
                chiaki_store_adapters.StoreAdapters.credential_store(handle),
                chiaki_store_adapters.StoreAdapters.console_store(handle),
                chiaki_store_adapters.StoreAdapters.datacenter_store(handle),
                chiaki_store_adapters.StoreAdapters.device_store(handle)
            )
        }
        guard opened else {
            throw .unavailable
        }
        return CoreSession()
    }

    /// Whether a session is open in this process.
    public static var isOpen: Bool {
        chiaki_bridge.CoreSession.is_open()
    }

    /// The version and source commit the linked core was built as, which needs no open session.
    public static var build: CoreBuild {
        let facts = chiaki_bridge.CoreSession.version()
        return CoreBuild(version: String(facts.version), commit: String(facts.commit))
    }

    /// Signs users in and out and reads what the core knows about them.
    public var users: UsersBridge {
        UsersBridge()
    }

    /// Reads and reveals the credentials the core holds for users.
    public var credentials: CredentialsBridge {
        CredentialsBridge()
    }

    /// Manages the consoles the core knows.
    public var consoles: ConsoleBridge {
        ConsoleBridge()
    }

    /// Searches the local network for consoles.
    public var discovery: DiscoveryBridge {
        DiscoveryBridge()
    }

    /// Lists and starts the titles installed on an account's consoles.
    public var consoleTitles: ConsoleTitlesBridge {
        ConsoleTitlesBridge()
    }

    /// Lists the consoles PSN holds for an account.
    public var accountConsoles: AccountConsolesBridge {
        AccountConsolesBridge()
    }

    /// Reads accounts' cloud catalogs.
    public var catalog: CatalogBridge {
        CatalogBridge()
    }

    /// Asks the store and the catalog about single titles.
    public var titleChecks: TitleChecksBridge {
        TitleChecksBridge()
    }

    /// Reaches the Kakusan identity, remembered devices and invitations outside of a shared stream.
    public var kakusanDevices: KakusanDevicesBridge {
        KakusanDevicesBridge()
    }

    /// Reads and clears the core's on-disk caches.
    public var caches: CachesBridge {
        CachesBridge()
    }

    /// Reads and clears the core's log of HTTP exchanges.
    public var httpCalls: HTTPCallsBridge {
        HTTPCallsBridge()
    }

    /// Reads the core's own diagnostic lines between streams.
    public var log: CoreLogBridge {
        CoreLogBridge()
    }

    /// Loads every saved console and pairing into the core.
    ///
    /// - Returns: How many consoles were taken back, or `nil` when the store could not be read.
    public func rememberSavedConsoles() -> RememberedConsoles? {
        let loaded = chiaki_bridge.CoreSession.remember_saved_consoles()
        guard loaded.loaded else {
            return nil
        }
        return RememberedConsoles(remembered: Int(loaded.remembered), rejected: Int(loaded.rejected))
    }

    /// The facts the core holds for a console.
    ///
    /// - Parameter id: The console's hardware id.
    /// - Returns: The facts, or `nil` when the core does not know the console.
    public func console(_ id: HardwareID) -> StoredConsole? {
        chiaki_bridge.CoreSession.console(chiaki_bridge.Bytes(id.bytes)).value.flatMap(
            ConsoleFactsReader.console
        )
    }

    /// Whether the core holds any pairing with a console.
    ///
    /// - Parameter id: The console's hardware id.
    /// - Returns: `true` when the console is known and paired.
    public func isPaired(_ id: HardwareID) -> Bool {
        chiaki_bridge.CoreSession.console(chiaki_bridge.Bytes(id.bytes)).value?.paired ?? false
    }

    /// Hands the keys and fingerprints the core derives to a device store whose rows still hold placeholders.
    ///
    /// Rows written before the core derived them hold zeros; this asks the core for this installation's key
    /// and each remembered device's fingerprint and lets the repository replace only the placeholders.
    ///
    /// - Parameter devices: The device repository.
    /// - Throws: The repository's `ChiakiPersistence/PersistenceError` when it cannot be read or written.
    public func restoreDerivedDeviceColumns(in devices: KakusanDeviceRepository) throws(PersistenceError) {
        #if CHIAKI_KAKUSAN
            guard try devices.hasUnderivedColumns() else {
                return
            }
            let identity = chiaki_bridge.KakusanDevices.this_device()
            let remembered = chiaki_bridge.KakusanDevices.remembered()
            let listed = remembered.kind() == .listed
                ? remembered.devices()
                : chiaki_bridge.DeviceList()
            var fingerprints: [DeviceIdentityKey: DeviceKeyFingerprint] = [:]
            for device in listed {
                if let key = DeviceIdentityKey(bytes: Array(device.identity)),
                   let fingerprint = DeviceKeyFingerprint(bytes: Array(device.fingerprint)) {
                    fingerprints[key] = fingerprint
                }
            }
            try devices.restoreDerivedColumns(
                identityKey: identity.kind() == .identified
                    ? DeviceIdentityKey(bytes: Array(identity.device().identity))
                    : DeviceIdentityKey(bytes: []),
                fingerprints: fingerprints
            )
        #endif
    }

    /// Closes the core. Its stores are released once every operation using them has finished.
    public func close() {
        chiaki_bridge.CoreSession.close()
    }
}

/// Why the core could not be opened.
public enum CoreOpenFailure: Error, Hashable, Sendable {
    /// A core session is open already in this process.
    case alreadyOpen

    /// The core refused the configuration or a platform service it needs is missing.
    case unavailable
}

/// How many saved consoles the core took back when it loaded the console store.
public struct RememberedConsoles: Hashable, Sendable {
    /// Consoles the core now knows from the store.
    public let remembered: Int

    /// Saved rows the core refused, such as pairings whose console is not saved.
    public let rejected: Int

    /// Describes one load.
    ///
    /// - Parameters:
    ///   - remembered: Consoles taken back.
    ///   - rejected: Rows refused.
    public init(remembered: Int, rejected: Int) {
        self.remembered = remembered
        self.rejected = rejected
    }
}
