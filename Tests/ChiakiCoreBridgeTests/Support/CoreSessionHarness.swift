import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB

struct CoreSessionHarness {
    let database: AppDatabase
    let repositories: AppRepositories
    let catalog: URL

    var repository: ConsoleRepository {
        repositories.consoles
    }

    init() throws {
        database = try AppDatabase(path: nil, keys: KeychainKeyStore(source: .memory()))
        repositories = AppRepositories(database: database)
        catalog = FileManager.default.temporaryDirectory.appendingPathComponent(
            "chiaki-core-bridge-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
    }

    func open(
        consoles: (any ConsoleStoring)? = nil,
        credentials: (any CredentialStoring)? = nil,
        datacenters: (any DatacenterStoring)? = nil,
        devices: (any DeviceStoring)? = nil
    ) throws -> CoreSession {
        try CoreSession.open(
            catalog: catalog,
            consoles: consoles ?? repositories.consoles,
            credentials: credentials ?? repositories.credentials,
            datacenters: datacenters ?? repositories.datacenters,
            devices: devices ?? repositories.devices
        )
    }

    func addProfile(_ account: AccountID) throws {
        try database.write { database in
            try database.execute(
                sql: "INSERT INTO profiles(id, display_name, auth_method, psn_account_id) "
                    + "VALUES (?, 'Player', 'account_id', ?)",
                arguments: [UUID().uuidString, account.data]
            )
        }
    }

    func pairing(account: AccountID, console: HardwareID, keys: (UInt8, UInt8)) -> StoredPairing? {
        var registration = [UInt8](repeating: keys.0, count: PairingCredentials.keyLength)
        var remotePlay = [UInt8](repeating: keys.1, count: PairingCredentials.keyLength)
        guard let credentials = PairingCredentials(
            registrationKey: SecretBytes(wiping: &registration),
            remotePlayKey: SecretBytes(wiping: &remotePlay),
            keyType: 2
        ) else {
            return nil
        }
        return StoredPairing(account: account, console: console, credentials: credentials, deviceUID: nil)
    }

    func remove() {
        try? FileManager.default.removeItem(at: catalog)
    }
}
