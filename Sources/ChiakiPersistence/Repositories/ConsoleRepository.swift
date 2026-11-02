import ChiakiModels
import Foundation
import GRDB

/// The saved consoles and the pairings with them, in the `consoles` and `registrations` tables.
///
/// Firmware family and name source are stored with each console, so a PS4 keeps its protocol variant and a
/// discovered name can still be replaced by a better one after a restart. Pairing keys are sealed with the
/// database's ``CredentialCipher`` and only ever leave it in wiping buffers.
public final class ConsoleRepository: ConsoleStoring {
    private enum PairingWrite {
        case saved
        case unknownAccount
        case unknownConsole
    }

    private let database: AppDatabase
    private let report: @Sendable (PersistenceError) -> Void

    /// Creates the repository over the app database.
    ///
    /// - Parameters:
    ///   - database: The open database.
    ///   - report: Receives every storage failure before it is turned into a `ChiakiModels/ConsoleStoreFailure`,
    ///     so the cause can be logged. Ignored by default.
    public init(database: AppDatabase, report: @escaping @Sendable (PersistenceError) -> Void = { _ in }) {
        self.database = database
        self.report = report
    }

    /// Loads every saved console and every pairing that decrypts and decodes.
    ///
    /// - Returns: The saved rows.
    /// - Throws: `ChiakiModels/ConsoleStoreFailure/unavailable` when the tables cannot be read.
    public func savedConsoles() throws(ConsoleStoreFailure) -> SavedConsoles {
        let rows = try reporting { () throws(PersistenceError) in
            try database.read { database in
                try (
                    ConsoleRow.fetchAll(database, sql: ConsoleRow.selectSaved),
                    PairingRow.fetchAll(database, sql: PairingRow.selectSaved)
                )
            }
        }
        return SavedConsoles(
            consoles: rows.0.compactMap(\ConsoleRow.stored),
            pairings: rows.1.compactMap(pairing)
        )
    }

    /// Writes a console's facts, keeping its row id and a known address when the facts carry none.
    ///
    /// - Parameter console: The facts to persist.
    /// - Throws: `ChiakiModels/ConsoleStoreFailure/unavailable` when the write failed.
    public func save(_ console: StoredConsole) throws(ConsoleStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                let id = try String.fetchOne(
                    database,
                    sql: ConsoleRow.selectID,
                    arguments: [console.hardwareID.hex]
                )
                    ?? UUID().uuidString
                try database.execute(
                    sql: ConsoleRow.upsert,
                    arguments: ConsoleRow.upsertArguments(console, id: id)
                )
            }
        }
    }

    /// Writes a pairing for the oldest profile holding its account, sealing its keys.
    ///
    /// A new encryption key is created only while no credential of any kind is stored.
    ///
    /// - Parameter pairing: The pairing to persist.
    /// - Throws: `ChiakiModels/ConsoleStoreFailure/unknownAccount` or
    ///   `ChiakiModels/ConsoleStoreFailure/unknownConsole` when either is not saved, and
    ///   `ChiakiModels/ConsoleStoreFailure/unavailable` when the write failed.
    public func save(_ pairing: StoredPairing) throws(ConsoleStoreFailure) {
        let outcome = try reporting { () throws(PersistenceError) in
            try database.write { database in
                try write(pairing, in: database)
            }
        }
        switch outcome {
        case .saved:
            return
        case .unknownAccount:
            throw .unknownAccount
        case .unknownConsole:
            throw .unknownConsole
        }
    }

    /// Deletes one account's pairing with a console.
    ///
    /// - Parameters:
    ///   - account: The account whose pairing goes.
    ///   - console: The console it was with.
    /// - Throws: `ChiakiModels/ConsoleStoreFailure/unavailable` when the delete failed.
    public func removePairing(account: AccountID, console: HardwareID) throws(ConsoleStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(sql: PairingRow.delete, arguments: [account.data, console.hex])
            }
        }
    }

    /// Deletes a console and, by cascade, every pairing with it.
    ///
    /// - Parameter console: The console to delete.
    /// - Throws: `ChiakiModels/ConsoleStoreFailure/unavailable` when the delete failed.
    public func removeConsole(_ console: HardwareID) throws(ConsoleStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(sql: ConsoleRow.delete, arguments: [console.hex])
            }
        }
    }

    /// Every pairing between a profile and a console.
    ///
    /// - Returns: The pairings in the order they were made.
    /// - Throws: ``PersistenceError/corruptData`` when a row breaks its schema, or a database error.
    public func registeredConsoles() throws(PersistenceError) -> [RegisteredConsole] {
        let rows = try database.read { database in
            try Row.fetchAll(database, sql: PairingRow.selectRegistered)
        }
        return try AppDatabase.mapping {
            try rows.map { row in
                guard let profile = try UUID(uuidString: row.decode(String.self, forColumn: "profile_id")),
                      let console = try UUID(uuidString: row.decode(String.self, forColumn: "console_id"))
                else {
                    throw PersistenceError.corruptData
                }
                return try RegisteredConsole(
                    hardwareID: row.decode(String?.self, forColumn: "hardware_id"),
                    id: console,
                    name: row.decode(String.self, forColumn: "name"),
                    accountID: profile,
                    address: row.decode(String.self, forColumn: "address"),
                    ps5: row.decode(String.self, forColumn: "generation") == ConsoleKind.ps5.rawValue,
                    remoteDeviceID: row.decode(Data?.self, forColumn: "remote_device_id")
                )
            }
        }
    }

    /// The console and account a profile streams to, found by the console's address or by PSN's device id.
    ///
    /// - Parameters:
    ///   - profile: The paired profile's id.
    ///   - address: The console's last address, used when `remoteDeviceID` is `nil`.
    ///   - remoteDeviceID: PSN's identifier for the console.
    /// - Returns: The play target.
    /// - Throws: ``PersistenceError/invalidInput`` when no such pairing is saved.
    public func playTarget(
        profile: UUID,
        address: String,
        remoteDeviceID: Data? = nil
    ) throws(PersistenceError) -> PlayTarget {
        let row = try database.read { database in
            try Row.fetchOne(
                database, sql: PairingRow.selectPlayTarget, arguments: [
                    profile.uuidString,
                    remoteDeviceID,
                    address
                ]
            )
        }
        guard let row else {
            throw .invalidInput
        }
        return try AppDatabase.mapping {
            guard let account = try AccountID(bytes: row.decode(Data.self, forColumn: "psn_account_id")),
                  let hardware = try row.decode(String?.self, forColumn: "hardware_id").flatMap({
                      HardwareID(hex: $0)
                  })
            else {
                throw PersistenceError.invalidInput
            }
            return try PlayTarget(
                accountID: account,
                hardwareID: hardware,
                name: row.decode(String.self, forColumn: "name"),
                address: row.decode(String?.self, forColumn: "last_address"),
                ps5: row.decode(String.self, forColumn: "generation") == ConsoleKind.ps5.rawValue,
                remoteDeviceID: row.decode(Data?.self, forColumn: "remote_device_id")
            )
        }
    }

    /// The hardware id of a saved console.
    ///
    /// - Parameter console: The console's row id.
    /// - Returns: The hardware id, or `nil` for an unknown console or one never reached.
    /// - Throws: A database error.
    public func hardwareID(of console: UUID) throws(PersistenceError) -> HardwareID? {
        let hex = try database.read { database in
            try String?
                .fetchOne(database, sql: ConsoleRow.selectHardwareByID, arguments: [console.uuidString]) ??
                nil
        }
        return hex.flatMap {
            HardwareID(hex: $0)
        }
    }

    /// Remembers the address a saved console was discovered at.
    ///
    /// - Parameters:
    ///   - address: The discovered address, already validated by the caller.
    ///   - console: The console's hardware id.
    /// - Returns: What changed.
    /// - Throws: A database error.
    @discardableResult
    public func rememberAddress(_ address: String, of console: HardwareID) throws(PersistenceError)
        -> ConsoleAddressUpdate {
        try database.write { database in
            guard let row = try Row.fetchOne(
                database,
                sql: ConsoleRow.selectAddress,
                arguments: [console.hex]
            )
            else {
                return .unregistered
            }
            let previous = try row.decode(String?.self, forColumn: "last_address")
            guard previous != address else {
                return .unchanged
            }
            try database.execute(sql: ConsoleRow.updateAddress, arguments: [address, console.hex, address])
            return .updated(previous: previous)
        }
    }

    /// Renames a console and sets its address.
    ///
    /// - Parameters:
    ///   - console: The console's row id.
    ///   - name: The new name, trimmed, 1 to 100 characters.
    ///   - address: The new address, trimmed, without whitespace, at most 253 bytes.
    /// - Throws: ``PersistenceError/invalidInput`` for an invalid name or address.
    public func rename(_ console: UUID, name: String, address: String) throws(PersistenceError) {
        let edit = try Self.validatedEdit(name: name, address: address)
        try database.write { database in
            try database.execute(
                sql: ConsoleRow.rename,
                arguments: [edit.name, edit.address, console.uuidString]
            )
        }
    }

    /// Deletes a console by row id; its pairings cascade.
    ///
    /// - Parameter console: The console's row id.
    /// - Throws: A database error.
    public func delete(_ console: UUID) throws(PersistenceError) {
        try database.write { database in
            try database.execute(sql: ConsoleRow.deleteByID, arguments: [console.uuidString])
        }
    }

    /// Trims and checks a console edit.
    ///
    /// - Parameters:
    ///   - name: The new name.
    ///   - address: The new address.
    /// - Returns: The trimmed values.
    /// - Throws: ``PersistenceError/invalidInput`` for an empty or overlong name, or an empty, overlong or
    ///   spaced address.
    static func validatedEdit(name: String,
                              address: String) throws(PersistenceError) -> (name: String, address: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !address.isEmpty, address.utf8.count <= 253,
              !address.contains(where: \.isWhitespace)
        else {
            throw .invalidInput
        }
        return (name, address)
    }

    private func write(_ pairing: StoredPairing, in database: GRDB.Database) throws -> PairingWrite {
        guard let profile = try String.fetchOne(
            database, sql: PairingRow.selectProfile, arguments: [pairing.account.data]
        ) else {
            return .unknownAccount
        }
        guard let console = try Row.fetchOne(
            database, sql: PairingRow.selectConsole, arguments: [pairing.console.hex]
        ) else {
            return .unknownConsole
        }
        let consoleID = try console.decode(String.self, forColumn: "id")
        let id = try String.fetchOne(database, sql: PairingRow.selectID, arguments: [profile, consoleID])
            ?? UUID().uuidString
        let allowKeyCreation = try Row.fetchOne(database, sql: PairingRow.anyCredential) == nil
        let envelope = try self.database.cipher.seal(
            PairingRow.keys(of: pairing.credentials),
            context: PairingRow.context(id: id, profileID: profile, consoleID: consoleID),
            allowKeyCreation: allowKeyCreation
        )
        try database.execute(
            sql: PairingRow.upsert,
            arguments: [
                id, profile, consoleID, envelope, Int64(pairing.credentials.keyType),
                pairing.deviceUID.map { Data($0.bytes) }
            ]
        )
        return .saved
    }

    private func pairing(_ row: PairingRow) -> StoredPairing? {
        guard let account = AccountID(bytes: row.accountID),
              let console = HardwareID(hex: row.hardwareID) else {
            report(.corruptData)
            return nil
        }
        let secret: SecretBytes
        do {
            secret = try database.cipher.open(row.envelope, context: row.context)
        } catch {
            report(error)
            return nil
        }
        guard let keyType = UInt32(exactly: row.keyType),
              let credentials = PairingRow.credentials(from: secret, keyType: keyType)
        else {
            report(.corruptData)
            return nil
        }
        let device = row.remoteDeviceID.flatMap {
            ConsoleDeviceUID(bytes: $0)
        }
        return StoredPairing(account: account, console: console, credentials: credentials, deviceUID: device)
    }

    private func reporting<Result>(_ body: () throws(PersistenceError) -> Result) throws(ConsoleStoreFailure)
        -> Result {
        do {
            return try body()
        } catch {
            report(error)
            throw .unavailable
        }
    }
}
