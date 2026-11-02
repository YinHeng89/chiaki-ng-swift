import ChiakiModels
import DesignSystem

/// The part of the library shown: the consoles, the cloud games or the account's trophies.
public enum LibrarySection: String, CaseIterable, Sendable {
    /// The account's consoles and their recently played games.
    case consoles = "Consoles"
    /// The account's cloud games.
    case cloud = "Cloud"
    /// The account's trophy level and the trophies it earned in each game.
    case trophies = "Trophies"

    /// The section's icon.
    public var icon: AppIcon {
        switch self {
        case .consoles:
            .console
        case .cloud:
            .cloud
        case .trophies:
            .trophy
        }
    }

    /// The account feature the section needs.
    public var feature: ProfileFeature {
        switch self {
        case .consoles:
            .localPlay
        case .cloud:
            .cloud
        case .trophies:
            .trophies
        }
    }
}
