import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import GRDB

struct TestDatabase {
    let database: AppDatabase

    init(path: String? = nil, keys: KeychainKeyStore = KeychainKeyStore(source: .memory())) throws {
        database = try AppDatabase(path: path, keys: keys)
    }

    static func scratchFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("chiaki-persistence-\(UUID().uuidString).sqlite")
    }

    @discardableResult
    func addProfile(_ account: AccountID, id: ProfileID = ProfileID(),
                    name: String = "Player") throws -> ProfileID {
        try database.write { database in
            try database.execute(
                sql: """
                INSERT INTO profiles(id, display_name, auth_method, psn_account_id) VALUES (?, ?, 'account_id', ?)
                """,
                arguments: [id.uuidString, name, account.data]
            )
        }
        return id
    }

    func scalar<Value: DatabaseValueConvertible>(_ sql: String,
                                                 _ arguments: StatementArguments = []) throws -> Value? {
        try database.read { database in
            try Value.fetchOne(database, sql: sql, arguments: arguments)
        }
    }

    func secret(_ byte: UInt8, count: Int = PairingCredentials.keyLength) -> SecretBytes {
        var bytes = [UInt8](repeating: byte, count: count)
        return SecretBytes(wiping: &bytes)
    }

    func pairing(
        account: AccountID,
        console: HardwareID,
        keys: (UInt8, UInt8),
        keyType: UInt32 = 2,
        device: ConsoleDeviceUID? = nil
    ) -> StoredPairing? {
        guard let credentials = PairingCredentials(
            registrationKey: secret(keys.0), remotePlayKey: secret(keys.1), keyType: keyType
        ) else {
            return nil
        }
        return StoredPairing(account: account, console: console, credentials: credentials, deviceUID: device)
    }
}
