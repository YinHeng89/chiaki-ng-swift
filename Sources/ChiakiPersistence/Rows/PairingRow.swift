import ChiakiModels
import Foundation
import GRDB

/// One row of the `registrations` table joined with its profile's account id and its console's hardware
/// id, decoded by column name.
struct PairingRow: FetchableRecord, Sendable {
    /// Lists every pairing with its account, console and address, in the order the pairings were made.
    static let selectRegistered = """
    SELECT r.profile_id, COALESCE(c.last_address, c.name) AS address, c.generation, r.remote_device_id,
           c.id AS console_id, c.name, c.hardware_id
    FROM registrations r JOIN consoles c ON c.id = r.console_id
    ORDER BY r.rowid
    """

    /// Reads what is needed to stream from an account's paired console, matched by PSN device id or, without
    /// one, by address.
    static let selectPlayTarget = """
    SELECT p.psn_account_id, c.hardware_id, c.name, c.last_address, c.generation, r.remote_device_id
    FROM registrations r
    JOIN consoles c ON c.id = r.console_id
    JOIN profiles p ON p.id = r.profile_id
    WHERE r.profile_id = ? AND ((?2 IS NULL AND c.last_address = ?3) OR r.remote_device_id = ?2)
    """

    /// Selects every pairing whose console has a hardware id.
    static let selectSaved = """
    SELECT r.id, r.profile_id, r.console_id, r.encrypted_credentials, r.key_type, r.remote_device_id,
           p.psn_account_id, c.hardware_id
    FROM registrations r
    JOIN profiles p ON p.id = r.profile_id
    JOIN consoles c ON c.id = r.console_id
    WHERE c.hardware_id IS NOT NULL
    ORDER BY r.rowid
    """

    /// Selects the profile that holds an account id, oldest first.
    static let selectProfile = """
    SELECT id FROM profiles WHERE psn_account_id = ? ORDER BY created_at, id LIMIT 1
    """

    /// Selects the console a pairing is with, by hardware id.
    static let selectConsole = "SELECT id FROM consoles WHERE hardware_id = ?"

    /// Selects the id of an existing pairing between a profile and a console.
    static let selectID = "SELECT id FROM registrations WHERE profile_id = ? AND console_id = ?"

    /// Inserts a pairing or replaces the credentials of the existing one.
    static let upsert = """
    INSERT INTO registrations(id, profile_id, console_id, encrypted_credentials, key_version, key_type,
        remote_device_id)
    VALUES (?, ?, ?, ?, 1, ?, ?)
    ON CONFLICT(profile_id, console_id) DO UPDATE SET
        encrypted_credentials = excluded.encrypted_credentials,
        key_version = 1,
        key_type = excluded.key_type,
        remote_device_id = excluded.remote_device_id
    """

    /// Deletes every pairing between an account's profiles and a console.
    static let delete = """
    DELETE FROM registrations
    WHERE profile_id IN (SELECT id FROM profiles WHERE psn_account_id = ?)
      AND console_id IN (SELECT id FROM consoles WHERE hardware_id = ?)
    """

    /// Selects one row when any credential is stored, deciding whether a new key may be created.
    static let anyCredential = """
    SELECT 1 FROM profile_tokens UNION ALL SELECT 1 FROM registrations
    UNION ALL SELECT 1 FROM profile_npsso UNION ALL SELECT 1 FROM kakusan_identity LIMIT 1
    """

    /// The `registrations.id` column.
    let id: String

    /// The `registrations.profile_id` column.
    let profileID: String

    /// The `registrations.console_id` column.
    let consoleID: String

    /// The `registrations.encrypted_credentials` envelope: both keys as raw bytes.
    let envelope: Data

    /// The `registrations.key_type` column.
    let keyType: Int64

    /// The `registrations.remote_device_id` column.
    let remoteDeviceID: Data?

    /// The `profiles.psn_account_id` column.
    let accountID: Data

    /// The `consoles.hardware_id` column.
    let hardwareID: String

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected by ``selectSaved``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        id = try row.decode(String.self, forColumn: "id")
        profileID = try row.decode(String.self, forColumn: "profile_id")
        consoleID = try row.decode(String.self, forColumn: "console_id")
        envelope = try row.decode(Data.self, forColumn: "encrypted_credentials")
        keyType = try row.decode(Int64.self, forColumn: "key_type")
        remoteDeviceID = try row.decode(Data?.self, forColumn: "remote_device_id")
        accountID = try row.decode(Data.self, forColumn: "psn_account_id")
        hardwareID = try row.decode(String.self, forColumn: "hardware_id")
    }

    /// The context string a pairing envelope is bound to.
    ///
    /// - Parameters:
    ///   - id: The pairing's row id.
    ///   - profileID: The profile's row id.
    ///   - consoleID: The console's row id.
    /// - Returns: The authenticated context.
    static func context(id: String, profileID: String, consoleID: String) -> String {
        "connection:\(id):\(profileID):\(consoleID):v2"
    }

    /// Both pairing keys as one sealed plaintext: the registration key followed by the Remote Play key.
    ///
    /// - Parameter credentials: The pairing's credentials.
    /// - Returns: The keys, in a wiping buffer.
    static func keys(of credentials: borrowing PairingCredentials) -> SecretBytes {
        let length = PairingCredentials.keyLength
        return SecretBytes(count: length * 2) { buffer in
            credentials.registrationKey.withUnsafeBytes {
                UnsafeMutableRawBufferPointer(rebasing: buffer[0 ..< length]).copyMemory(from: $0)
            }
            credentials.remotePlayKey.withUnsafeBytes {
                UnsafeMutableRawBufferPointer(rebasing: buffer[length ..< length * 2]).copyMemory(from: $0)
            }
        }
    }

    /// Splits a sealed plaintext made by ``keys(of:)`` back into credentials.
    ///
    /// - Parameters:
    ///   - keys: The opened plaintext.
    ///   - keyType: The stored key type.
    /// - Returns: The credentials, or `nil` when the plaintext has the wrong length.
    static func credentials(from keys: borrowing SecretBytes, keyType: UInt32) -> PairingCredentials? {
        let length = PairingCredentials.keyLength
        guard keys.count == length * 2 else {
            return nil
        }
        return keys.withUnsafeBytes { bytes in
            credentials(
                registrationKey: SecretBytes(count: length) {
                    $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[0 ..< length]))
                },
                remotePlayKey: SecretBytes(count: length) {
                    $0.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[length ..< length * 2]))
                },
                keyType: keyType
            )
        }
    }

    /// Builds credentials from two keys that may be missing.
    ///
    /// - Parameters:
    ///   - registrationKey: The registration key, if read.
    ///   - remotePlayKey: The Remote Play key, if read.
    ///   - keyType: The key type.
    /// - Returns: The credentials, or `nil` when a key is missing or has the wrong length.
    static func credentials(
        registrationKey: consuming SecretBytes?,
        remotePlayKey: consuming SecretBytes?,
        keyType: UInt32
    ) -> PairingCredentials? {
        switch consume registrationKey {
        case .some(let registration):
            switch consume remotePlayKey {
            case .some(let remotePlay):
                return PairingCredentials(
                    registrationKey: registration,
                    remotePlayKey: remotePlay,
                    keyType: keyType
                )
            case .none:
                return nil
            }
        case .none:
            return nil
        }
    }

    /// The context string this row's envelope is bound to.
    var context: String {
        Self.context(id: id, profileID: profileID, consoleID: consoleID)
    }
}
