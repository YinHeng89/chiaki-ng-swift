/// How the add-console screen finds the console to pair.
public enum AddConsoleMode: Hashable, Sendable, CaseIterable {
    /// Pick a console the local-network scan found.
    case automatic

    /// Type the console's address.
    case manual

    /// Pick a console registered to the PSN account, paired over the internet.
    case playStation

    /// Whether the mode needs a signed-in PSN account.
    public var needsSignIn: Bool {
        self == .playStation
    }
}
