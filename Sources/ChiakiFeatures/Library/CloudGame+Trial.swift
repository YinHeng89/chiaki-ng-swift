import ChiakiModels
import Foundation

/// How a held trial is marked on a card: its icon and its words, such as the hourglass and Trial.
public struct CloudTrialMark: Equatable, Sendable {
    /// The trial's icon.
    public let icon: AppIcon
    /// The trial's words.
    public let label: LocalizedStringResource

    /// The marks of the held trials among some games, by the title id in each product id, which is how the
    /// console shelf names its titles.
    ///
    /// - Parameter games: The games.
    /// - Returns: The mark of each held trial whose product id names a title id; the first game wins a
    ///   repeated title id.
    static func byTitle(_ games: [CloudGame]) -> [String: CloudTrialMark] {
        Dictionary(
            games.compactMap { game in
                game.productTitleID.flatMap { id in
                    game.trialMark.map { (id, $0) }
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

extension CloudGame {
    /// The words a card shows for a trial: "Demo" when the store's own name for an ordinary trial calls it a demo,
    /// "Trial" for every other trial, including every Play First Trial, and `nil` for a game the account does
    /// not hold as a trial.
    ///
    /// The store gives no way to tell an untimed demo from a timed game trial, so only its name decides Demo.
    var trialLabel: LocalizedStringResource? {
        guard isTrial else {
            return nil
        }
        return isNamedDemo
            ? .libraryTrialDemo
            : .libraryTrialTrial
    }

    /// The icon a card shows for a trial: ``AppIcon/demo`` for a trial the store names a demo and ``AppIcon/trial``
    /// for every other trial, and `nil` for a game the account does not hold as a trial.
    var trialIcon: AppIcon? {
        guard isTrial else {
            return nil
        }
        return isNamedDemo
            ? .demo
            : .trial
    }

    /// The words a store card shows for a trial version the store offers: "Trial available" for a Play First
    /// Trial, which the account may already have used, "Demo available" for an ordinary trial, and `nil` when
    /// the store offers none the account lacks.
    var trialOfferLabel: LocalizedStringResource? {
        switch trialOffer {
        case .playFirstTrial:
            .libraryTrialTrialAvailable
        case .demo:
            .libraryTrialDemoAvailable
        case nil:
            nil
        }
    }

    /// The icon a store card shows for a trial version the store offers: ``AppIcon/trial`` for a Play First
    /// Trial, ``AppIcon/demo`` for an ordinary trial, and `nil` when the store offers none the account lacks.
    var trialOfferIcon: AppIcon? {
        switch trialOffer {
        case .playFirstTrial:
            .trial
        case .demo:
            .demo
        case nil:
            nil
        }
    }

    /// The icon and words a card shows for a held trial, or `nil` for a game the account does not hold as a
    /// trial.
    var trialMark: CloudTrialMark? {
        guard let trialIcon, let trialLabel else {
            return nil
        }
        return CloudTrialMark(icon: trialIcon, label: trialLabel)
    }

    private var isNamedDemo: Bool {
        !isPlayFirstTrial && name.split(whereSeparator: { !$0.isLetter }).contains {
            $0.localizedCaseInsensitiveCompare("demo") == .orderedSame
        }
    }
}
