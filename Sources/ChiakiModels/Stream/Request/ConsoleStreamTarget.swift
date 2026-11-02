import Foundation

/// The paired console a console stream is started for, and the profile it is paired with.
public struct ConsoleStreamTarget: Hashable, Sendable {
    /// The app profile the console is paired with.
    public let profile: ProfileID

    /// The stored console, when the console has been saved.
    public let console: ConsoleID?

    /// The console's last known address.
    public let address: String

    /// The console generation.
    public let kind: ConsoleKind

    /// The console's name, when known.
    public let name: String?

    /// PSN's identifier for the console, when it can be reached over the internet.
    public let remoteDeviceID: Data?

    /// Describes a console target.
    ///
    /// - Parameters:
    ///   - profile: The profile the console is paired with.
    ///   - console: The stored console.
    ///   - address: The last known address.
    ///   - kind: The console generation.
    ///   - name: The console's name.
    ///   - remoteDeviceID: PSN's identifier for the console.
    public init(
        profile: ProfileID,
        console: ConsoleID?,
        address: String,
        kind: ConsoleKind,
        name: String? = nil,
        remoteDeviceID: Data? = nil
    ) {
        self.profile = profile
        self.console = console
        self.address = address
        self.kind = kind
        self.name = name
        self.remoteDeviceID = remoteDeviceID
    }
}
