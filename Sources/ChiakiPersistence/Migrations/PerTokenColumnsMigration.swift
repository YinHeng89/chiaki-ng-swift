import ChiakiModels
import Foundation
import GRDB

/// Migration 018: one encrypted column per token, and pairing keys sealed as raw bytes.
///
/// Older versions sealed both tokens of a kind into one JSON envelope and both pairing keys into a JSON
/// document with base64 keys. This step opens each envelope with the Keychain key, reads the fields straight
/// into wiping buffers with `LegacySecretDocument` and seals every token, and each pairing's two keys, in
/// envelopes of their own bound to new contexts. The pairing's key type and PSN device id move into columns.
///
/// A row whose envelope does not open or decode is dropped, as the app already ignored such rows when it
/// loaded them; the user signs in or pairs again. A Keychain that refuses the key fails the step, so a locked
/// Keychain never costs data.
enum PerTokenColumnsMigration {
    private struct MigratedPairing {
        let sealedKeys: Data
        let keyType: Int64
        let device: Data?
    }
    /// Creates the replacement token table, with one sealed column for the access token and one for the
    /// refresh token.
    static let tokensTable = """
    CREATE TABLE profile_tokens_018 (
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        credential_kind TEXT NOT NULL CHECK (credential_kind IN ('remote_play', 'mobile_sso')),
        encrypted_access BLOB CHECK (encrypted_access IS NULL OR length(encrypted_access) > 1),
        encrypted_refresh BLOB CHECK (encrypted_refresh IS NULL OR length(encrypted_refresh) > 1),
        key_version INTEGER NOT NULL CHECK (key_version > 0),
        access_expires_at INTEGER CHECK (access_expires_at IS NULL OR typeof(access_expires_at) = 'integer'),
        access_obtained_at INTEGER CHECK (access_obtained_at IS NULL OR typeof(access_obtained_at) = 'integer'),
        refresh_obtained_at INTEGER CHECK (refresh_obtained_at IS NULL OR typeof(refresh_obtained_at) = 'integer'),
        refresh_expires_at INTEGER CHECK (refresh_expires_at IS NULL OR typeof(refresh_expires_at) = 'integer'),
        updated_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
            CHECK (typeof(updated_at) = 'integer'),
        CHECK (encrypted_access IS NOT NULL OR encrypted_refresh IS NOT NULL),
        CHECK ((encrypted_access IS NULL) = (access_expires_at IS NULL)),
        CHECK (encrypted_access IS NOT NULL OR access_obtained_at IS NULL),
        CHECK (encrypted_refresh IS NOT NULL OR (refresh_obtained_at IS NULL AND refresh_expires_at IS NULL)),
        PRIMARY KEY (profile_id, credential_kind)
    )
    """

    /// Creates the replacement pairing table, with the key type and PSN device id in columns of their own.
    static let registrationsTable = """
    CREATE TABLE registrations_018 (
        id TEXT NOT NULL PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
        console_id TEXT NOT NULL REFERENCES consoles(id) ON DELETE CASCADE,
        encrypted_credentials BLOB NOT NULL CHECK (length(encrypted_credentials) > 1),
        key_version INTEGER NOT NULL CHECK (key_version > 0),
        key_type INTEGER NOT NULL CHECK (typeof(key_type) = 'integer' AND key_type BETWEEN 0 AND 4294967295),
        created_at INTEGER NOT NULL DEFAULT (CAST(round((julianday('now') - 2440587.5) * 86400000) AS INTEGER))
            CHECK (typeof(created_at) = 'integer'),
        remote_device_id BLOB
            CHECK (remote_device_id IS NULL OR (typeof(remote_device_id) = 'blob' AND length(remote_device_id) = 32)),
        UNIQUE (profile_id, console_id)
    )
    """

    /// Swaps the new token and pairing tables in for the old ones and recreates the pairing index and launch
    /// trigger.
    static let replaceTables = """
    DROP TABLE profile_tokens;
    ALTER TABLE profile_tokens_018 RENAME TO profile_tokens;
    DROP TABLE registrations;
    ALTER TABLE registrations_018 RENAME TO registrations;
    CREATE INDEX registrations_by_console ON registrations(console_id);
    CREATE TRIGGER registrations_release_console_launch AFTER DELETE ON registrations
    BEGIN
        UPDATE consoles SET encrypted_login_pin = NULL, login_pin_profile_id = NULL
        WHERE id = old.console_id AND login_pin_profile_id = old.profile_id;
        UPDATE consoles SET connect_at_launch = 0
        WHERE id = old.console_id AND NOT EXISTS (SELECT 1 FROM registrations WHERE console_id = old.console_id);
    END
    """

    /// Reads every token row in the old single-envelope layout.
    static let legacyTokens = """
    SELECT profile_id, credential_kind, encrypted_tokens, key_version, expires_at, updated_at,
           access_obtained_at_ms, refresh_obtained_at_ms, refresh_expires_at_ms
    FROM profile_tokens
    """

    /// Inserts one migrated token row into the replacement token table.
    static let insertTokens = """
    INSERT INTO profile_tokens_018(profile_id, credential_kind, encrypted_access, encrypted_refresh, key_version,
        access_expires_at, access_obtained_at, refresh_obtained_at, refresh_expires_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    /// Reads every pairing row in the old JSON-document layout.
    static let legacyPairings = """
    SELECT id, profile_id, console_id, encrypted_credentials, key_version, created_at, remote_device_id
    FROM registrations
    """

    /// Inserts one migrated pairing row into the replacement pairing table.
    static let insertPairing = """
    INSERT INTO registrations_018(id, profile_id, console_id, encrypted_credentials, key_version, key_type,
        created_at, remote_device_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """

    /// Runs the step inside the migration transaction.
    ///
    /// - Parameters:
    ///   - database: The database at version 16.
    ///   - cipher: The cipher holding the Keychain key.
    /// - Throws: The SQLite error of a failing statement, or ``PersistenceError/keyUnavailable(status:)`` when
    ///   the Keychain refuses the key.
    static func run(_ database: GRDB.Database, cipher: CredentialCipher) throws {
        try database.execute(sql: tokensTable)
        try database.execute(sql: registrationsTable)
        for row in try Row.fetchAll(database, sql: legacyTokens) {
            try migrateTokens(row, in: database, cipher: cipher)
        }
        for row in try Row.fetchAll(database, sql: legacyPairings) {
            try migratePairing(row, in: database, cipher: cipher)
        }
        try database.execute(sql: replaceTables)
    }

    private static func migrateTokens(
        _ row: Row,
        in database: GRDB.Database,
        cipher: CredentialCipher
    ) throws {
        let profileID: String = try row.decode(String.self, forColumn: "profile_id")
        let kind: String = try row.decode(String.self, forColumn: "credential_kind")
        let envelope: Data = try row.decode(Data.self, forColumn: "encrypted_tokens")
        guard let document = try opened(envelope, context: "account:\(profileID):\(kind):v1", cipher: cipher)
        else {
            return
        }
        let sealed = try document.withUnsafeBytes { (bytes) throws -> (Data?, Data?)? in
            guard let reader = LegacySecretDocument(bytes) else {
                return nil
            }
            return try (
                seal(
                    reader.text("access"),
                    context: TokenRow.context(profileID: profileID, kind: kind, part: .access),
                    cipher: cipher
                ),
                seal(
                    reader.text("refresh"),
                    context: TokenRow.context(profileID: profileID, kind: kind, part: .refresh),
                    cipher: cipher
                )
            )
        }
        guard let sealed, sealed.0 != nil || sealed.1 != nil else {
            return
        }
        let hasAccess = sealed.0 != nil
        let hasRefresh = sealed.1 != nil
        try database.execute(
            sql: insertTokens,
            arguments: [
                profileID, kind, sealed.0, sealed.1, row.decode(Int64.self, forColumn: "key_version"),
                hasAccess
                    ? row.decode(Int64.self, forColumn: "expires_at")
                    : nil,
                hasAccess
                    ? row.decode(Int64?.self, forColumn: "access_obtained_at_ms")
                    : nil,
                hasRefresh
                    ? row.decode(Int64?.self, forColumn: "refresh_obtained_at_ms")
                    : nil,
                hasRefresh
                    ? row.decode(Int64?.self, forColumn: "refresh_expires_at_ms")
                    : nil,
                row.decode(Int64.self, forColumn: "updated_at")
            ]
        )
    }

    private static func migratePairing(
        _ row: Row,
        in database: GRDB.Database,
        cipher: CredentialCipher
    ) throws {
        let id: String = try row.decode(String.self, forColumn: "id")
        let profileID: String = try row.decode(String.self, forColumn: "profile_id")
        let consoleID: String = try row.decode(String.self, forColumn: "console_id")
        let envelope: Data = try row.decode(Data.self, forColumn: "encrypted_credentials")
        let legacyContext = "connection:\(id):\(profileID):\(consoleID):v1"
        guard let document = try opened(envelope, context: legacyContext, cipher: cipher) else {
            return
        }
        let migrated = try document.withUnsafeBytes { (bytes) throws -> MigratedPairing? in
            guard let reader = LegacySecretDocument(bytes), let keyType = reader.integer("keyType"),
                  let credentials = PairingRow.credentials(
                      registrationKey: reader.base64("registrationKey"),
                      remotePlayKey: reader.base64("remotePlayKey"),
                      keyType: UInt32(clamping: keyType)
                  )
            else {
                return nil
            }
            let device = reader.base64("remoteDeviceID")?.withUnsafeBytes {
                $0.count == ConsoleDeviceUID.byteCount
                    ? Data($0)
                    : nil
            }
            let keys = PairingRow.keys(of: credentials)
            let sealed = try cipher.seal(
                keys,
                context: PairingRow.context(id: id, profileID: profileID, consoleID: consoleID),
                allowKeyCreation: false
            )
            return MigratedPairing(sealedKeys: sealed, keyType: Int64(credentials.keyType), device: device)
        }
        guard let migrated else {
            return
        }
        try database.execute(
            sql: insertPairing,
            arguments: [
                id, profileID, consoleID, migrated.sealedKeys, row.decode(
                    Int64.self,
                    forColumn: "key_version"
                ),
                migrated.keyType,
                row.decode(Int64.self, forColumn: "created_at"),
                row.decode(Data?.self, forColumn: "remote_device_id") ?? migrated.device
            ]
        )
    }

    private static func opened(_ envelope: Data, context: String,
                               cipher: CredentialCipher) throws -> SecretBytes? {
        do {
            return try cipher.open(envelope, context: context)
        } catch .keyUnavailable(let status) {
            throw PersistenceError.keyUnavailable(status: status)
        } catch {
            return nil
        }
    }

    private static func seal(
        _ secret: consuming SecretBytes?,
        context: String,
        cipher: CredentialCipher
    ) throws
        -> Data? {
        switch consume secret {
        case .some(let value):
            guard !value.isEmpty else {
                return nil
            }
            return try cipher.seal(value, context: context, allowKeyCreation: false)
        case .none:
            return nil
        }
    }
}

/// Reads fields of the flat JSON objects that older versions sealed into credential envelopes.
///
/// Tokens were sealed as `{"access":…,"refresh":…}` and pairings as a document with base64 keys. The reader
/// walks the decrypted bytes in place and copies a string field's decoded bytes straight into
/// `ChiakiModels/SecretBytes`, so no secret becomes a `String` on the way. Only the object shapes those
/// versions wrote are understood: one object of string, number, Boolean and `null` values.
private struct LegacySecretDocument {
    private enum Value {
        case text(Range<Int>)
        case number(Range<Int>)
        case literal
    }

    private let fields: [String: Value]
    private let bytes: UnsafeRawBufferPointer

    /// Parses a decrypted document.
    ///
    /// - Parameter bytes: The document; it must outlive the reader.
    /// - Returns: `nil` when the bytes are not one flat JSON object.
    init?(_ bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
        var fields: [String: Value] = [:]
        var index = Self.skipSpace(bytes, from: 0)
        guard index < bytes.count, bytes[index] == UInt8(ascii: "{") else {
            return nil
        }
        index = Self.skipSpace(bytes, from: index + 1)
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            self.fields = fields
            return
        }
        while true {
            guard let key = Self.string(bytes, from: index),
                  let name = String(bytes: bytes[key.content], encoding: .utf8)
            else {
                return nil
            }
            index = Self.skipSpace(bytes, from: key.end)
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                return nil
            }
            index = Self.skipSpace(bytes, from: index + 1)
            guard let value = Self.value(bytes, from: index) else {
                return nil
            }
            fields[name] = value.value
            index = Self.skipSpace(bytes, from: value.end)
            guard index < bytes.count else {
                return nil
            }
            if bytes[index] == UInt8(ascii: "}") {
                break
            }
            guard bytes[index] == UInt8(ascii: ",") else {
                return nil
            }
            index = Self.skipSpace(bytes, from: index + 1)
        }
        self.fields = fields
    }

    /// Copies a string field's decoded bytes into a wiping buffer.
    ///
    /// - Parameter name: The field name.
    /// - Returns: The decoded bytes, or `nil` when the field is missing or not a string.
    func text(_ name: String) -> SecretBytes? {
        guard case .text(let range) = fields[name] else {
            return nil
        }
        var decoded = [UInt8]()
        decoded.reserveCapacity(range.count)
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "\\") else {
                decoded.append(byte)
                index += 1
                continue
            }
            guard index + 1 < range.upperBound else {
                decoded.withUnsafeMutableBytes {
                    SecretBytes.wipe($0)
                }
                return nil
            }
            switch bytes[index + 1] {
            case UInt8(ascii: "n"):
                decoded.append(0x0A)
            case UInt8(ascii: "t"):
                decoded.append(0x09)
            case UInt8(ascii: "r"):
                decoded.append(0x0D)
            case UInt8(ascii: "b"):
                decoded.append(0x08)
            case UInt8(ascii: "f"):
                decoded.append(0x0C)
            case UInt8(ascii: "u"):
                guard index + 5 < range.upperBound,
                      let unit = Hex.decode(utf8: Array(bytes[index + 2 ... index + 5])),
                      unit[0] == 0, unit[1] < 0x80
                else {
                    decoded.withUnsafeMutableBytes {
                        SecretBytes.wipe($0)
                    }
                    return nil
                }
                decoded.append(unit[1])
                index += 4
            default:
                decoded.append(bytes[index + 1])
            }
            index += 2
        }
        return SecretBytes(wiping: &decoded)
    }

    /// Copies a base64 string field's decoded bytes into a wiping buffer.
    ///
    /// - Parameter name: The field name.
    /// - Returns: The decoded bytes, or `nil` when the field is missing or not base64.
    func base64(_ name: String) -> SecretBytes? {
        guard let encoded = text(name) else {
            return nil
        }
        var source = encoded.withUnsafeBytes {
            Data($0)
        }
        defer {
            source.withUnsafeMutableBytes {
                SecretBytes.wipe($0)
            }
        }
        guard var decoded = Data(base64Encoded: source) else {
            return nil
        }
        return SecretBytes(wiping: &decoded)
    }

    /// Reads a whole-number field.
    ///
    /// - Parameter name: The field name.
    /// - Returns: The number, or `nil` when the field is missing or not a whole number.
    func integer(_ name: String) -> Int64? {
        guard case .number(let range) = fields[name] else {
            return nil
        }
        return String(bytes: bytes[range], encoding: .utf8).flatMap {
            Int64($0)
        }
    }

    private static func skipSpace(_ bytes: UnsafeRawBufferPointer, from start: Int) -> Int {
        var index = start
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
            index += 1
        }
        return index
    }

    private static func string(_ bytes: UnsafeRawBufferPointer,
                               from start: Int) -> (content: Range<Int>, end: Int)? {
        guard start < bytes.count, bytes[start] == UInt8(ascii: "\"") else {
            return nil
        }
        var index = start + 1
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\"):
                index += 2
            case UInt8(ascii: "\""):
                return (start + 1 ..< index, index + 1)
            default:
                index += 1
            }
        }
        return nil
    }

    private static func value(_ bytes: UnsafeRawBufferPointer, from start: Int) -> (value: Value, end: Int)? {
        guard start < bytes.count else {
            return nil
        }
        if let text = string(bytes, from: start) {
            return (.text(text.content), text.end)
        }
        for literal in ["null", "true", "false"] {
            let utf8 = Array(literal.utf8)
            if start + utf8.count <= bytes.count, Array(bytes[start ..< start + utf8.count]) == utf8 {
                return (.literal, start + utf8.count)
            }
        }
        var index = start
        while index < bytes.count,
              bytes[index] == UInt8(ascii: "-") || (UInt8(ascii: "0") ... UInt8(ascii: "9"))
              .contains(bytes[index]) {
            index += 1
        }
        guard index > start else {
            return nil
        }
        return (.number(start ..< index), index)
    }
}
