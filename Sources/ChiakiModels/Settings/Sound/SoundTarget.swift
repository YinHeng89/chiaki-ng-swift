import Foundation

/// A kind of stream whose sound support differs.
public enum SoundTarget: CaseIterable, Sendable {
    /// A PS4 stream.
    case ps4

    /// A PS5 stream.
    case ps5

    /// A PS Now cloud stream.
    case psNow

    /// A PS Cloud stream.
    case psCloud

    /// The label shown for the target.
    public var title: LocalizedStringResource {
        switch self {
        case .ps4:
            .settingsSoundTargetPs4
        case .ps5:
            .settingsSoundTargetPs5
        case .psNow:
            .settingsSoundTargetPsNow
        case .psCloud:
            .settingsSoundTargetPsCloud
        }
    }
}
