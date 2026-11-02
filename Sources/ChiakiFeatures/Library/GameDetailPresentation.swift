import ChiakiModels
import Foundation
import SwiftUI
import MenuFocus

/// The display-ready text of a game's catalogue details: star rating, age rating, media list and fact rows,
/// formatted for a locale.
public struct GameDetailPresentation: Equatable {
    /// One row of the star breakdown: how many stars and the share of ratings that gave them.
    public struct Bar: Equatable, Identifiable {
        /// The star count the row is for, from one to five.
        public let stars: Int
        /// The percentage of ratings with that many stars, clamped to 0 through 100.
        public let percent: Int

        /// Creates a bar.
        ///
        /// - Parameters:
        ///   - stars: The star count the row is for, from one to five.
        ///   - percent: The percentage of ratings with that many stars, clamped to 0 through 100.
        public init(stars: Int, percent: Int) {
            self.stars = stars
            self.percent = percent
        }

        /// Identifies the row by its star count.
        public var id: Int {
            stars
        }
    }

    /// The game's star rating ready to draw.
    public struct Rating: Equatable {
        /// The average rating, as the catalogue words it or formatted to two decimals.
        public let average: String
        /// How many of the five stars are filled, the average rounded.
        public let filledStars: Int
        /// The number of ratings with its noun, such as "1 rating" or "1,204 ratings".
        public let count: String
        /// The breakdown rows from five stars down to one.
        public let bars: [Bar]

        /// Creates a rating.
        ///
        /// - Parameters:
        ///   - average: The average rating, as the catalogue words it or formatted to two decimals.
        ///   - filledStars: How many of the five stars are filled, the average rounded.
        ///   - count: The number of ratings with its noun, such as "1 rating" or "1,204 ratings".
        ///   - bars: The breakdown rows from five stars down to one.
        public init(average: String, filledStars: Int, count: String, bars: [Bar]) {
            self.average = average
            self.filledStars = filledStars
            self.count = count
            self.bars = bars
        }
    }

    /// The game's age rating ready to draw.
    public struct Age: Equatable {
        /// The address of the rating board's badge, when there is one.
        public let icon: String?
        /// The rating's name with underscores turned into spaces.
        public let name: String
        /// The content descriptors joined with commas, or `nil` when there are none.
        public let descriptors: String?

        /// Creates an age.
        ///
        /// - Parameters:
        ///   - icon: The address of the rating board's badge, when there is one.
        ///   - name: The rating's name with underscores turned into spaces.
        ///   - descriptors: The content descriptors joined with commas, or `nil` when there are none.
        public init(icon: String?, name: String, descriptors: String?) {
            self.icon = icon
            self.name = name
            self.descriptors = descriptors
        }
    }

    /// One item in the media rail.
    public enum Media: Equatable, Identifiable {
        /// A trailer video.
        case trailer(URL)
        /// A screenshot, by its image address.
        case screenshot(String)

        /// Identifies the item by its address.
        public var id: String {
            switch self {
            case .trailer(let url):
                url.absoluteString
            case .screenshot(let url):
                url
            }
        }

        /// Whether the item is a screenshot rather than a trailer.
        public var isScreenshot: Bool {
            if case .screenshot = self {
                return true
            }
            return false
        }
    }

    /// A labelled fact row such as the publisher, release date or genres.
    public struct Fact: Equatable, Identifiable {
        /// The row's label.
        public let label: String
        /// The row's value.
        public let value: String

        /// Creates a fact.
        ///
        /// - Parameters:
        ///   - label: The row's label.
        ///   - value: The row's value.
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }

        /// Identifies the row by its label.
        public var id: String {
            label
        }
    }

    /// The star rating, or `nil` when the game has no ratings or the breakdown is incomplete.
    public let rating: Rating?
    /// The age rating, or `nil` when it has neither a name nor a badge.
    public let age: Age?
    /// The screenshots followed by the trailers.
    public let media: [Media]
    /// The publisher, release date and genre rows that have values.
    public let facts: [Fact]

    /// Formats a game's details for display.
    ///
    /// - Parameters:
    /// - details: The catalogue details.
    /// - locale: The locale numbers and dates are formatted for.
    /// - timeZone: The time zone the release date is shown in; GMT by default.
    public init(_ details: GameDetails, locale: Locale = .current, timeZone: TimeZone = .gmt) {
        rating = details.starRating.flatMap { Self.rating($0, locale: locale) }
        age = details.ageRating.flatMap(Self.age)
        media = details.screenshots.map(Media.screenshot) + details.trailers.map(Media.trailer)
        var facts: [Fact] = []
        if !details.publisher.isEmpty {
            facts.append(Fact(label: "Publisher", value: details.publisher))
        }
        if let released = details.releasedAt {
            let style = Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: timeZone)
            facts.append(Fact(label: "Released", value: released.formatted(style)))
        }
        if !details.genres.isEmpty {
            facts.append(Fact(label: "Genres", value: details.genres.joined(separator: ", ")))
        }
        self.facts = facts
    }

    /// Whether a star or age rating is there to show the rating band.
    public var showsRatingBand: Bool {
        rating != nil || age != nil
    }

    private static func rating(_ stars: GameDetails.StarRating, locale: Locale) -> Rating? {
        guard stars.ratings > 0, stars.percentByStars.count == 5 else {
            return nil
        }
        let count = stars.ratings.formatted(.number.locale(locale))
        return Rating(
            average: stars.averageText.isEmpty
                ? stars.average.formatted(.number.precision(.fractionLength(2)).locale(locale))
                : stars.averageText,
            filledStars: min(5, max(0, Int(stars.average.rounded()))),
            count: stars.ratings == 1
                ? "\(count) rating"
                : "\(count) ratings",
            bars: (1...5).reversed().map { Bar(
                stars: $0,
                percent: min(100, max(0, stars.percentByStars[$0 - 1]))
            ) }
        )
    }

    private static func age(_ rating: GameDetails.AgeRating) -> Age? {
        guard !rating.name.isEmpty || rating.icon != nil else {
            return nil
        }
        return Age(
            icon: rating.icon, name: rating.name.replacingOccurrences(of: "_", with: " "),
            descriptors: rating.descriptors.isEmpty
                ? nil
                : rating.descriptors.joined(separator: ", ")
        )
    }
}

/// Moves controller focus around the game detail: the close button on top, the action row below it, then the
/// media row.
public enum GameDetailFocusGraph {
    /// Picks the item focus lands on when moving in a direction.
    ///
    /// Left and right move along the current row, up and down move between the rows, and with no focus the
    /// first action, the first media item or the close button is chosen.
    ///
    /// - Parameters:
    /// - current: The focused item, or `nil` when nothing is focused.
    /// - direction: The direction of the move.
    /// - close: The close button.
    /// - actions: The action row, in order.
    /// - media: The media row, in order.
    /// - Returns: The item to focus next, which is `current` when the move goes nowhere.
    public static func next<Item: Hashable>(
        from current: Item?, direction: MenuMoveDirection, close: Item, actions: [Item], media: [Item]
    ) -> Item {
        let entry = actions.first ?? media.first ?? close
        guard let current else {
            return entry
        }
        if current == close {
            return direction == .down || direction == .left
                ? entry
                : close
        }
        if let index = actions.firstIndex(of: current) {
            return fromRow(actions, at: index, direction: direction, above: close, below: media.first)
        }
        if let index = media.firstIndex(of: current) {
            return fromRow(media, at: index, direction: direction, above: actions.first ?? close, below: nil)
        }
        return entry
    }

    private static func fromRow<Item: Hashable>(
        _ row: [Item], at index: Int, direction: MenuMoveDirection, above: Item, below: Item?
    ) -> Item {
        switch direction {
        case .left:
            row[max(0, index - 1)]
        case .right:
            row[min(row.count - 1, index + 1)]
        case .up:
            above
        case .down:
            below ?? row[index]
        @unknown default:
            row[index]
        }
    }
}
