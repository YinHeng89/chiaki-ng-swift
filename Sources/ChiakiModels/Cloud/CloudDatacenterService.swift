/// The cloud service a datacenter measurement or choice belongs to; the raw values are the stored keys.
public enum CloudDatacenterService: String, Codable, CaseIterable, Hashable, Sendable {
    /// PS Now.
    case psNow = "psnow"

    /// PS Cloud.
    case psCloud = "pscloud"

    /// Reads the service from a catalog `streamServiceType`.
    ///
    /// - Parameter streamServiceType: `psnow` or `pscloud`.
    public init?(streamServiceType: String) {
        self.init(rawValue: streamServiceType)
    }

    /// The service's name.
    public var title: String {
        switch self {
        case .psNow:
            "PS Now"
        case .psCloud:
            "PS Cloud"
        }
    }
}
