import ChiakiModels
import Foundation

/// Words the cloud library's diagnostic log lines.
public enum CloudLibraryLog {
    /// The line logged when a library fetch starts, saying whether a refresh or opening the library asked for
    /// it.
    ///
    /// - Parameters:
    ///   - who: The account, as a log-safe prefix.
    ///   - locale: The catalog locale.
    ///   - force: Whether the fetch was forced.
    /// - Returns: The log line.
    public static func started(_ who: String, _ locale: String, _ force: Bool) -> String {
        let reason = force
            ? "refresh requested"
            : "library opened"
        return "Fetching the cloud library for \(who) (locale \(locale), \(reason))"
    }

    /// The line logged when every caller cancelled a library fetch.
    ///
    /// - Parameters:
    ///   - who: The account, as a log-safe prefix.
    ///   - locale: The catalog locale.
    ///   - milliseconds: How long the fetch ran.
    /// - Returns: The log line.
    public static func cancelled(_ who: String, _ locale: String, _ milliseconds: Int) -> String {
        "Stopped fetching the cloud library for \(who) after \(milliseconds) ms: "
            + "every caller cancelled; locale \(locale)"
    }

    /// The line logged when a library fetch succeeds, counting owned, PS Plus, PS Cloud, PS Now and hidden
    /// titles.
    ///
    /// - Parameters:
    ///   - snapshot: The fetched library.
    ///   - who: The account, as a log-safe prefix.
    ///   - locale: The catalog locale.
    ///   - milliseconds: How long the fetch took.
    /// - Returns: The log line.
    public static func loaded(_ snapshot: CloudLibrarySnapshot, who: String, locale: String,
                              milliseconds: Int) -> String {
        let games = snapshot.games
        let owned = games.filter(\.isOwned).count
        let plus = snapshot.listedGames.filter(\.isInCatalog).count
        let cloud = games.filter { $0.streamServiceType == "pscloud" }.count
        return "Fetched \(games.count) titles for \(who) in \(milliseconds) ms: \(owned) owned, "
            + "\(plus) in the PS Plus catalog, \(cloud) PS Cloud and \(games.count - cloud) PS Now, "
            + "\(games.count - snapshot.listedGames.count) hidden; locale \(locale)"
    }

    /// The most titles named on one dropped titles line before the rest are only counted.
    public static let droppedTitlesNamedPerLine = 40

    /// One line per service and reason naming the titles the core hid from the library.
    ///
    /// - Parameter snapshot: The fetched library.
    /// - Returns: The log lines, in the order each cause was first seen.
    public static func dropped(_ snapshot: CloudLibrarySnapshot) -> [String] {
        struct Cause: Hashable {
            let service: String
            let reason: String
        }
        var causes: [Cause] = []
        var titles: [Cause: [CloudGame]] = [:]
        for game in snapshot.games where !game.visible {
            let cause = Cause(service: game.streamServiceType, reason: game.hideReason ?? "")
            if titles[cause] == nil {
                causes.append(cause)
            }
            titles[cause, default: []].append(game)
        }
        return causes.map { cause in
            let dropped = titles[cause] ?? []
            let named = dropped.prefix(droppedTitlesNamedPerLine)
                .map { "\"\($0.name)\" (\($0.productId))" }
                .joined(separator: ", ")
            let unnamed = dropped.count - min(dropped.count, droppedTitlesNamedPerLine)
            let rest = unnamed > 0
                ? ", and \(unnamed) more"
                : ""
            let service = cause.service == "pscloud"
                ? "PS Cloud"
                : "PS Now"
            return "Dropped \(dropped.count) \(service) title(s) because "
                + "\(droppedBecause(cause.reason, service: cause.service)): \(named)\(rest)"
        }
    }

    /// Explains a reason code the core gives for hiding a title.
    ///
    /// - Parameters:
    ///   - reason: The core's reason code.
    ///   - service: The title's stream service, `pscloud` or `psnow`.
    /// - Returns: A phrase completing "because".
    public static func droppedBecause(_ reason: String, service: String) -> String {
        switch reason {
        case "not_in_service":
            service == "pscloud"
                ? "the title is not part of the streaming service"
                : "no PlayStation Plus plan covers the title's streaming copy"
        case "not_ps5_native":
            "the copy in the library is not a PS5 version"
        case "duplicate_launch":
            "the title launches as another title that is already listed"
        case "already_owned":
            "an edition already in the library covers it"
        case "tier_does_not_include":
            "the membership tier does not include streaming"
        case "copy_does_not_stream":
            "the store says the owned PS5 copy does not support streaming"
        default:
            "the core gave no reason"
        }
    }

    /// The line logged when a library fetch fails, with the failure explained.
    ///
    /// - Parameters:
    ///   - who: The account, as a log-safe prefix.
    ///   - locale: The catalog locale.
    ///   - milliseconds: How long the fetch ran.
    ///   - error: The failure.
    /// - Returns: The log line.
    public static func failed(_ who: String, _ locale: String, _ milliseconds: Int,
                              _ error: Error) -> String {
        "Fetching the cloud library for \(who) (locale \(locale)) failed after \(milliseconds) ms: \(reason(error))"
    }

    /// The line logged when a title refresh finishes.
    ///
    /// - Parameters:
    ///   - game: The refreshed title.
    ///   - outcome: The refresh outcome.
    ///   - milliseconds: How long the refresh took.
    /// - Returns: The log line.
    public static func titleRefreshed(_ game: CloudGame, outcome: CloudTitleRefreshOutcome,
                                      milliseconds: Int) -> String {
        "Title refresh for \"\(game.name)\" (product \(LogFormat.textPrefix(game.productId, characters: 12))): "
            + "\(outcome.logLabel) in \(milliseconds) ms"
    }

    /// Explains why a library fetch failed.
    ///
    /// - Parameter error: The failure.
    /// - Returns: A plain explanation for library failures, or the error's own description otherwise.
    public static func reason(_ error: Error) -> String {
        switch error {
        case CloudLibraryFailure.signInRequired:
            "the account is not signed in or its sign-in has expired; the account must sign in again"
        case CloudLibraryFailure.invalidCatalog:
            "the catalog could not be read"
        case CloudLibraryFailure.network:
            "the catalog request was not answered (the reason is logged above)"
        case CloudLibraryFailure.unavailable:
            "the catalog client could not be created"
        default:
            LogFormat.error(error)
        }
    }
}
