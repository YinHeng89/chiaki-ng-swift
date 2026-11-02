/// The console a successful pairing attempt saved.
public struct PairedConsole: Hashable, Sendable {
    /// The console's hardware id.
    public let hardwareID: HardwareID

    /// The console's display name.
    public let name: String

    /// Who supplied ``name``.
    public let nameSource: ConsoleNameSource

    /// The console's firmware family.
    public let firmware: ConsoleFirmware

    /// The address the console was reached at, if any.
    public let address: String?

    /// Describes a paired console.
    ///
    /// - Parameters:
    ///   - hardwareID: The console's hardware id.
    ///   - name: The display name.
    ///   - nameSource: Who supplied the name.
    ///   - firmware: The firmware family.
    ///   - address: The address it was reached at, if any.
    public init(
        hardwareID: HardwareID,
        name: String,
        nameSource: ConsoleNameSource,
        firmware: ConsoleFirmware,
        address: String?
    ) {
        self.hardwareID = hardwareID
        self.name = name
        self.nameSource = nameSource
        self.firmware = firmware
        self.address = address
    }

    /// The console generation, derived from ``firmware``.
    public var kind: ConsoleKind {
        firmware.kind
    }
}
