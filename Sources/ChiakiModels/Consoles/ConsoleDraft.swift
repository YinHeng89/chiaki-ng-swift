import Foundation

/// A console's settings while the console editor changes them.
public struct ConsoleDraft: Hashable, Sendable {
    /// The most characters a console name may have.
    public static let maximumNameLength = 100

    /// The console's row id.
    public let id: UUID

    /// The name being edited.
    public var name: String

    /// The address being edited.
    public var address: String

    /// The console's generation as shown, such as `"PS5"`.
    public let generation: String

    /// Whether the console can be reached over the internet.
    public let remoteAvailable: Bool

    /// The console's hardware id as hex, if known.
    public let hardwareID: String?

    /// Whether the app connects to the console at launch.
    public var connectAtLaunch: Bool

    /// Whether a login PIN is saved, or is to be forgotten.
    public var loginPIN: ConsoleLoginPIN

    /// Describes a draft.
    ///
    /// - Parameters:
    ///   - id: The console's row id.
    ///   - name: The current name.
    ///   - address: The current address.
    ///   - generation: The generation as shown.
    ///   - remoteAvailable: Whether the console can be reached over the internet.
    ///   - hardwareID: The hardware id as hex.
    ///   - connectAtLaunch: Whether to connect at launch.
    ///   - loginPIN: Whether a login PIN is saved.
    public init(
        id: UUID,
        name: String,
        address: String,
        generation: String,
        remoteAvailable: Bool,
        hardwareID: String?,
        connectAtLaunch: Bool = false,
        loginPIN: ConsoleLoginPIN = .none
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.generation = generation
        self.remoteAvailable = remoteAvailable
        self.hardwareID = hardwareID
        self.connectAtLaunch = connectAtLaunch
        self.loginPIN = loginPIN
    }

    /// The trimmed name, when it is not empty and not too long.
    public var validName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumNameLength else {
            return nil
        }
        return trimmed
    }

    /// The address, when ``ConsoleAddress`` accepts it.
    public var validAddress: ConsoleAddress? {
        ConsoleAddress(address)
    }

    /// Whether the draft can be saved.
    public var isValid: Bool {
        validName != nil && validAddress != nil
    }

    /// The draft with the options read for the console.
    ///
    /// - Parameter options: The console's saved launch options.
    /// - Returns: The draft showing whether the console connects at launch and whether a login PIN is saved.
    public func applying(_ options: ConsoleLaunchOptions) -> ConsoleDraft {
        var draft = self
        draft.connectAtLaunch = options.connectAtLaunch
        draft.loginPIN = options.loginPINSaved
            ? .saved
            : .none
        return draft
    }
}

/// The address a console is reached at: an IPv4 or IPv6 address or a host name, as typed.
///
/// This is the one validator for typed console addresses. Surrounding whitespace is dropped; the rest must be
/// non-empty, contain no whitespace and fit in a DNS name.
public struct ConsoleAddress: Hashable, Sendable, CustomStringConvertible {
    /// The most bytes an address may have, the length limit of a DNS name.
    public static let maximumLength = 253

    /// The address text, without surrounding whitespace.
    public let text: String

    /// Validates typed text.
    ///
    /// - Parameter typed: The address as typed.
    /// - Returns: `nil` when the text is empty, holds whitespace or is longer than ``maximumLength`` bytes.
    public init?(_ typed: String) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= Self.maximumLength,
              !trimmed.contains(where: \.isWhitespace)
        else {
            return nil
        }
        text = trimmed
    }

    /// The address text.
    public var description: String {
        text
    }
}

/// Whether a console's login PIN is saved, as the console editor shows it.
public enum ConsoleLoginPIN: Hashable, Sendable {
    /// No login PIN is saved.
    case none

    /// A login PIN is saved.
    case saved

    /// The saved login PIN is forgotten when the edit is saved.
    case forgotten
}
