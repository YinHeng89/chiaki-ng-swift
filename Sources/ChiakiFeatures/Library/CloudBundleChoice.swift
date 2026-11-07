import ChiakiModels
import Foundation

/// One game inside a cloud bundle, offered in the bundle picker with the reason it cannot be played when the
/// stream service refuses it.
public struct CloudBundleChoice: Equatable, Identifiable, Sendable {
    /// The game this choice launches, filled from the matching library entry when there is one and from the
    /// bundle otherwise.
    public let game: CloudGame

    /// The game's product identifier, which keeps choices distinct in lists and focus.
    public var id: String {
        game.id
    }

    /// Why the stream service refuses to launch this game, or `nil` when it can be played.
    public var refusal: CloudLaunchRefusal? {
        game.launchRefusal
    }

    /// The player-facing explanation of ``refusal``, or `nil` when the game can be played.
    public var reason: LocalizedStringResource? {
        refusal.map { CloudClearanceRefusalMessage.text(for: CloudClearanceRefusal(refusal: $0)) }
    }

    /// Builds a choice from one entry of a bundle.
    ///
    /// - Parameters:
    ///   - child: The bundle entry this choice stands for.
    ///   - index: The entry's position in the bundle, used to name it when the library has no listing for it.
    ///   - bundle: The bundle the entry belongs to, which supplies artwork, platform and catalog details.
    ///   - listed: The library's own listing of the same game, if any, whose name and artwork take
    ///     precedence.
    public init(_ child: CloudBundledGame, at index: Int, of bundle: CloudGame, listed: CloudGame?) {
        game = CloudGame(
            productId: child.productId,
            name: listed?.name ?? String(localized: .libraryBundleGameNumber(number: String(index + 1))),
            imageUrl: listed?.imageUrl ?? bundle.imageUrl,
            landscapeImageUrl: listed?.landscapeImageUrl ?? bundle.landscapeImageUrl,
            platform: bundle.platform,
            isOwned: child.isOwned,
            plusCatalog: bundle.plusCatalog,
            streamServiceType: bundle.streamServiceType,
            conceptUrl: listed?.conceptUrl ?? bundle.conceptUrl,
            conceptId: listed?.conceptId ?? bundle.conceptId,
            standing: bundle.standing,
            launchRefusal: child.launchRefusal,
            release: bundle.release,
            ownershipId: child.entitlementId
        )
    }
}

extension CloudGame {
    /// Whether playing this game opens the bundle picker rather than launching, because the stream service asks for
    /// a game in the bundle to be chosen.
    public var opensBundlePicker: Bool {
        isBundle && launchRefusal == .chooseAGame
    }

    /// Lists the bundle's games as picker choices, naming each from the library when it lists the same game.
    ///
    /// - Parameter games: The library listing searched for each bundled game's own entry.
    /// - Returns: One choice per bundled game in bundle order, or an empty array when this game is not a
    ///   bundle.
    public func bundleChoices(among games: [CloudGame]) -> [CloudBundleChoice] {
        guard let bundle else {
            return []
        }
        return bundle.games.enumerated().map { index, child in
            CloudBundleChoice(child, at: index, of: self, listed: games.first { listed in
                listed.id != id && listed.describes(child)
            })
        }
    }

    private func describes(_ child: CloudBundledGame) -> Bool {
        productId == child.productId || ownershipId == child.entitlementId
    }
}
