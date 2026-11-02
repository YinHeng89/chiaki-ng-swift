import ChiakiModels
import Foundation

/// A console card on the shelf: a paired console, or a developer preview of one.
public struct DisplayedConsole: Hashable, Sendable {
    /// The console the card shows.
    public let target: RegistrationFlow.ConsoleTarget
    /// Whether the card is a developer preview that starts nothing.
    public let preview: Bool
    /// The title a preview shows as last played.
    public var sampleTitle: RecentTitle?

    /// Creates a displayed console.
    ///
    /// - Parameters:
    ///   - target: The console the card shows.
    ///   - preview: Whether the card is a developer preview that starts nothing.
    ///   - sampleTitle: The title a preview shows as last played.
    ///   - sampleRecentlyPlayed: Which recently played art a preview shows.
    public init(
        target: RegistrationFlow.ConsoleTarget,
        preview: Bool,
        sampleTitle: RecentTitle? = nil,
        sampleRecentlyPlayed: SampleConsole.RecentlyPlayed = .none
    ) {
        self.target = target
        self.preview = preview
        self.sampleTitle = sampleTitle
        self.sampleRecentlyPlayed = sampleRecentlyPlayed
    }

    /// Which recently played art a preview shows.
    public var sampleRecentlyPlayed: SampleConsole.RecentlyPlayed

    /// Treats two cards as equal when they show the same console with the same preview flag, ignoring sample
    /// art.
    public static func == (lhs: DisplayedConsole, rhs: DisplayedConsole) -> Bool {
        lhs.target == rhs.target && lhs.preview == rhs.preview
    }

    /// Hashes the console and preview flag, matching `==`.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        hasher.combine(preview)
    }

    /// The console a developer preview card of a generation shows.
    ///
    /// - Parameter kind: The console generation.
    /// - Returns: A console that is never paired.
    public static func sample(_ kind: RegistrationFlow.ConsoleKind) -> RegistrationFlow.ConsoleTarget {
        let name: String
        switch kind {
        case .ps5:
            name = "Living Room PS5"
        case .ps4:
            name = "Studio PS4"
        }
        return RegistrationFlow.ConsoleTarget(
            address: "Developer preview",
            kind: kind,
            remoteDeviceID: Data([1]),
            name: name
        )
    }
}
