import Foundation

/// The paired console and account a stream is started for.
public struct PlayTarget: Equatable, Sendable {
    /// The account the console is paired with.
    public let accountID: AccountID

    /// The console's hardware id.
    public let hardwareID: HardwareID

    /// The console's name.
    public let name: String

    /// The console's last address, if known.
    public let address: String?

    /// Whether the console is a PS5.
    public let ps5: Bool

    /// PSN's 32-byte identifier for the console on the account, when it can be reached over the internet.
    public let remoteDeviceID: Data?

    /// Describes a play target.
    ///
    /// - Parameters:
    ///   - accountID: The account.
    ///   - hardwareID: The console's hardware id.
    ///   - name: The console's name.
    ///   - address: The last address.
    ///   - ps5: Whether the console is a PS5.
    ///   - remoteDeviceID: PSN's identifier for the console.
    public init(
        accountID: AccountID,
        hardwareID: HardwareID,
        name: String,
        address: String?,
        ps5: Bool,
        remoteDeviceID: Data?
    ) {
        self.accountID = accountID
        self.hardwareID = hardwareID
        self.name = name
        self.address = address
        self.ps5 = ps5
        self.remoteDeviceID = remoteDeviceID
    }
}
