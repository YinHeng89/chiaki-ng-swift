import Foundation

/// Which PSN alerts the app shows, and whose it never shows.
///
/// Decoding tolerates a missing or unknown value and falls back to the default. Muted senders are kept
/// sorted, without duplicates and at most ``mutedLimit`` long.
public struct PSNAlertSettings: Codable, Equatable, Sendable {
    /// The most senders that can be muted.
    public static let mutedLimit = 200

    /// Whether game and party invitations raise an alert.
    public var invitations: Bool

    /// Whether messages raise an alert.
    public var messages: Bool

    /// The online ids whose invitations and messages never raise an alert; they still appear in the list.
    public private(set) var mutedSenders: [String]

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - invitations: Whether game and party invitations raise an alert.
    ///   - messages: Whether messages raise an alert.
    ///   - mutedSenders: The muted online ids.
    public init(invitations: Bool = true, messages: Bool = true, mutedSenders: [String] = []) {
        self.invitations = invitations
        self.messages = messages
        self.mutedSenders = Self.normalized(mutedSenders)
    }

    /// Decodes settings, defaulting anything missing or unreadable.
    ///
    /// - Parameter decoder: The decoder holding the stored settings.
    /// - Throws: `DecodingError` when the stored value is not a keyed container.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        invitations = (try? values.decodeIfPresent(Bool.self, forKey: .invitations)) ?? true
        messages = (try? values.decodeIfPresent(Bool.self, forKey: .messages)) ?? true
        mutedSenders = Self
            .normalized((try? values.decodeIfPresent([String].self, forKey: .mutedSenders)) ?? [])
    }

    /// Whether a sender is muted.
    ///
    /// - Parameter sender: The online id.
    /// - Returns: `true` when the sender's alerts are muted.
    public func isMuted(_ sender: String) -> Bool {
        mutedSenders.contains(sender)
    }

    /// Mutes or unmutes a sender.
    ///
    /// - Parameters:
    ///   - sender: The online id.
    ///   - muted: Whether to mute the sender.
    public mutating func setMuted(_ sender: String, _ muted: Bool) {
        mutedSenders = Self.normalized(
            muted
                ? mutedSenders + [sender]
                : mutedSenders.filter {
                    $0 != sender
                }
        )
    }

    private static func normalized(_ senders: [String]) -> [String] {
        Array(Set(senders.filter {
            !$0.isEmpty
        }).sorted().prefix(mutedLimit))
    }
}

extension PSNAlertSettings: PersistedSettingValue {
    /// The key the alert settings are stored under.
    public static var settingKey: SettingKey<PSNAlertSettings> {
        SettingKeys.psnAlerts
    }
}
