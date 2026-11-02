import Foundation

/// One pairing between a profile and a console, as the console list shows it.
public struct RegisteredConsole: Equatable, Sendable {
    /// The console's hardware id as twelve hex digits, or `nil` for a console never reached.
    public let hardwareID: String?

    /// The console's row id.
    public let id: UUID

    /// The console's name.
    public let name: String

    /// The profile id of the paired account.
    public let accountID: UUID

    /// The console's last address, or its name when no address is known.
    public let address: String

    /// Whether the console is a PS5.
    public let ps5: Bool

    /// PSN's identifier for the console on the account, if known.
    public let remoteDeviceID: Data?

    /// Describes a pairing.
    ///
    /// - Parameters:
    ///   - hardwareID: The hardware id as hex.
    ///   - id: The console's row id.
    ///   - name: The console's name.
    ///   - accountID: The paired profile's id.
    ///   - address: The last address or the name.
    ///   - ps5: Whether the console is a PS5.
    ///   - remoteDeviceID: PSN's identifier for the console.
    public init(
        hardwareID: String?,
        id: UUID,
        name: String,
        accountID: UUID,
        address: String,
        ps5: Bool,
        remoteDeviceID: Data?
    ) {
        self.hardwareID = hardwareID
        self.id = id
        self.name = name
        self.accountID = accountID
        self.address = address
        self.ps5 = ps5
        self.remoteDeviceID = remoteDeviceID
    }
}
