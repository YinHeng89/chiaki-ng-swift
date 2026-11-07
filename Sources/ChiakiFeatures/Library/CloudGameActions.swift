import ChiakiModels
import Foundation

/// The actions the game detail offers for one cloud game.
///
/// The card layout, the layered layout and the controller focus order all read this one value, so a button
/// that is shown is always reachable and a notice is shown once.
public struct CloudGameActions: Equatable {
    /// What the play button starts.
    public enum PlayOffer: Equatable {
        /// Runs the launch checks for this request, then plays it.
        case checkAndPlay(CloudLaunchRequest)
        /// Opens the bundle picker so a game inside the bundle can be chosen.
        case chooseGame
    }

    /// The play button of a game that is in the library.
    public struct PlayButton: Equatable {
        /// What the button starts, or `nil` when the game cannot be played from here.
        public let offer: PlayOffer?
        /// Whether the store page check allows playing.
        public let allowed: Bool

        /// Creates a play button.
        ///
        /// - Parameters:
        ///   - offer: What the button starts, or `nil` when the game cannot be played from here.
        ///   - allowed: Whether the store page check allows playing.
        public init(offer: PlayOffer?, allowed: Bool) {
            self.offer = offer
            self.allowed = allowed
        }

        /// Whether the button can be pressed.
        public var isEnabled: Bool {
            offer != nil && allowed
        }

        /// The button's title.
        public var title: LocalizedStringResource {
            offer == .chooseGame
                ? .libraryActionsChooseGame
                : .libraryActionsCheckAndPlay
        }
    }

    /// A button that opens the game's store page.
    public struct StoreLink: Equatable {
        /// The button's title.
        public let title: LocalizedStringResource
        /// The page opened when the account's own store page cannot be resolved.
        public let fallback: URL?

        /// Creates a store link.
        ///
        /// - Parameters:
        ///   - title: The button's title.
        ///   - fallback: The page opened when the account's own store page cannot be resolved.
        public init(title: LocalizedStringResource, fallback: URL?) {
            self.title = title
            self.fallback = fallback
        }
    }

    /// The button that shows the other generation's version of the game, which the library lists under the
    /// version that leads the pair.
    public struct VersionSwitch: Equatable {
        /// The product id of the other version.
        public let productId: String
        /// The button's title, such as `Show PS4 version`.
        public let title: LocalizedStringResource

        /// Creates a version switch to another listed version.
        ///
        /// - Parameter other: The other version of the game.
        public init(to other: CloudGame) {
            productId = other.productId
            title = .libraryActionsShowVersion(platform: other.platform.uppercased())
        }
    }

    /// One control in the detail's focus order, after its Close button.
    public enum Focus: Hashable {
        /// The play button.
        case play
        /// The store page button.
        case store
        /// The store code beside the store button, which opens the same page.
        case purchaseCode
        /// The add to library button.
        case addToLibrary
        /// The refresh button shown after the store page was opened to add the game.
        case refreshTitle
        /// One playable game in the open bundle picker.
        case bundleGame(String)
        /// The button that shows the other generation's version.
        case otherVersion
    }

    /// The play button, or `nil` when the game must be added to the library first or the bundle picker is open.
    public let play: PlayButton?
    /// The bundle's games shown instead of the play button, or `nil` when the picker is closed.
    public let bundleChoices: [CloudBundleChoice]?
    /// The store page button, or `nil` when the game offers none.
    public let store: StoreLink?
    /// The store page opened to add the game to the library, or `nil` when the game cannot be added.
    public let addToLibrary: URL?
    /// The store page a phone scans to buy the game, shown as a code beside its store button, or `nil` when
    /// the game is not for sale here.
    public let purchaseCode: URL?
    /// Whether the refresh button can take focus.
    public let refreshTitleFocusable: Bool
    /// Whether the launch check row and the store page check reason are shown.
    public let showsLaunchChecks: Bool
    /// The button that shows the other generation's version, or `nil` when the library lists none or the
    /// bundle picker is open.
    public let otherVersion: VersionSwitch?

    /// Works out what the detail offers for one game.
    ///
    /// A trial that has ended offers no play button and no launch checks, only its store page, where it can be
    /// bought. The library does not list ended trials, so this only guards a detail opened some other way.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - accountID: The account that would play it, or `nil` when no account is signed in.
    ///   - check: The store page check of the game, if one ran.
    ///   - bundleChoices: The bundle's games when the bundle picker is open for this game; `nil` otherwise.
    ///   - titleRefreshIdle: Whether no title refresh is running or cooling down.
    ///   - mayRefreshTitle: Whether the title refresh is offered for this game yet.
    ///   - otherVersion: The other generation's version the library lists, or `nil` when it lists none.
    public init(
        game: CloudGame,
        accountID: UUID?,
        check: CloudCardCheck?,
        bundleChoices: [CloudBundleChoice]?,
        titleRefreshIdle: Bool,
        mayRefreshTitle: Bool,
        otherVersion: CloudGame? = nil
    ) {
        let storeURL = Self.storeURL(game.conceptUrl)
        self.otherVersion = bundleChoices == nil
            ? otherVersion.map(VersionSwitch.init(to:))
            : nil
        guard !game.trialEnded else {
            self.bundleChoices = nil
            play = nil
            showsLaunchChecks = false
            store = StoreLink(title: .libraryActionsViewInStore, fallback: storeURL)
            addToLibrary = nil
            purchaseCode = Self.code(storeURL)
            refreshTitleFocusable = false
            return
        }
        let inLibrary = !game.needsLibraryAdd
        self.bundleChoices = inLibrary
            ? bundleChoices
            : nil
        play = inLibrary && bundleChoices == nil
            ? PlayButton(
                offer: Self.offer(game, accountID: accountID),
                allowed: !CloudCardCheck.needed(for: game) || check?.allowsPlay == true
            )
            : nil
        showsLaunchChecks = inLibrary
        let showsStorePage = inLibrary && CloudCardCheck.needed(for: game)
            && (game.standing(after: check) == .mayStream || check == .notStreamable || check == .refused)
        if showsStorePage {
            let title: LocalizedStringResource = game.standing(after: check) == .store
                ? .libraryActionsViewInStore
                : .libraryActionsViewStorePage
            store = StoreLink(title: title, fallback: storeURL)
            addToLibrary = nil
            purchaseCode = game.standing(after: check) == .store
                ? Self.code(storeURL)
                : nil
        } else if let storeURL, game.isStoreOnly || !game.canBeAddedToLibrary {
            store = StoreLink(title: .libraryActionsViewInStore, fallback: storeURL)
            addToLibrary = nil
            purchaseCode = Self.code(storeURL)
        } else {
            store = nil
            addToLibrary = storeURL
            purchaseCode = nil
        }
        refreshTitleFocusable = addToLibrary != nil && titleRefreshIdle && mayRefreshTitle
    }

    /// Whether the detail shows a code for the store page: always, since the code is also a control that
    /// opens the page, and on a phone the PlayStation App takes it.
    public static let showsStoreCode = true

    private static func code(_ page: URL?) -> URL? {
        page
    }

    /// Whether the hint about adding the game in the store is shown.
    public var showsLibraryAddHint: Bool {
        addToLibrary != nil
    }

    /// Whether the title refresh notice is shown.
    public var showsTitleNotice: Bool {
        showsLaunchChecks || addToLibrary != nil
    }

    /// The detail's controls in focus order, after its Close button.
    public var focusOrder: [Focus] {
        if let bundleChoices {
            return bundleChoices.filter { $0.refusal == nil }.map { Focus.bundleGame($0.id) }
        }
        var order: [Focus] = []
        if play?.isEnabled == true {
            order.append(.play)
        }
        if store != nil {
            order.append(.store)
            if purchaseCode != nil {
                order.append(.purchaseCode)
            }
        } else if addToLibrary != nil {
            order.append(.addToLibrary)
            if refreshTitleFocusable {
                order.append(.refreshTitle)
            }
        }
        if otherVersion != nil {
            order.append(.otherVersion)
        }
        return order
    }

    /// Validates a store page address from the catalog.
    ///
    /// - Parameter raw: The address the catalog gave.
    /// - Returns: The address when it is a secure PlayStation Store page; `nil` otherwise.
    public static func storeURL(_ raw: String?) -> URL? {
        guard let url = URL.secureArtwork(raw), url.host == "store.playstation.com" else {
            return nil
        }
        return url
    }

    private static func offer(_ game: CloudGame, accountID: UUID?) -> PlayOffer? {
        guard let accountID, !CloudSamplePreorders.isSample(game) else {
            return nil
        }
        if game.opensBundlePicker {
            return .chooseGame
        }
        guard game.launchRefusal == nil, let request = try? CloudLaunchRequest(
            accountID: accountID,
            game: game
        ) else {
            return nil
        }
        return .checkAndPlay(request)
    }
}
