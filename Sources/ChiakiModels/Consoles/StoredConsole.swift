/// The facts about a console that are persisted between runs.
public struct StoredConsole: Hashable, Sendable {
    /// The console's hardware id, the row's key.
    public let hardwareID: HardwareID

    /// The firmware family last learned.
    public let firmware: ConsoleFirmware

    /// The display name.
    public let name: String

    /// Who supplied ``name``.
    public let nameSource: ConsoleNameSource

    /// The address the console was last reached at, if any.
    public let address: String?

    /// Creates the facts for one console.
    ///
    /// - Parameters:
    ///   - hardwareID: The console's hardware id.
    ///   - firmware: The firmware family.
    ///   - name: The display name.
    ///   - nameSource: Who supplied the name.
    ///   - address: The last address, if any.
    public init(
        hardwareID: HardwareID,
        firmware: ConsoleFirmware,
        name: String,
        nameSource: ConsoleNameSource,
        address: String?
    ) {
        self.hardwareID = hardwareID
        self.firmware = firmware
        self.name = name
        self.nameSource = nameSource
        self.address = address
    }

    /// The console generation, derived from ``firmware``.
    public var kind: ConsoleKind {
        firmware.kind
    }
}

/// The firmware family of a console, which selects the Remote Play protocol variant the core speaks to it.
///
/// A PS4 below system software 8.0 needs an older variant than one on 10.0 or later, so the family is
/// persisted in `consoles.firmware` and never collapsed to the generation. The raw values are the stored
/// text.
public enum ConsoleFirmware: String, CaseIterable, Hashable, Sendable {
    /// A PS4 on system software below 8.0.
    case ps4_8

    /// A PS4 on system software 8.0 up to but not including 10.0.
    case ps4_9

    /// A PS4 on system software 10.0 or later.
    case ps4_10

    /// A PS5.
    case ps5

    /// The console generation the family belongs to.
    public var kind: ConsoleKind {
        switch self {
        case .ps4_8, .ps4_9, .ps4_10:
            .ps4
        case .ps5:
            .ps5
        }
    }

    /// The family assumed for a console of a generation when nothing more is known.
    ///
    /// - Parameter kind: The console generation.
    /// - Returns: ``ps4_10`` for a PS4 and ``ps5`` for a PS5.
    public static func assumed(for kind: ConsoleKind) -> ConsoleFirmware {
        switch kind {
        case .ps4:
            .ps4_10
        case .ps5:
            .ps5
        }
    }
}

/// Who supplied a console's name, in ascending order of precedence.
///
/// The core lets a newly learned name replace the held one only when its source ranks at least as high, so the
/// source is persisted in `consoles.name_source` beside the name. The raw values are the stored text.
public enum ConsoleNameSource: String, CaseIterable, Hashable, Sendable {
    /// A placeholder such as "PS5", used until a real name is learned.
    case generation

    /// The name PSN holds for the console on the account.
    case account

    /// The nickname the console stated when it was paired.
    case pairing

    /// The name the console stated when it answered a network search.
    case discovered

    /// A name the user chose. It outranks every other source.
    case renamed
}

/// What remembering a discovered address did to a saved console.
public enum ConsoleAddressUpdate: Equatable, Sendable {
    /// No console with that hardware id is saved.
    case unregistered

    /// The console already had that address.
    case unchanged

    /// The address was replaced; the previous one is given when there was one.
    case updated(previous: String?)
}
