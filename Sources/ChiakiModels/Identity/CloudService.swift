/// The PlayStation cloud streaming service a game or datacenter belongs to.
///
/// The raw values are the `streamServiceType` strings the catalog reports and the keys the datacenter
/// settings are stored under, so ``CloudService/init(rawValue:)`` reads both directly.
public enum CloudService: String, Codable, CaseIterable, Hashable, Sendable {
    /// The PS5-generation cloud streaming service, reported as `"pscloud"`.
    case psCloud = "pscloud"

    /// The older PlayStation Now service, reported as `"psnow"`.
    case psNow = "psnow"
}
