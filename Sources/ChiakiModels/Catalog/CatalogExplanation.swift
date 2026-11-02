/// Why the catalog listed or hid one title, rule by rule.
public struct CatalogExplanation: Equatable, Sendable {
    /// One rule's judgement.
    public struct Step: Equatable, Sendable {
        /// The rule.
        public let rule: CatalogRule

        /// How the rule judged.
        public let outcome: CatalogStepOutcome

        /// Whether the rule hides the title.
        public let hides: Bool

        /// The product the rule looked at.
        public let productID: String?

        /// The ownership the rule looked at.
        public let ownershipID: String?

        /// The title number the rule looked at.
        public let titleNumber: String?

        /// The membership tier the rule looked at.
        public let tier: PlusTier?

        /// Describes a step.
        ///
        /// - Parameters:
        ///   - rule: The rule.
        ///   - outcome: How it judged.
        ///   - hides: Whether it hides the title.
        ///   - productID: The product.
        ///   - ownershipID: The ownership.
        ///   - titleNumber: The title number.
        ///   - tier: The tier.
        public init(
            rule: CatalogRule,
            outcome: CatalogStepOutcome,
            hides: Bool = false,
            productID: String? = nil,
            ownershipID: String? = nil,
            titleNumber: String? = nil,
            tier: PlusTier? = nil
        ) {
            self.rule = rule
            self.outcome = outcome
            self.hides = hides
            self.productID = productID
            self.ownershipID = ownershipID
            self.titleNumber = titleNumber
            self.tier = tier
        }
    }

    /// Whether the title is listed.
    public let listed: Bool

    /// The rules in the order they were applied.
    public let steps: [Step]

    /// Describes an explanation.
    ///
    /// - Parameters:
    ///   - listed: Whether the title is listed.
    ///   - steps: The rules applied.
    public init(listed: Bool, steps: [Step]) {
        self.listed = listed
        self.steps = steps
    }
}

/// A rule the catalog applies when it decides whether a title is listed.
public enum CatalogRule: Sendable, CaseIterable {
    /// The streaming service lists the title.
    case listedInCatalog

    /// The title's platform.
    case platform

    /// The title's streaming service.
    case service

    /// Whether PlayStation Plus includes the title.
    case includedWithPlus

    /// The membership tier.
    case tier

    /// Whether the title counts as a game.
    case countsAsGame

    /// Whether the library holds the title.
    case libraryMatch

    /// The title merged into another listing.
    case mergedIntoListing

    /// The title has its own listing.
    case ownListing

    /// An owned duplicate of the title.
    case ownedDuplicate

    /// A trial superseded by the full title.
    case trialSuperseded

    /// A disc upgrade.
    case discUpgrade

    /// Ownership.
    case ownership

    /// Whether the title is native to PS5.
    case ps5Native

    /// A duplicate launch identifier.
    case duplicateLaunch

    /// The title is already owned.
    case alreadyOwned

    /// The streamable list's verdict.
    case listStreamability

    /// The storefront's answer.
    case storefront

    /// A refusal remembered from an earlier launch.
    case rememberedRefusal

    /// The release date.
    case release

    /// The same product listed twice.
    case sameProduct

    /// How the title is reached.
    case accessRoute

    /// The Premium branding.
    case premiumBranding

    /// The Premium entitlement.
    case premiumEntitlement

    /// Joined to the library by entitlement.
    case joinedByEntitlement

    /// Joined to the library by product.
    case joinedByProduct

    /// The bundle's ownership.
    case bundleOwnership
}

/// How one catalog rule judged a title.
public enum CatalogStepOutcome: Sendable, CaseIterable {
    /// The rule passed.
    case passed

    /// The rule failed.
    case failed

    /// The rule noted something without judging.
    case noted

    /// The rule was not checked.
    case unchecked
}

/// A cloud library title paired with the catalogue's explanation of why it is or is not offered.
public struct ExplainedTitle: Equatable, Identifiable, Sendable {
    /// The title's product identifier, which keeps rows stable across reloads.
    public var id: String {
        game.id
    }
    /// The cloud game as the library listed it, including whether it is visible and owned.
    public let game: CloudGame
    /// The rules the catalogue applied to the title and the outcome of each.
    public let explanation: CatalogExplanation
    /// Pairs a cloud game with the catalogue explanation for it.
    public init(game: CloudGame, explanation: CatalogExplanation) {
        self.game = game
        self.explanation = explanation
    }
}
