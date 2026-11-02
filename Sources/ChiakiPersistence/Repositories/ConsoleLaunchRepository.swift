import ChiakiModels
import Foundation
import GRDB

/// What each saved console does at launch, and the sealed login PIN an account keeps for it, in the
/// `consoles` table.
///
/// At most one console connects at launch. A login PIN belongs to one paired account and goes when that
/// account or its pairing does.
public final class ConsoleLaunchRepository: Sendable {
    /// Reads whether a console connects at launch and whether it has a saved login PIN.
    static let selectOptions = """
    SELECT connect_at_launch, encrypted_login_pin IS NOT NULL AS pin_saved FROM consoles WHERE id = ?
    """

    /// Finds the console set to connect at launch, provided it is still paired with some account.
    static let selectLaunchConsole = """
    SELECT c.id FROM consoles c
    WHERE c.connect_at_launch = 1 AND EXISTS (SELECT 1 FROM registrations r WHERE r.console_id = c.id)
    LIMIT 1
    """

    /// Clears connect-at-launch on every console except the given one, so at most one connects at launch.
    static let clearOtherLaunch = "UPDATE consoles SET connect_at_launch = 0 WHERE connect_at_launch = 1 AND id <> ?"

    /// Sets whether a console connects at launch.
    static let setLaunch = "UPDATE consoles SET connect_at_launch = ? WHERE id = ?"

    /// Removes a console's saved login PIN, whichever account it belongs to.
    static let forgetPIN = "UPDATE consoles SET encrypted_login_pin = NULL, login_pin_profile_id = NULL WHERE id = ?"

    /// Saves a sealed login PIN for an account, only when that account is paired with the console.
    static let savePIN = """
    UPDATE consoles SET encrypted_login_pin = ?, login_pin_profile_id = ?
    WHERE id = ? AND EXISTS (SELECT 1 FROM registrations WHERE console_id = consoles.id AND profile_id = ?)
    """

    /// Reads a console's sealed login PIN when it belongs to the given account.
    static let selectPIN = "SELECT encrypted_login_pin FROM consoles WHERE id = ? AND login_pin_profile_id = ?"

    /// Removes a console's saved login PIN only when it belongs to the given account.
    static let clearPIN = """
    UPDATE consoles SET encrypted_login_pin = NULL, login_pin_profile_id = NULL
    WHERE id = ? AND login_pin_profile_id = ?
    """

    private let database: AppDatabase

    /// Creates the repository over the app database.
    ///
    /// - Parameter database: The open database.
    public init(database: AppDatabase) {
        self.database = database
    }

    /// The launch options of a console.
    ///
    /// - Parameter console: The console's row id.
    /// - Returns: The options.
    /// - Throws: ``PersistenceError/invalidInput`` when no such console is saved.
    public func options(of console: UUID) throws(PersistenceError) -> ConsoleLaunchOptions {
        let row = try database.read { database in
            try Row.fetchOne(database, sql: Self.selectOptions, arguments: [console.uuidString])
        }
        guard let row else {
            throw .invalidInput
        }
        return try AppDatabase.mapping {
            try ConsoleLaunchOptions(
                connectAtLaunch: row.decode(Int64.self, forColumn: "connect_at_launch") == 1,
                loginPINSaved: row.decode(Int64.self, forColumn: "pin_saved") == 1
            )
        }
    }

    /// Edits a console's name, address and launch options in one transaction.
    ///
    /// - Parameters:
    ///   - console: The console's row id.
    ///   - name: The new name.
    ///   - address: The new address.
    ///   - connectAtLaunch: Whether to connect at launch; any other console stops doing so.
    ///   - forgetLoginPIN: Whether to forget the saved login PIN.
    /// - Throws: ``PersistenceError/invalidInput`` for an invalid name or address or an unknown console.
    public func update(
        _ console: UUID,
        name: String,
        address: String,
        connectAtLaunch: Bool,
        forgetLoginPIN: Bool
    ) throws(PersistenceError) {
        let edit = try ConsoleRepository.validatedEdit(name: name, address: address)
        try database.write { database in
            try database.execute(
                sql: ConsoleRow.rename, arguments: [edit.name, edit.address, console.uuidString]
            )
            guard database.changesCount == 1 else {
                throw PersistenceError.invalidInput
            }
            if connectAtLaunch {
                try database.execute(sql: Self.clearOtherLaunch, arguments: [console.uuidString])
            }
            try database.execute(
                sql: Self.setLaunch,
                arguments: [
                    connectAtLaunch
                        ? Int64(1)
                        : Int64(0),
                    console.uuidString
                ]
            )
            if forgetLoginPIN {
                try database.execute(sql: Self.forgetPIN, arguments: [console.uuidString])
            }
        }
    }

    /// The paired console to connect to at launch, if any.
    ///
    /// - Returns: The console's row id.
    /// - Throws: ``PersistenceError/corruptData`` for a malformed id, or a database error.
    public func launchConsole() throws(PersistenceError) -> UUID? {
        let id = try database.read { database in
            try String.fetchOne(database, sql: Self.selectLaunchConsole)
        }
        guard let id else {
            return nil
        }
        guard let uuid = UUID(uuidString: id) else {
            throw .corruptData
        }
        return uuid
    }

    /// Seals a login PIN for an account's pairing with a console.
    ///
    /// - Parameters:
    ///   - pin: Exactly four ASCII digits.
    ///   - console: The console's row id.
    ///   - profile: The paired profile's id.
    /// - Throws: ``PersistenceError/invalidInput`` for a malformed PIN or when the account is not paired with
    ///   the console.
    public func saveLoginPIN(_ pin: borrowing SecretBytes, console: UUID,
                             profile: UUID) throws(PersistenceError) {
        guard Self.isValidPIN(pin) else {
            throw .invalidInput
        }
        let allowKeyCreation = try database.read { database in
            try Row.fetchOne(database, sql: PairingRow.anyCredential) == nil
        }
        let envelope = try database.cipher.seal(
            pin, context: Self.pinContext(console: console, profile: profile),
            allowKeyCreation: allowKeyCreation
        )
        try database.write { database in
            try database.execute(
                sql: Self.savePIN,
                arguments: [envelope, profile.uuidString, console.uuidString, profile.uuidString]
            )
            guard database.changesCount == 1 else {
                throw PersistenceError.invalidInput
            }
        }
    }

    /// Opens the login PIN an account keeps for a console.
    ///
    /// - Parameters:
    ///   - console: The console's row id.
    ///   - profile: The profile's id.
    /// - Returns: The PIN, or `nil` when none is saved for that account.
    /// - Throws: ``PersistenceError/corruptData`` when the stored PIN is malformed, or the cipher's errors.
    public func loginPIN(console: UUID, profile: UUID) throws(PersistenceError) -> SecretBytes? {
        let envelope = try database.read { database in
            try Data?.fetchOne(
                database, sql: Self.selectPIN, arguments: [console.uuidString, profile.uuidString]
            ) ?? nil
        }
        guard let envelope else {
            return nil
        }
        let pin = try database.cipher.open(
            envelope,
            context: Self.pinContext(console: console, profile: profile)
        )
        guard Self.isValidPIN(pin) else {
            throw .corruptData
        }
        return pin
    }

    /// Forgets the login PIN an account keeps for a console.
    ///
    /// - Parameters:
    ///   - console: The console's row id.
    ///   - profile: The profile's id.
    /// - Throws: A database error.
    public func clearLoginPIN(console: UUID, profile: UUID) throws(PersistenceError) {
        try database.write { database in
            try database.execute(sql: Self.clearPIN, arguments: [console.uuidString, profile.uuidString])
        }
    }

    private static func pinContext(console: UUID, profile: UUID) -> String {
        "console-login-pin:\(console.uuidString):\(profile.uuidString):v1"
    }

    private static func isValidPIN(_ pin: borrowing SecretBytes) -> Bool {
        pin.withUnsafeBytes { bytes in
            bytes.count == 4 && bytes.allSatisfy {
                (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0)
            }
        }
    }
}
