/// Why a console was not woken.
public enum WakeRefusal: Error, Hashable, Sendable, CaseIterable {
    /// The account has no pairing with the console.
    case notPaired

    /// No address is known for the console.
    case noAddress

    /// The network refused the wake packet.
    case network

    /// The console did not answer.
    case notFound

    /// The console stayed in rest mode.
    case stillInRestMode

    /// The wait was cancelled.
    case cancelled

    /// The console was forgotten while it was woken.
    case forgotten

    /// The core is not open.
    case notAvailable

    /// The account or console is not one the core holds.
    case unknown
}

/// Why a pairing was not removed.
public enum UnpairRefusal: Error, Hashable, Sendable, CaseIterable {
    /// The console store could not be written.
    case storeUnavailable

    /// The console or account is not one the core holds.
    case unknownConsole

    /// The core is not open.
    case notAvailable
}
