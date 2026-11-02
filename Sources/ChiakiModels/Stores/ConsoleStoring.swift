/// Persists the consoles this device knows and the pairings with them.
///
/// The core calls an implementation from several threads at once, so conforming types must be thread safe.
public protocol ConsoleStoring: Sendable {
    /// Loads every saved console and pairing.
    ///
    /// Pairings that cannot be decrypted or decoded are left out rather than failing the load.
    ///
    /// - Returns: The saved rows.
    /// - Throws: ``ConsoleStoreFailure/unavailable`` when the storage cannot be read.
    func savedConsoles() throws(ConsoleStoreFailure) -> SavedConsoles

    /// Writes a console's facts, replacing any with the same hardware id.
    ///
    /// - Parameter console: The facts to persist.
    /// - Throws: ``ConsoleStoreFailure/unavailable`` when the write failed.
    func save(_ console: StoredConsole) throws(ConsoleStoreFailure)

    /// Writes a pairing, replacing any for the same account and console.
    ///
    /// - Parameter pairing: The pairing to persist. Its keys are secret and are encrypted at rest.
    /// - Throws: ``ConsoleStoreFailure`` when the account or console is unknown or the write failed.
    func save(_ pairing: StoredPairing) throws(ConsoleStoreFailure)

    /// Deletes one account's pairing with a console. The console and other accounts' pairings stay.
    ///
    /// - Parameters:
    ///   - account: The account whose pairing goes.
    ///   - console: The console it was with.
    /// - Throws: ``ConsoleStoreFailure/unavailable`` when the delete failed.
    func removePairing(account: AccountID, console: HardwareID) throws(ConsoleStoreFailure)

    /// Deletes a console and every pairing with it.
    ///
    /// - Parameter console: The console to delete.
    /// - Throws: ``ConsoleStoreFailure/unavailable`` when the delete failed.
    func removeConsole(_ console: HardwareID) throws(ConsoleStoreFailure)
}

/// Why a console store could not complete a read or write.
public enum ConsoleStoreFailure: Error, Hashable, Sendable {
    /// The storage could not be read or written.
    case unavailable

    /// A pairing named an account no profile holds.
    case unknownAccount

    /// A pairing named a console that is not saved.
    case unknownConsole
}

/// Everything a console store holds: the saved consoles and the pairings with them.
public struct SavedConsoles: Sendable {
    /// Every saved console.
    public let consoles: [StoredConsole]

    /// Every saved pairing whose console is among ``consoles``.
    public let pairings: [StoredPairing]

    /// Bundles loaded consoles and pairings.
    ///
    /// - Parameters:
    ///   - consoles: The saved consoles.
    ///   - pairings: The saved pairings.
    public init(consoles: [StoredConsole], pairings: [StoredPairing]) {
        self.consoles = consoles
        self.pairings = pairings
    }
}
