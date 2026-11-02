import Foundation

/// How the catalog last fetched an account's titles.
public struct CatalogFetchReport: Equatable, Sendable {
    /// How many owned copies were checked.
    public struct CopiesChecked: Equatable, Sendable {
        /// Copies asked about.
        public let asked: Int

        /// Copies answered.
        public let answered: Int

        /// Describes a check.
        ///
        /// - Parameters:
        ///   - asked: Copies asked about.
        ///   - answered: Copies answered.
        public init(asked: Int, answered: Int) {
            self.asked = asked
            self.answered = answered
        }
    }

    /// Who the cloud catalog was read for.
    public struct Audience: Equatable, Sendable {
        /// The country.
        public let country: String

        /// The language.
        public let language: String

        /// The age.
        public let age: Int

        /// Describes an audience.
        ///
        /// - Parameters:
        ///   - country: The country.
        ///   - language: The language.
        ///   - age: The age.
        public init(country: String, language: String, age: Int) {
            self.country = country
            self.language = language
            self.age = age
        }
    }

    /// The Premium streaming category as last read.
    public struct PremiumCategory: Equatable, Sendable {
        /// When it was read.
        public let fetchedAt: Date

        /// How many titles it held.
        public let titles: Int

        /// Describes a reading.
        ///
        /// - Parameters:
        ///   - fetchedAt: When it was read.
        ///   - titles: How many titles it held.
        public init(fetchedAt: Date, titles: Int) {
            self.fetchedAt = fetchedAt
            self.titles = titles
        }
    }

    /// What is known about the owned library.
    public enum Library: Equatable, Sendable {
        /// The library was not fetched.
        case unknown

        /// The library could not be fetched.
        case unavailable

        /// The library was fetched, possibly in part.
        case fetched(Date, records: Int)
    }

    /// Whether the list came from the account service.
    public var fromAccountService = true

    /// Whether the list was complete.
    public var complete = true

    /// When the list was fetched.
    public var listFetchedAt = Date(timeIntervalSince1970: 0)

    /// How many PlayStation Now titles were listed.
    public var psNowTitles = 0

    /// How many owned copies were checked.
    public var copiesChecked: CopiesChecked?

    /// How many titles had no covered copy.
    public var withoutACoveredCopy = 0

    /// How many cloud titles were listed.
    public var psCloudTitles = 0

    /// Who the cloud catalog was read for.
    public var audience: Audience?

    /// The Premium streaming category.
    public var premiumCategory: PremiumCategory?

    /// What is known about the owned library.
    public var library = Library.unknown

    /// The membership tier, when known.
    public var tier: PlusTier?

    /// Creates an empty report.
    public init() {}
}
