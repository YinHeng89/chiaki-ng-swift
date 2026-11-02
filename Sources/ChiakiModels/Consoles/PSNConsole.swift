import Foundation

/// A console PSN lists on an account.
public struct PSNConsole: Equatable, Identifiable, Sendable {
    /// The device id bytes, which identify the console.
    public var id: Data {
        deviceID
    }

    /// The console's device id bytes.
    public let deviceID: Data

    /// The console's name.
    public let name: String

    /// Whether the console is a PS5.
    public let ps5: Bool

    /// Whether Remote Play is enabled on the console.
    public let remotePlayEnabled: Bool

    /// Describes a console.
    ///
    /// - Parameters:
    ///   - deviceID: The device id bytes.
    ///   - name: The name.
    ///   - ps5: Whether it is a PS5.
    ///   - remotePlayEnabled: Whether Remote Play is enabled.
    public init(deviceID: Data, name: String, ps5: Bool, remotePlayEnabled: Bool) {
        self.deviceID = deviceID
        self.name = name
        self.ps5 = ps5
        self.remotePlayEnabled = remotePlayEnabled
    }

    /// The device id PSN gives the account's main PS4.
    public static let mainPS4DeviceID = Data(
        repeating: ConsoleDeviceUID.mainPS4Byte,
        count: ConsoleDeviceUID.byteCount
    )

    /// The account's main PS4, which PSN does not list.
    public static let mainPS4 = PSNConsole(
        deviceID: mainPS4DeviceID,
        name: "Main PS4 Console",
        ps5: false,
        remotePlayEnabled: true
    )

    /// Whether this is the account's main PS4.
    public var isMainPS4: Bool {
        !ps5 && deviceID == Self.mainPS4DeviceID
    }
}
