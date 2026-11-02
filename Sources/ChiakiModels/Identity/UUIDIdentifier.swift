import Foundation

/// An identifier backed by a `UUID`, stored as its uppercase `uuidString` text.
///
/// ``ProfileID`` and ``ConsoleID`` conform so that each row kind has its own type while
/// sharing one text form and one `Codable` form. A conforming type encodes as a bare `UUID`, so its JSON
/// matches the plain `UUID` values persisted before the strong types existed.
public protocol UUIDIdentifier: Hashable, Sendable, Codable {
    /// The underlying `UUID`.
    var uuid: UUID { get }

    /// Wraps an existing `UUID`.
    ///
    /// - Parameter uuid: The `UUID` to wrap.
    init(uuid: UUID)
}

public extension UUIDIdentifier {
    /// Creates a new random identifier.
    init() {
        self.init(uuid: UUID())
    }

    /// Reads an identifier from its text form.
    ///
    /// - Parameter uuidString: A `UUID` string in either case, such as `"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"`.
    /// - Returns: `nil` when the text is not a `UUID`.
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuid: uuid)
    }

    /// The uppercase text form stored in the database's `id` columns.
    var uuidString: String {
        uuid.uuidString
    }

    /// Decodes an identifier from a bare `UUID` value.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the value is not a `UUID`.
    init(from decoder: any Decoder) throws {
        try self.init(uuid: decoder.singleValueContainer().decode(UUID.self))
    }

    /// Encodes the identifier as a bare `UUID` value.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: `EncodingError` when the encoder refuses the value.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }
}

/// The identifier of one asynchronous operation, such as one pairing attempt.
///
/// A workflow records the id of the operation it started and accepts a completion only when the completion
/// carries the same id, so a cancelled or superseded operation cannot move the workflow.
public struct OperationID: UUIDIdentifier {
    /// The underlying `UUID`.
    public let uuid: UUID

    /// Wraps an existing `UUID`.
    ///
    /// - Parameter uuid: The `UUID` to wrap.
    public init(uuid: UUID) {
        self.uuid = uuid
    }
}

/// The identifier of an app profile, the `profiles.id` column.
///
/// It names the profile row, not the PSN account behind it; see ``AccountID`` for that.
public struct ProfileID: UUIDIdentifier {
    /// The underlying `UUID`.
    public let uuid: UUID

    /// Wraps an existing `UUID`.
    ///
    /// - Parameter uuid: The `UUID` to wrap.
    public init(uuid: UUID) {
        self.uuid = uuid
    }
}

/// The identifier of a saved console, the `consoles.id` column.
///
/// It names the stored row, not the hardware; see ``HardwareID`` for that.
public struct ConsoleID: UUIDIdentifier {
    /// The underlying `UUID`.
    public let uuid: UUID

    /// Wraps an existing `UUID`.
    ///
    /// - Parameter uuid: The `UUID` to wrap.
    public init(uuid: UUID) {
        self.uuid = uuid
    }
}
