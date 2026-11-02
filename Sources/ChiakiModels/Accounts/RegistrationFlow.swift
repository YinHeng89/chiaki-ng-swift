import Foundation

/// The known accounts, their console pairings and which account and console are selected.
///
/// The root feature keeps these in its shared `accounts`, `consoleCatalog` and `selectedAccount` values and
/// its selected console, and reads and writes them through this value. Where the user is lives in the root
/// feature's route; this value holds no screen.
public struct RegistrationFlow: Equatable, Sendable {
    /// How an account was added.
    public enum ProfileKind: String, Hashable, Sendable {
        /// Signed in on the web.
        case npsso

        /// Added by account id only.
        case accountID
    }

    /// An account as the root view shows it.
    public struct Profile: Hashable, Sendable {
        /// The profile's row id.
        public let id: UUID

        /// The display name.
        public let name: String

        /// How the account was added.
        public let kind: ProfileKind

        /// The Base64 PSN account id, if known.
        public let accountID: String?

        /// The cached avatar image.
        public var avatarData: Data?

        /// Whether the account has PS Plus.
        public var isPlus: Bool?

        /// When PS Plus membership was last read.
        public var membershipCheckedAt: Date?

        /// When the membership reading goes stale.
        public var membershipExpiresAt: Date?

        /// Describes an account.
        ///
        /// - Parameters:
        ///   - id: The profile's row id.
        ///   - name: The display name.
        ///   - kind: How the account was added.
        ///   - accountID: The Base64 PSN account id.
        public init(id: UUID, name: String, kind: ProfileKind, accountID: String?) {
            self.id = id
            self.name = name
            self.kind = kind
            self.accountID = accountID
        }
    }

    /// A console's generation as shown.
    public enum ConsoleKind: String, CaseIterable, Hashable, Sendable {
        /// A PlayStation 5.
        case ps5 = "PS5"

        /// A PlayStation 4.
        case ps4 = "PS4"
    }

    /// A console as the root view shows it.
    public struct ConsoleTarget: Hashable, Sendable {
        /// The last address, or the name for a console reached over the internet.
        public let address: String

        /// The generation.
        public let kind: ConsoleKind

        /// PSN's identifier for the console, when it can be reached over the internet.
        public let remoteDeviceID: Data?

        /// The console's row id, once paired.
        public let id: UUID?

        /// The console's name.
        public let name: String?

        /// The hardware id as hex.
        public let hardwareID: String?

        /// Describes a console.
        ///
        /// - Parameters:
        ///   - address: The address or name.
        ///   - kind: The generation.
        ///   - remoteDeviceID: PSN's identifier for the console.
        ///   - id: The row id.
        ///   - name: The name.
        ///   - hardwareID: The hardware id as hex.
        public init(
            address: String, kind: ConsoleKind, remoteDeviceID: Data? = nil, id: UUID? = nil,
            name: String? = nil, hardwareID: String? = nil
        ) {
            self.address = address
            self.kind = kind
            self.remoteDeviceID = remoteDeviceID
            self.id = id
            self.name = name
            self.hardwareID = hardwareID
        }
    }

    /// A pairing between an account and a console.
    public struct Registration: Hashable, Sendable {
        /// The account.
        public let profileID: UUID

        /// The console.
        public let console: ConsoleTarget

        /// Describes a pairing.
        ///
        /// - Parameters:
        ///   - profileID: The account.
        ///   - console: The console.
        public init(profileID: UUID, console: ConsoleTarget) {
            self.profileID = profileID
            self.console = console
        }
    }

    /// Every known account.
    public internal(set) var profiles: [Profile]

    /// Every pairing of a known account.
    public internal(set) var registrations: [Registration]

    /// The selected account.
    public internal(set) var selectedProfileID: UUID?

    /// The selected console.
    public internal(set) var selectedConsole: ConsoleTarget?

    /// Creates the accounts and pairings.
    ///
    /// - Parameters:
    ///   - profiles: Every known account.
    ///   - registrations: Every pairing.
    ///   - selectedProfileID: The selected account.
    ///   - selectedConsole: The selected console.
    public init(
        profiles: [Profile] = [],
        registrations: [Registration] = [],
        selectedProfileID: UUID? = nil,
        selectedConsole: ConsoleTarget? = nil
    ) {
        self.profiles = profiles
        self.registrations = registrations
        self.selectedProfileID = selectedProfileID
        self.selectedConsole = selectedConsole
    }

    /// The selected account.
    public var selectedProfile: Profile? {
        profiles.first {
            $0.id == selectedProfileID
        }
    }

    /// The consoles paired with the selected account.
    public var linkedConsoles: [ConsoleTarget] {
        registrations.filter {
            $0.profileID == selectedProfileID
        }.map(\.console)
    }

    /// The paired console with this row id for an account.
    ///
    /// - Parameters:
    ///   - consoleID: The console's row id.
    ///   - account: The account.
    /// - Returns: The console, or `nil` when the account is not paired with it.
    public func console(_ consoleID: UUID, of account: UUID) -> ConsoleTarget? {
        registrations.first {
            $0.profileID == account && $0.console.id == consoleID
        }?.console
    }

    /// Shows the accounts, selecting one.
    ///
    /// - Parameters:
    ///   - saved: The accounts.
    ///   - selected: The account to select; otherwise the current or the first one.
    public mutating func restoreProfiles(_ saved: [Profile], selected: UUID? = nil) {
        profiles = saved
        selectedProfileID = selected ?? selectedProfileID ?? saved.first?.id
    }

    /// Selects the account remembered as selected, if it is known.
    ///
    /// - Parameter id: The remembered account.
    public mutating func restoreSelection(_ id: UUID) {
        guard selectedProfileID != id, profiles.contains(where: { $0.id == id }) else {
            return
        }
        selectedProfileID = id
        selectedConsole = nil
    }

    /// Replaces the pairings with the saved ones of known accounts.
    ///
    /// - Parameter saved: The saved pairings.
    public mutating func restoreRegistrations(_ saved: [Registration]) {
        registrations = saved.filter { edge in
            profiles.contains {
                $0.id == edge.profileID
            }
        }
    }

    /// Forgets a deleted account with its pairings.
    ///
    /// - Parameter id: The deleted account.
    public mutating func removeProfile(_ id: UUID) {
        registrations.removeAll {
            $0.profileID == id
        }
        profiles.removeAll {
            $0.id == id
        }
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
            selectedConsole = nil
        }
    }

    /// Replaces the accounts after a refresh, selecting the first one when the selected account is gone.
    ///
    /// - Parameter saved: The refreshed accounts.
    /// - Returns: `true` when the selected account is gone.
    @discardableResult
    public mutating func updateProfiles(_ saved: [Profile]) -> Bool {
        profiles = saved
        guard !saved.contains(where: { $0.id == selectedProfileID }) else {
            return false
        }
        selectedProfileID = saved.first?.id
        selectedConsole = nil
        return true
    }

    /// Selects a known account.
    ///
    /// - Parameter id: The account.
    /// - Returns: `true` when the account is known.
    @discardableResult
    public mutating func selectProfile(_ id: UUID) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else {
            return false
        }
        selectedProfileID = id
        selectedConsole = nil
        return true
    }

    /// Selects a console paired with the selected account.
    ///
    /// - Parameter target: The console.
    /// - Returns: `true` when the console is paired with the selected account.
    @discardableResult
    public mutating func selectConsole(_ target: ConsoleTarget) -> Bool {
        guard linkedConsoles.contains(target) else {
            return false
        }
        selectedConsole = target
        return true
    }

    /// Selects an account and one of its paired consoles for a stream.
    ///
    /// - Parameters:
    ///   - profile: The account the console is paired with.
    ///   - console: The console.
    /// - Returns: `true` when the pairing exists.
    @discardableResult
    public mutating func selectStream(profile: UUID, console: ConsoleTarget) -> Bool {
        guard registrations.contains(Registration(profileID: profile, console: console)) else {
            return false
        }
        selectedProfileID = profile
        selectedConsole = console
        return true
    }

    /// Records a console the selected account just paired with and selects it.
    ///
    /// - Parameter target: The paired console.
    /// - Returns: `true` when an account is selected.
    @discardableResult
    public mutating func recordPairing(_ target: ConsoleTarget) -> Bool {
        guard let profileID = selectedProfileID else {
            return false
        }
        let registration = Registration(profileID: profileID, console: target)
        if !registrations.contains(registration) {
            registrations.append(registration)
        }
        selectedConsole = target
        return true
    }

    /// Forgets the selected account's pairing with a console whose pairing was refused.
    ///
    /// - Parameter target: The console.
    public mutating func forgetPairing(_ target: ConsoleTarget) {
        registrations.removeAll {
            $0.profileID == selectedProfileID && $0.console == target
        }
        selectedConsole = nil
    }
}

public extension RegistrationFlow.Profile {
    /// Describes a saved account as the screens show it.
    ///
    /// - Parameter profile: The saved account.
    init(_ profile: AccountProfile) {
        self.init(
            id: profile.id,
            name: profile.name,
            kind: profile.method == .npsso
                ? .npsso
                : .accountID,
            accountID: profile.accountID.base64
        )
        avatarData = profile.avatarData
        isPlus = profile.isPlus
        membershipCheckedAt = profile.membershipCheckedAt
        membershipExpiresAt = profile.membershipExpiresAt
    }
}

public extension RegistrationFlow.Registration {
    /// Describes a saved pairing as the screens show it.
    ///
    /// - Parameter console: The saved pairing.
    init(_ console: RegisteredConsole) {
        self.init(
            profileID: console.accountID,
            console: RegistrationFlow.ConsoleTarget(
                address: console.address,
                kind: console.ps5
                    ? .ps5
                    : .ps4,
                remoteDeviceID: console.remoteDeviceID,
                id: console.id,
                name: console.name,
                hardwareID: console.hardwareID
            )
        )
    }
}

public extension RegistrationFlow.ConsoleTarget {
    /// Describes a console a pairing just saved.
    ///
    /// - Parameter console: The paired console.
    init(paired console: PairedConsole) {
        self.init(
            address: console.address ?? console.name,
            kind: console.kind == .ps5
                ? .ps5
                : .ps4,
            name: console.name,
            hardwareID: console.hardwareID.hex
        )
    }

    /// Where to pair this console: at home by address, or over the internet by its PSN identifier.
    ///
    /// `nil` when the PSN identifier is malformed.
    var pairingTarget: PairingTarget? {
        let generation: ChiakiModels.ConsoleKind = kind == .ps5
            ? .ps5
            : .ps4
        guard let device = remoteDeviceID else {
            return .atHome(address: address, kind: generation)
        }
        guard let uid = ConsoleDeviceUID(bytes: device) else {
            return nil
        }
        return .overInternet(AccountConsoleTarget(
            deviceUID: uid,
            name: name ?? kind.rawValue,
            kind: generation
        ))
    }
}
