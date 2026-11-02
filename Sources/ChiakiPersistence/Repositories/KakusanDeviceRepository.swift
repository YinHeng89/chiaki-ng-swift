import ChiakiModels
import Foundation
import GRDB

/// This installation's Kakusan identity and the devices it remembers, in `kakusan_identity` and
/// `kakusan_peers`.
///
/// The identity seed is sealed with the database's ``CredentialCipher`` and only leaves it in a wiping buffer.
/// Rows written before the core derived keys and fingerprints hold zeros there; once the core is open, the app
/// hands the derived values to ``restoreDerivedColumns(identityKey:fingerprints:)``.
public final class KakusanDeviceRepository: DeviceStoring {
    private let database: AppDatabase
    private let report: @Sendable (PersistenceError) -> Void
    private let now: @Sendable () -> Date

    /// Creates the repository over the app database.
    ///
    /// - Parameters:
    ///   - database: The open database.
    ///   - report: Receives every storage failure before it is turned into a
    ///     `ChiakiModels/DeviceStoreFailure`. Ignored by default.
    ///   - now: The clock dating a new identity.
    public init(
        database: AppDatabase,
        report: @escaping @Sendable (PersistenceError) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = {
            Date()
        }
    ) {
        self.database = database
        self.report = report
        self.now = now
    }

    /// Loads the identity, opening its seed.
    ///
    /// - Returns: The identity with the stored key, or `nil` when none was created. Its fingerprint is the
    ///   placeholder; the core derives the real one from the seed.
    /// - Throws: `ChiakiModels/DeviceStoreFailure/unavailable` when the table cannot be read or the seed does
    ///   not open.
    public func identity() throws(DeviceStoreFailure) -> StoredDeviceIdentity? {
        let row = try reporting { () throws(PersistenceError) in
            try database.read { database in
                try DeviceIdentityRow.fetchOne(database, sql: DeviceIdentityRow.select)
            }
        }
        guard let row else {
            return nil
        }
        let seed: SecretBytes
        do {
            seed = try database.cipher.open(row.envelope, context: DeviceIdentityRow.seedContext)
        } catch {
            report(error)
            throw .unavailable
        }
        guard let key = DeviceIdentityKey(bytes: row.publicKey),
              let identity = StoredDeviceIdentity(seed: seed, key: key, fingerprint: .underived)
        else {
            report(.corruptData)
            throw .unavailable
        }
        return identity
    }

    /// Saves the identity, sealing its seed.
    ///
    /// A new encryption key is created only while no credential of any kind is stored.
    ///
    /// - Parameter identity: The identity.
    /// - Throws: `ChiakiModels/DeviceStoreFailure/unavailable` when the write failed.
    public func save(_ identity: StoredDeviceIdentity) throws(DeviceStoreFailure) {
        let stamp = Timestamp.milliseconds(of: now())
        try reporting { () throws(PersistenceError) in
            let allowKeyCreation = try database.read { database in
                try Row.fetchOne(database, sql: PairingRow.anyCredential) == nil
            }
            let envelope = try database.cipher.seal(
                identity.seed, context: DeviceIdentityRow.seedContext, allowKeyCreation: allowKeyCreation
            )
            try database.write { database in
                try database.execute(
                    sql: DeviceIdentityRow.upsert, arguments: [envelope, Data(identity.key.bytes), stamp]
                )
            }
        }
    }

    /// Loads every remembered device.
    ///
    /// - Returns: The devices in the order they were first saved.
    /// - Throws: `ChiakiModels/DeviceStoreFailure/unavailable` when the table cannot be read.
    public func rememberedDevices() throws(DeviceStoreFailure) -> [RememberedDevice] {
        try reporting { () throws(PersistenceError) in
            try database.read { database in
                try RememberedDeviceRow.fetchAll(database, sql: RememberedDeviceRow.selectAll)
            }
        }
        .compactMap(\.device)
    }

    /// Saves a device, keeping when an already remembered one was first verified.
    ///
    /// - Parameter device: The device.
    /// - Throws: `ChiakiModels/DeviceStoreFailure/unavailable` when the write failed.
    public func save(_ device: RememberedDevice) throws(DeviceStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(
                    sql: RememberedDeviceRow.upsert,
                    arguments: [
                        Data(device.key.bytes), Data(device.fingerprint.bytes), device.nickname,
                        Timestamp.milliseconds(of: device.firstVerified),
                        Timestamp.milliseconds(of: device.lastSeen)
                    ]
                )
            }
        }
    }

    /// Forgets a device.
    ///
    /// - Parameter key: The device's key.
    /// - Throws: `ChiakiModels/DeviceStoreFailure/unavailable` when the delete failed.
    public func forget(_ key: DeviceIdentityKey) throws(DeviceStoreFailure) {
        try reporting { () throws(PersistenceError) in
            try database.write { database in
                try database.execute(sql: RememberedDeviceRow.delete, arguments: [Data(key.bytes)])
            }
        }
    }

    /// Whether any stored key or fingerprint is still the placeholder the core has not derived yet.
    ///
    /// - Returns: `true` when ``restoreDerivedColumns(identityKey:fingerprints:)`` has work to do.
    /// - Throws: ``PersistenceError`` when the tables cannot be read.
    public func hasUnderivedColumns() throws(PersistenceError) -> Bool {
        let placeholder = Data(DeviceKeyFingerprint.underived.bytes)
        return try database.read { database in
            let identity = try DeviceIdentityRow.fetchOne(database, sql: DeviceIdentityRow.select)
            let peer = try Row.fetchOne(
                database,
                sql: RememberedDeviceRow.anyUnderived,
                arguments: [placeholder]
            )
            return identity?.publicKey == placeholder || peer != nil
        }
    }

    /// Replaces placeholder keys and fingerprints with the values the core derived.
    ///
    /// Only placeholders are replaced; a column holding a real value is never overwritten.
    ///
    /// - Parameters:
    ///   - identityKey: This installation's derived public key, if the core has one.
    ///   - fingerprints: The derived fingerprint of each remembered device, by key.
    /// - Throws: ``PersistenceError`` when the write failed.
    public func restoreDerivedColumns(
        identityKey: DeviceIdentityKey?,
        fingerprints: [DeviceIdentityKey: DeviceKeyFingerprint]
    ) throws(PersistenceError) {
        let placeholder = Data(DeviceKeyFingerprint.underived.bytes)
        try database.write { database in
            if let identityKey, Data(identityKey.bytes) != placeholder {
                try database.execute(
                    sql: DeviceIdentityRow.restoreKey, arguments: [Data(identityKey.bytes), placeholder]
                )
            }
            for (key, fingerprint) in fingerprints where !fingerprint.isUnderived {
                try database.execute(
                    sql: RememberedDeviceRow.restoreFingerprint,
                    arguments: [Data(fingerprint.bytes), Data(key.bytes), placeholder]
                )
            }
        }
    }

    private func reporting<Result>(_ body: () throws(PersistenceError) -> Result) throws(DeviceStoreFailure)
        -> Result {
        do {
            return try body()
        } catch {
            report(error)
            throw .unavailable
        }
    }
}

/// The one row of the `kakusan_identity` table: the sealed seed and the public key derived from it.
private struct DeviceIdentityRow: FetchableRecord, Sendable {
    /// The context the seed envelope is bound to.
    static let seedContext = "kakusan:identity:v1"

    /// Selects the identity.
    static let select = "SELECT encrypted_seed, public_key FROM kakusan_identity WHERE id = 1"

    /// Inserts the identity or replaces it.
    static let upsert = """
    INSERT INTO kakusan_identity(id, encrypted_seed, public_key, key_version, created_at) VALUES (1, ?, ?, 1, ?)
    ON CONFLICT(id) DO UPDATE SET encrypted_seed = excluded.encrypted_seed, public_key = excluded.public_key
    """

    /// Replaces the placeholder public key with the derived one.
    static let restoreKey = "UPDATE kakusan_identity SET public_key = ? WHERE id = 1 AND public_key = ?"

    /// The `encrypted_seed` envelope.
    let envelope: Data

    /// The `public_key` column.
    let publicKey: Data

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``select``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        envelope = try row.decode(Data.self, forColumn: "encrypted_seed")
        publicKey = try row.decode(Data.self, forColumn: "public_key")
    }
}

/// One row of the `kakusan_peers` table, decoded by column name.
private struct RememberedDeviceRow: FetchableRecord, Sendable {
    /// Selects every remembered device in the order it was first saved.
    static let selectAll = """
    SELECT public_key, fingerprint, nickname, first_verified_at, last_seen_at FROM kakusan_peers ORDER BY rowid
    """

    /// Inserts a device or updates the one with the same key, keeping when it was first verified.
    static let upsert = """
    INSERT INTO kakusan_peers(public_key, fingerprint, nickname, first_verified_at, last_seen_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(public_key) DO UPDATE SET
        nickname = excluded.nickname,
        last_seen_at = excluded.last_seen_at,
        fingerprint = excluded.fingerprint
    """

    /// Deletes the device with a key.
    static let delete = "DELETE FROM kakusan_peers WHERE public_key = ?"

    /// Selects one row when any device still has the placeholder fingerprint.
    static let anyUnderived = "SELECT 1 FROM kakusan_peers WHERE fingerprint = ? LIMIT 1"

    /// Replaces a device's placeholder fingerprint with the derived one.
    static let restoreFingerprint = """
    UPDATE kakusan_peers SET fingerprint = ? WHERE public_key = ? AND fingerprint = ?
    """

    /// The device the row holds, or `nil` when a column breaks its schema.
    let device: RememberedDevice?

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectAll``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        let key = try DeviceIdentityKey(bytes: row.decode(Data.self, forColumn: "public_key"))
        let fingerprint = try DeviceKeyFingerprint(bytes: row.decode(Data.self, forColumn: "fingerprint"))
        guard let key, let fingerprint else {
            device = nil
            return
        }
        device = try RememberedDevice(
            key: key,
            fingerprint: fingerprint,
            nickname: row.decode(String.self, forColumn: "nickname"),
            firstVerified: Timestamp.date(milliseconds: row.decode(
                Int64.self,
                forColumn: "first_verified_at"
            )),
            lastSeen: Timestamp.date(milliseconds: row.decode(Int64.self, forColumn: "last_seen_at"))
        )
    }
}
