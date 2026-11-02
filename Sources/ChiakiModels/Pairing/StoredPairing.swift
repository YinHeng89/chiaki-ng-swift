/// One account's pairing with one console, as persisted.
///
/// The pairing owns its ``PairingCredentials``, which cannot be copied, so a stored pairing is a reference:
/// it can sit in an array, and its keys are wiped once the last reference goes.
public final class StoredPairing: Sendable {
    /// The account the pairing belongs to.
    public let account: AccountID

    /// The console the pairing is with.
    public let console: HardwareID

    /// The secret keys the console issued.
    public let credentials: PairingCredentials

    /// PSN's identifier for the console on the account, once known. Needed to reach a PS5 over the internet.
    public let deviceUID: ConsoleDeviceUID?

    /// Creates a stored pairing.
    ///
    /// - Parameters:
    ///   - account: The account the pairing belongs to.
    ///   - console: The console it is with.
    ///   - credentials: The keys; ownership moves into the pairing.
    ///   - deviceUID: PSN's identifier for the console, if known.
    public init(
        account: AccountID,
        console: HardwareID,
        credentials: consuming PairingCredentials,
        deviceUID: ConsoleDeviceUID?
    ) {
        self.account = account
        self.console = console
        self.credentials = credentials
        self.deviceUID = deviceUID
    }
}

/// The secret keys a console issued to one account when it was paired.
///
/// Both keys live in ``SecretBytes``, so the credentials cannot be copied and are wiped when destroyed.
public struct PairingCredentials: ~Copyable, Sendable {
    /// The length of each key in bytes.
    public static let keyLength = 16

    /// The registration key.
    public let registrationKey: SecretBytes

    /// The Remote Play key.
    public let remotePlayKey: SecretBytes

    /// The key type the console reported.
    public let keyType: UInt32

    /// Takes ownership of two keys.
    ///
    /// - Parameters:
    ///   - registrationKey: The registration key.
    ///   - remotePlayKey: The Remote Play key.
    ///   - keyType: The key type the console reported.
    /// - Returns: `nil` unless both keys are ``keyLength`` bytes. The keys are wiped either way.
    public init?(
        registrationKey: consuming SecretBytes,
        remotePlayKey: consuming SecretBytes,
        keyType: UInt32
    ) {
        guard registrationKey.count == Self.keyLength, remotePlayKey.count == Self.keyLength else {
            return nil
        }
        self.registrationKey = registrationKey
        self.remotePlayKey = remotePlayKey
        self.keyType = keyType
    }

    /// Compares two sets of credentials without revealing where they differ.
    ///
    /// - Parameter other: The credentials to compare with.
    /// - Returns: `true` when both keys and the key type match.
    public func isEqual(to other: borrowing PairingCredentials) -> Bool {
        keyType == other.keyType
            && registrationKey.isEqual(to: other.registrationKey)
            && remotePlayKey.isEqual(to: other.remotePlayKey)
    }
}
