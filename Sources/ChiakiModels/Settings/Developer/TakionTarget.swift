import Foundation

/// A kind of stream whose Takion protocol version can be overridden.
public enum TakionTarget: String, CaseIterable, Codable, Sendable {
    /// PS4 streams, local and remote.
    case localPS4

    /// PS5 streams, local and remote.
    case localPS5

    /// PS Now cloud streams.
    case psNow

    /// PS Cloud streams.
    case psCloud

    /// The label shown for the target.
    public var title: LocalizedStringResource {
        switch self {
        case .localPS4:
            .settingsDeveloperTakionLocalPs4
        case .localPS5:
            .settingsDeveloperTakionLocalPs5
        case .psNow:
            .settingsDeveloperTakionPsNow
        case .psCloud:
            .settingsDeveloperTakionPsCloud
        }
    }

    /// Whether the target is a cloud service, which accepts the cloud-only versions too.
    public var isCloud: Bool {
        self == .psCloud
    }

    /// The version the target negotiates when no override is set.
    public var negotiatedVersion: UInt32 {
        switch self {
        case .localPS4, .psNow:
            9
        case .localPS5:
            15
        case .psCloud:
            12
        }
    }
}
