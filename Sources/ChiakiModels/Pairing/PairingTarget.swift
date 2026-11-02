/// The console a pairing attempt is aimed at, and how it is reached.
public enum PairingTarget: Hashable, Sendable {
    /// A console reached directly on the local network at an address the user typed or discovery found.
    /// Pairing it needs the PIN the console shows.
    case atHome(address: String, kind: ConsoleKind)

    /// A console listed on the user's PSN account, paired through PSN without a PIN.
    case overInternet(AccountConsoleTarget)

    /// The console generation.
    public var kind: ConsoleKind {
        switch self {
        case .atHome(_, let kind):
            kind
        case .overInternet(let console):
            console.kind
        }
    }

    /// Whether the user has to type the console's PIN before the attempt can start.
    public var needsPIN: Bool {
        switch self {
        case .atHome:
            true
        case .overInternet:
            false
        }
    }
}

/// A console listed on a PlayStation Network account, chosen for pairing over the internet.
public struct AccountConsoleTarget: Hashable, Sendable {
    /// PSN's identifier for the console on the account.
    public let deviceUID: ConsoleDeviceUID

    /// The name PSN holds for the console.
    public let name: String

    /// The console generation.
    public let kind: ConsoleKind

    /// Creates a target from what PSN listed.
    ///
    /// - Parameters:
    ///   - deviceUID: PSN's identifier for the console.
    ///   - name: The name PSN holds for it.
    ///   - kind: The console generation.
    public init(deviceUID: ConsoleDeviceUID, name: String, kind: ConsoleKind) {
        self.deviceUID = deviceUID
        self.name = name
        self.kind = kind
    }

    /// Whether the target is the account's primary PS4 rather than one listed console.
    public var isMainPS4: Bool {
        kind == .ps4 && deviceUID.isMainPS4
    }
}
