import ChiakiModels

/// The console store as the C++ console store adapter reaches it through ``CoreStoreGateway``.
///
/// Every method takes and returns only what the generated C++ header can represent. Failures come back as
/// `false` or `nil`; the cause is reported by the store itself.
public final class CoreConsoleGateway {
    private let consoles: any ConsoleStoring

    /// Creates the gateway over the console store.
    ///
    /// - Parameter consoles: Where consoles and pairings are persisted.
    init(consoles: any ConsoleStoring) {
        self.consoles = consoles
    }

    /// Loads every saved console and pairing.
    ///
    /// - Returns: The ledger, or `nil` when the store could not be read.
    public func loadConsoles() -> CoreConsoleLedger? {
        do {
            return try CoreConsoleLedger(consoles.savedConsoles())
        } catch {
            return nil
        }
    }

    /// Saves a console's facts.
    ///
    /// - Parameters:
    ///   - hardwareID: Exactly six hardware id bytes.
    ///   - firmware: The firmware family.
    ///   - name: The display name.
    ///   - nameSource: Who supplied the name.
    ///   - address: The last address, or `nil` to keep the stored one.
    /// - Returns: `true` when the console was saved.
    public func saveConsole(
        hardwareID: UnsafeRawPointer,
        firmware: CoreFirmware,
        name: String,
        nameSource: CoreNameSource,
        address: String?
    ) -> Bool {
        guard let hardware = CoreRawBytes.hardware(hardwareID) else {
            return false
        }
        let console = StoredConsole(
            hardwareID: hardware,
            firmware: firmware.firmware,
            name: name,
            nameSource: nameSource.source,
            address: address
        )
        do {
            try consoles.save(console)
            return true
        } catch {
            return false
        }
    }

    /// Starts a pairing to save.
    ///
    /// - Parameters:
    ///   - accountID: Exactly eight account id bytes, least significant first.
    ///   - hardwareID: Exactly six hardware id bytes.
    /// - Returns: The draft to fill and pass to ``savePairing(_:)``.
    public func beginPairing(accountID: UnsafeRawPointer, hardwareID: UnsafeRawPointer) -> CorePairingDraft {
        CorePairingDraft(account: CoreRawBytes.account(accountID), console: CoreRawBytes.hardware(hardwareID))
    }

    /// Saves a pairing assembled with ``beginPairing(accountID:hardwareID:)``.
    ///
    /// - Parameter draft: The draft; it cannot be saved twice.
    /// - Returns: `true` when the pairing was saved.
    public func savePairing(_ draft: CorePairingDraft) -> Bool {
        guard let pairing = draft.finish() else {
            return false
        }
        do {
            try consoles.save(pairing)
            return true
        } catch {
            return false
        }
    }

    /// Deletes one account's pairing with a console.
    ///
    /// - Parameters:
    ///   - accountID: Exactly eight account id bytes.
    ///   - hardwareID: Exactly six hardware id bytes.
    /// - Returns: `true` when the delete succeeded.
    public func removePairing(accountID: UnsafeRawPointer, hardwareID: UnsafeRawPointer) -> Bool {
        guard let account = CoreRawBytes.account(accountID),
              let hardware = CoreRawBytes.hardware(hardwareID) else {
            return false
        }
        do {
            try consoles.removePairing(account: account, console: hardware)
            return true
        } catch {
            return false
        }
    }

    /// Deletes a console and every pairing with it.
    ///
    /// - Parameter hardwareID: Exactly six hardware id bytes.
    /// - Returns: `true` when the delete succeeded.
    public func removeConsole(hardwareID: UnsafeRawPointer) -> Bool {
        guard let hardware = CoreRawBytes.hardware(hardwareID) else {
            return false
        }
        do {
            try consoles.removeConsole(hardware)
            return true
        } catch {
            return false
        }
    }
}

/// Everything the console store holds, handed to a C++ store adapter in one load.
///
/// The ledger keeps the loaded pairings, whose keys stay in wiping buffers until the adapter copies each
/// pair of keys into memory it owns. The keys are wiped when the ledger is released.
public final class CoreConsoleLedger {
    /// Every saved console.
    public let consoles: [CoreConsoleRecord]

    /// The non-secret parts of every saved pairing, in the order of
    /// ``copyKeys(ofPairing:registrationKey:remotePlayKey:)``.
    public let pairings: [CorePairingRecord]

    private let saved: [StoredPairing]

    /// Mirrors a load from the console store.
    ///
    /// - Parameter saved: The loaded consoles and pairings.
    init(_ saved: SavedConsoles) {
        consoles = saved.consoles.map(CoreConsoleRecord.init)
        pairings = saved.pairings.map(CorePairingRecord.init)
        self.saved = saved.pairings
    }

    /// Copies one pairing's keys into buffers the caller owns.
    ///
    /// - Parameters:
    ///   - index: The pairing's position in ``pairings``.
    ///   - registrationKey: A buffer of at least `ChiakiModels/PairingCredentials/keyLength` bytes.
    ///   - remotePlayKey: A buffer of at least `ChiakiModels/PairingCredentials/keyLength` bytes.
    /// - Returns: `false` when `index` is out of range; nothing is written then.
    public func copyKeys(
        ofPairing index: Int,
        registrationKey: UnsafeMutableRawPointer,
        remotePlayKey: UnsafeMutableRawPointer
    ) -> Bool {
        guard saved.indices.contains(index) else {
            return false
        }
        let pairing = saved[index]
        pairing.credentials.registrationKey.withUnsafeBytes { bytes in
            UnsafeMutableRawBufferPointer(start: registrationKey, count: bytes.count).copyMemory(from: bytes)
        }
        pairing.credentials.remotePlayKey.withUnsafeBytes { bytes in
            UnsafeMutableRawBufferPointer(start: remotePlayKey, count: bytes.count).copyMemory(from: bytes)
        }
        return true
    }
}

/// A saved console as the C++ store adapters read it.
public struct CoreConsoleRecord {
    /// The six hardware id bytes.
    public let hardwareID: [UInt8]

    /// The firmware family.
    public let firmware: CoreFirmware

    /// The display name.
    public let name: String

    /// Who supplied the name.
    public let nameSource: CoreNameSource

    /// The last address, if any.
    public let address: String?

    /// Mirrors saved console facts.
    ///
    /// - Parameter console: The facts.
    init(_ console: StoredConsole) {
        hardwareID = console.hardwareID.bytes
        firmware = CoreFirmware(console.firmware)
        name = console.name
        nameSource = CoreNameSource(console.nameSource)
        address = console.address
    }
}

/// The parts of a saved pairing that are not secret, as the C++ store adapters read them.
///
/// The keys are copied separately with ``CoreConsoleLedger/copyKeys(ofPairing:registrationKey:remotePlayKey:)``
/// straight into buffers the adapter owns and wipes.
public struct CorePairingRecord {
    /// The eight account id bytes, least significant first.
    public let accountID: [UInt8]

    /// The six hardware id bytes of the console.
    public let hardwareID: [UInt8]

    /// The key type the console reported.
    public let keyType: UInt32

    /// The 32 bytes of PSN's identifier for the console, once known.
    public let deviceUID: [UInt8]?

    /// Mirrors the non-secret parts of a pairing.
    ///
    /// - Parameter pairing: The pairing.
    init(_ pairing: StoredPairing) {
        accountID = pairing.account.bytes
        hardwareID = pairing.console.bytes
        keyType = pairing.credentials.keyType
        deviceUID = pairing.deviceUID?.bytes
    }
}

/// A pairing a C++ store adapter assembles before saving it through ``CoreConsoleGateway/savePairing(_:)``.
///
/// The keys are copied from the adapter's memory straight into wiping buffers.
public final class CorePairingDraft {
    private let account: AccountID?
    private let console: HardwareID?
    private var credentials: PairingCredentials?
    private var deviceUID: ConsoleDeviceUID?

    /// Starts a draft.
    ///
    /// - Parameters:
    ///   - account: The account, or `nil` when its bytes were not an account id.
    ///   - console: The console, or `nil` when its bytes were not a hardware id.
    init(account: AccountID?, console: HardwareID?) {
        self.account = account
        self.console = console
    }

    /// Copies the pairing's keys into the draft.
    ///
    /// - Parameters:
    ///   - registrationKey: Exactly `ChiakiModels/PairingCredentials/keyLength` key bytes.
    ///   - remotePlayKey: Exactly `ChiakiModels/PairingCredentials/keyLength` key bytes.
    ///   - keyType: The key type the console reported.
    public func setKeys(registrationKey: UnsafeRawPointer, remotePlayKey: UnsafeRawPointer, keyType: UInt32) {
        credentials = PairingCredentials(
            registrationKey: CoreRawBytes.pairingKey(registrationKey),
            remotePlayKey: CoreRawBytes.pairingKey(remotePlayKey),
            keyType: keyType
        )
    }

    /// Sets PSN's identifier for the console.
    ///
    /// - Parameter bytes: Exactly 32 identifier bytes.
    public func setDeviceUID(_ bytes: UnsafeRawPointer) {
        deviceUID = ConsoleDeviceUID(bytes: UnsafeRawBufferPointer(
            start: bytes,
            count: ConsoleDeviceUID.byteCount
        ))
    }

    /// Hands the assembled pairing over; a second call, or a draft without valid ids and keys, returns `nil`.
    ///
    /// - Returns: The pairing, its keys moved out of the draft.
    func finish() -> StoredPairing? {
        guard let account, let console else {
            return nil
        }
        switch credentials.take() {
        case .some(let credentials):
            return StoredPairing(
                account: account,
                console: console,
                credentials: credentials,
                deviceUID: deviceUID
            )
        case .none:
            return nil
        }
    }
}

/// A console firmware family as the C++ store adapters see it.
///
/// It mirrors `ChiakiModels/ConsoleFirmware` case for case, because the generated C++ header cannot
/// expose a type from another module. The adapters switch over it exhaustively.
public enum CoreFirmware {
    /// A PS4 on system software below 8.0.
    case ps4_8

    /// A PS4 on system software 8.0 up to but not including 10.0.
    case ps4_9

    /// A PS4 on system software 10.0 or later.
    case ps4_10

    /// A PS5.
    case ps5

    /// Mirrors a model firmware family.
    ///
    /// - Parameter firmware: The model value.
    public init(_ firmware: ConsoleFirmware) {
        self = switch firmware {
        case .ps4_8:
            .ps4_8
        case .ps4_9:
            .ps4_9
        case .ps4_10:
            .ps4_10
        case .ps5:
            .ps5
        }
    }

    /// The model firmware family.
    public var firmware: ConsoleFirmware {
        switch self {
        case .ps4_8:
            .ps4_8
        case .ps4_9:
            .ps4_9
        case .ps4_10:
            .ps4_10
        case .ps5:
            .ps5
        }
    }
}

/// A console name source as the C++ store adapters see it.
///
/// It mirrors `ChiakiModels/ConsoleNameSource` case for case, because the generated C++ header cannot
/// expose a type from another module. The adapters switch over it exhaustively.
public enum CoreNameSource {
    /// A generation placeholder.
    case generation

    /// The name PSN holds.
    case account

    /// The nickname stated when the console was paired.
    case pairing

    /// The name stated in a network search reply.
    case discovered

    /// A name the user chose.
    case renamed

    /// Mirrors a model name source.
    ///
    /// - Parameter source: The model value.
    public init(_ source: ConsoleNameSource) {
        self = switch source {
        case .generation:
            .generation
        case .account:
            .account
        case .pairing:
            .pairing
        case .discovered:
            .discovered
        case .renamed:
            .renamed
        }
    }

    /// The model name source.
    public var source: ConsoleNameSource {
        switch self {
        case .generation:
            .generation
        case .account:
            .account
        case .pairing:
            .pairing
        case .discovered:
            .discovered
        case .renamed:
            .renamed
        }
    }
}
