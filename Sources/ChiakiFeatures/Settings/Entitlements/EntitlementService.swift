import ChiakiModels

/// The streaming service whose titles the entitlements panel lists: PlayStation Now for PS4 and PS3, or PS5
/// cloud streaming.
public enum EntitlementService: String, CaseIterable, Equatable, Sendable {
    /// PlayStation Now titles for PS4 and PS3, or PS5 cloud streaming titles.
    case psNow = "PS4 and PS3", psCloud = "PS5"

    /// Returns whether the title belongs to this service, judged by its stream service type.
    public func lists(_ title: ExplainedTitle) -> Bool {
        (title.game.streamServiceType == "pscloud") == (self == .psCloud)
    }

    /// A sentence describing where this service's title list comes from.
    public var source: String {
        switch self {
        case .psNow:
            "The PlayStation Now shelves, with each PS4 title checked against the store catalogue for a "
                + "streaming copy that a plan covers"
        case .psCloud:
            "The PlayStation Store's PS5 lists for names and artwork, plan inclusion from the Premium streaming "
                + "category asked for the account's country, language and age, and the account's own PS5 "
                + "entitlements for whether each owned copy streams"
        }
    }

    /// The ordered rules that decide which of this service's titles are offered, written for display.
    public var rules: [String] {
        switch self {
        case .psNow:
            [
                "A title on a shelf is offered",
                "A PS4 title whose streaming copy no plan covers is dropped unless the copy is already held",
                "A held streaming copy licenses its title, on or off the shelf",
                "An edition covered by a licensed edition is dropped",
                "Every title is dropped when the membership is below Premium",
                "At launch the title page is asked again and a copy no plan covers is refused"
            ]
        case .psCloud:
            [
                "A PS5 title the store marks as streamable is listed",
                "A full game in the Premium streaming category is included with the plan",
                "A title in the library is playable when its copy is a PS5 version",
                "An owned PS5 copy the store says does not support streaming is dropped unless the plan includes it",
                "An owned PS5 copy whose streaming the store did not state is kept",
                "At launch an owned PS5 copy is checked with the store again and refused when it does not stream",
                "At launch a copy the store cannot be asked about is refused",
                "At launch the store decides only when the entitlement does not state streaming",
                "A title that launches as another listed title is dropped",
                "An edition covered by an owned edition is dropped",
                "Every title is dropped when the membership is below Premium"
            ]
        }
    }
}
