import ChiakiModels
import GRDB

/// One row of the `consoles` table, decoded by column name.
struct ConsoleRow: FetchableRecord, Sendable {
    /// Selects every console that has a hardware id, in insertion order.
    static let selectSaved = """
    SELECT id, hardware_id, name, generation, firmware, name_source, last_address
    FROM consoles WHERE hardware_id IS NOT NULL ORDER BY rowid
    """

    /// Selects the id of the console with a hardware id.
    static let selectID = "SELECT id FROM consoles WHERE hardware_id = ?"

    /// Inserts a console or updates the one with the same hardware id, keeping a known address when the new
    /// facts have none.
    static let upsert = """
    INSERT INTO consoles(id, hardware_id, name, generation, firmware, name_source, last_address)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(hardware_id) DO UPDATE SET
        name = excluded.name,
        generation = excluded.generation,
        firmware = excluded.firmware,
        name_source = excluded.name_source,
        last_address = COALESCE(excluded.last_address, consoles.last_address)
    """

    /// Deletes the console with a hardware id; its pairings cascade.
    static let delete = "DELETE FROM consoles WHERE hardware_id = ?"

    /// Updates a console's name and last known address.
    static let rename = "UPDATE consoles SET name = ?, last_address = ? WHERE id = ?"

    /// Deletes a console, cascading to its pairings.
    static let deleteByID = "DELETE FROM consoles WHERE id = ?"

    /// Reads a console's hardware id.
    static let selectHardwareByID = "SELECT hardware_id FROM consoles WHERE id = ?"

    /// Reads the last known address of the console with a hardware id.
    static let selectAddress = "SELECT last_address FROM consoles WHERE hardware_id = ?"

    /// Records a console's new address, writing only when it differs from the stored one.
    static let updateAddress = """
    UPDATE consoles SET last_address = ? WHERE hardware_id = ? AND (last_address IS NULL OR last_address <> ?)
    """

    /// The `id` column.
    let id: String

    /// The `hardware_id` column: twelve lowercase hex digits, or `NULL` for a console never reached.
    let hardwareID: String?

    /// The `name` column.
    let name: String

    /// The `generation` column: `ps4` or `ps5`.
    let generation: String

    /// The `firmware` column, `NULL` only for rows written without it.
    let firmware: String?

    /// The `name_source` column.
    let nameSource: String

    /// The `last_address` column.
    let lastAddress: String?

    /// Decodes a row by column name.
    ///
    /// - Parameter row: A row selected with at least the columns of ``selectSaved``.
    /// - Throws: GRDB's decoding error when a column is missing or has the wrong type.
    init(row: Row) throws {
        id = try row.decode(String.self, forColumn: "id")
        hardwareID = try row.decode(String?.self, forColumn: "hardware_id")
        name = try row.decode(String.self, forColumn: "name")
        generation = try row.decode(String.self, forColumn: "generation")
        firmware = try row.decode(String?.self, forColumn: "firmware")
        nameSource = try row.decode(String.self, forColumn: "name_source")
        lastAddress = try row.decode(String?.self, forColumn: "last_address")
    }

    /// The row as console facts, or `nil` when a column breaks its schema.
    ///
    /// A row written without firmware is read as the newest family of its generation, which is what the app
    /// assumed before migration 012.
    var stored: StoredConsole? {
        guard let hardwareID = hardwareID.flatMap({ HardwareID(hex: $0) }),
              let kind = ConsoleKind(rawValue: generation),
              let source = ConsoleNameSource(rawValue: nameSource)
        else {
            return nil
        }
        let family = firmware.map(ConsoleFirmware.init(rawValue:)) ?? ConsoleFirmware.assumed(for: kind)
        guard let family, family.kind == kind else {
            return nil
        }
        return StoredConsole(
            hardwareID: hardwareID,
            firmware: family,
            name: name,
            nameSource: source,
            address: lastAddress
        )
    }

    /// The arguments of ``upsert`` for a console's facts.
    ///
    /// - Parameters:
    ///   - console: The facts to write.
    ///   - id: The row id to insert under when the console is new.
    /// - Returns: The statement arguments.
    static func upsertArguments(_ console: StoredConsole, id: String) -> StatementArguments {
        [
            id, console.hardwareID.hex, console.name, console.kind.rawValue, console.firmware.rawValue,
            console.nameSource.rawValue, console.address
        ]
    }
}
