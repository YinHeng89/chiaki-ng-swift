import ChiakiModels
import Foundation

/// The streaming service whose titles the entitlements panel lists: PlayStation Now for PS4 and PS3, or PS5
/// cloud streaming.
public enum EntitlementService: String, CaseIterable, Equatable, Sendable {
    /// PlayStation Now titles for PS4 and PS3, or PS5 cloud streaming titles.
    case psNow = "PS4 and PS3", psCloud = "PS5"

    /// Returns whether the title belongs to this service, judged by its stream service type.
    public func lists(_ title: ExplainedTitle) -> Bool {
        (title.game.streamServiceType == "pscloud") == (self == .psCloud)
    }

    /// The service's name, shown on its segment.
    public var title: LocalizedStringResource {
        switch self {
        case .psNow:
            .settingsEntitlementsServicePsNow
        case .psCloud:
            .settingsEntitlementsServicePsCloud
        }
    }

    /// A sentence describing where this service's title list comes from.
    public var source: LocalizedStringResource {
        switch self {
        case .psNow:
            .settingsEntitlementsSourcePsNow
        case .psCloud:
            .settingsEntitlementsSourcePsCloud
        }
    }

    /// The ordered rules that decide which of this service's titles are offered, written for display.
    public var rules: [LocalizedStringResource] {
        switch self {
        case .psNow:
            [
                .settingsEntitlementsRulePsNowShelf,
                .settingsEntitlementsRulePsNowUncovered,
                .settingsEntitlementsRulePsNowHeldCopy,
                .settingsEntitlementsRulePsNowEdition,
                .settingsEntitlementsRuleBelowPremium,
                .settingsEntitlementsRulePsNowLaunch
            ]
        case .psCloud:
            [
                .settingsEntitlementsRulePsCloudStreamable,
                .settingsEntitlementsRulePsCloudPremium,
                .settingsEntitlementsRulePsCloudLibrary,
                .settingsEntitlementsRulePsCloudNoStreaming,
                .settingsEntitlementsRulePsCloudUnstated,
                .settingsEntitlementsRulePsCloudLaunchCheck,
                .settingsEntitlementsRulePsCloudLaunchUnasked,
                .settingsEntitlementsRulePsCloudLaunchStated,
                .settingsEntitlementsRulePsCloudDuplicate,
                .settingsEntitlementsRulePsCloudEdition,
                .settingsEntitlementsRuleBelowPremium
            ]
        }
    }
}
