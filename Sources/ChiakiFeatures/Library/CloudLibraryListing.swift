import ChiakiModels
import Foundation

/// The cloud library's listing pipeline: the visible games of a snapshot, narrowed by search, filter and
/// platform, ordered by recent play when asked, and cut into pages that keep the visible page in step with
/// every change.
///
/// A game still waiting for its release at ``now`` is listed only under `CloudLibraryFilter.preorders` and
/// by search, so it never shows as playable or buyable before it unlocks. The PS4 and PS5 versions of one game
/// match on their own, and a version that does not lead its pair is left out wherever the leading version
/// matches too, so each game shows once and its detail offers the other version. A trial that has ended is not listed
/// at all; once the store drops it, the game returns as a store game.
public struct CloudLibraryListing: Sendable {
    /// Counts of how often each stage of the pipeline reran, so tests can confirm that unrelated changes skip
    /// work.
    public struct Derivations: Equatable, Sendable {
        /// How often the visible games were listed from the snapshot.
        public var listings = 0
        /// How often the listed games were matched against the search, filter and platform.
        public var matches = 0
        /// How often the visible page was cut from the matches.
        public var pages = 0
    }

    /// The catalog the listing is built from, or `nil` before it loads; setting it relists everything.
    public var snapshot: CloudLibrarySnapshot? {
        didSet {
            list()
        }
    }
    /// The search text; while it is not empty, it matches game names and overrides the filter.
    public var query = "" {
        didSet {
            if query != oldValue {
                match()
            }
        }
    }
    /// The library filter applied when no search is running.
    public var filter = CloudLibraryFilter.all {
        didSet {
            if filter != oldValue {
                match()
            }
        }
    }
    /// The account's recently played games, most recent first, which order the recent filter and supply last
    /// played dates.
    public var recentlyPlayed: [CloudRecentlyPlayed] = [] {
        didSet {
            if recentlyPlayed != oldValue {
                recency = Dictionary(
                    recentlyPlayed.enumerated().map { ($0.element.productId, $0.offset) },
                    uniquingKeysWith: { first, _ in first }
                )
                noteRecentlyPlayed()
                match()
            }
        }
    }
    /// Games the stream service refused to stream, hidden from every filter but the store and from recently played.
    public var unstreamable: Set<String> = [] {
        didSet {
            if unstreamable != oldValue {
                noteRecentlyPlayed()
                match()
            }
        }
    }
    /// Store games whose signed-in store page no longer offers the account a trial, because it has been used;
    /// their Play First Trial offer is dropped from the listed games at once. The core also remembers each one
    /// on disk, so later loads, including after a restart, already list the game without the offer.
    public var trialsWithdrawn: Set<String> = [] {
        didSet {
            if trialsWithdrawn != oldValue {
                list()
            }
        }
    }
    /// The time releases are judged at, ideally the server's; until it is set every scheduled release counts as
    /// still to come.
    public var now = Date.distantPast {
        didSet {
            if now != oldValue {
                notePreorders()
                noteRecentlyPlayed()
                match()
            }
        }
    }
    /// The platform games must be on to be listed.
    public var platform = CloudPlatformFilter.all {
        didSet {
            if platform != oldValue {
                match()
            }
        }
    }
    /// How many games fit on one page of the grid.
    public private(set) var pageSize = CloudGridShape.unmeasured.size
    /// The page shown, kept within the page count as the matches change.
    public private(set) var page = 0
    /// The snapshot's visible games in catalog order.
    public private(set) var listed: [CloudGame] = []
    /// The listed games that pass the search, filter and platform, in display order.
    public private(set) var matching: [CloudGame] = []
    /// The games on the current page.
    public private(set) var visible: [CloudGame] = []
    /// The identifiers of the games on the current page, in order.
    public private(set) var visibleIDs: [String] = []
    /// How often each pipeline stage has run.
    public private(set) var derivations = Derivations()
    private var positions: [String: Int] = [:]
    private var recency: [String: Int] = [:]
    /// Whether any listed game can be shown under the recent filter.
    public private(set) var hasRecentlyPlayed = false
    /// Whether any listed game is still waiting for its release.
    public private(set) var hasPreorders = false

    /// Creates an empty listing with no snapshot.
    public init() {
    }

    /// The number of pages the matches fill, never less than one.
    public var pageCount: Int {
        max(1, (matching.count + pageSize - 1) / pageSize)
    }

    /// The matching games on one page.
    ///
    /// - Parameter wanted: The page number, counted from zero.
    /// - Returns: The page's games, or an empty array when the page is out of range.
    public func games(onPage wanted: Int) -> [CloudGame] {
        let start = wanted * pageSize
        guard wanted >= 0, start < matching.count else {
            return []
        }
        return Array(matching[start..<min(start + pageSize, matching.count)])
    }

    /// Shows a page, clamped to the pages that exist.
    ///
    /// - Parameter wanted: The page to show, counted from zero.
    public mutating func show(page wanted: Int) {
        let target = min(max(0, wanted), pageCount - 1)
        guard target != page else {
            return
        }
        page = target
        slice()
    }

    /// Changes how many games fit on a page, keeping a game on the page shown.
    ///
    /// - Parameters:
    ///   - size: The new page size; ignored unless it is positive and different.
    ///   - id: The game to keep in view, or `nil` to keep the first game of the current page.
    public mutating func resize(to size: Int, keeping id: String?) {
        guard size > 0, size != pageSize else {
            return
        }
        let kept = id.flatMap { id in
            matching.firstIndex { $0.id == id }
        } ?? page * pageSize
        pageSize = size
        page = min(kept / size, pageCount - 1)
        slice()
    }

    /// Finds a listed game by identifier.
    ///
    /// - Parameter id: The game's identifier, or `nil`.
    /// - Returns: The game, or `nil` when it is not listed.
    public func game(_ id: String?) -> CloudGame? {
        guard let id, let position = positions[id] else {
            return nil
        }
        return listed[position]
    }

    private mutating func list() {
        derivations.listings += 1
        listed = snapshot?.games.compactMap { game in
            guard game.visible, !game.trialEnded else {
                return nil
            }
            return trialsWithdrawn.contains(game.id) && game.trialOffer == .playFirstTrial
                ? game.withoutTrialOffer
                : game
        } ?? []
        positions = Dictionary(
            listed.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        trialMarks = CloudTrialMark.byTitle(listed)
        noteRecentlyPlayed()
        notePreorders()
        match()
    }

    /// The trial mark of each listed trial by the title id in its product id, so the console shelf can mark a
    /// recently played trial the same way; worked out whenever the games are listed.
    public private(set) var trialMarks: [String: CloudTrialMark] = [:]

    /// The earliest scheduled release among the listed games that is later than ``now``.
    public var nextUnlock: Date? {
        listed.compactMap { $0.release.unlock(after: now) }.min()
    }

    private mutating func notePreorders() {
        hasPreorders = listed.contains(where: awaitsRelease)
    }

    private func awaitsRelease(_ game: CloudGame) -> Bool {
        game.release.awaitsRelease(at: now)
    }

    private mutating func noteRecentlyPlayed() {
        hasRecentlyPlayed = !recency.isEmpty && listed.contains(where: isRecent)
    }

    private func isRecent(_ game: CloudGame) -> Bool {
        !game.isStoreOnly && !unstreamable.contains(game.id) && recency[game.productId] != nil
            && !awaitsRelease(game)
    }

    private mutating func match() {
        derivations.matches += 1
        let platform = platform
        let query = query
        let searching = !query.isEmpty
        matching = listed.filter { game in
            guard platform.admits(game.platform) else {
                return false
            }
            guard searching else {
                return passes(game)
            }
            return game.name.localizedStandardContains(query)
        }
        let matched = Set(matching.map(\.id))
        matching.removeAll { game in
            guard let other = game.otherVersion, !other.leads else {
                return false
            }
            return matched.contains(other.productId)
        }
        if filter == .recent, !searching {
            matching.sort { (recency[$0.productId] ?? .max) < (recency[$1.productId] ?? .max) }
        }
        page = min(page, pageCount - 1)
        slice()
    }

    private func passes(_ game: CloudGame) -> Bool {
        if filter == .preorders {
            return awaitsRelease(game)
        }
        guard !awaitsRelease(game) else {
            return false
        }
        return switch filter {
        case .all:
            !game.isStoreOnly && !unstreamable.contains(game.id)
        case .recent:
            isRecent(game)
        case .owned:
            game.isOwnedPS5
        case .plus:
            game.isInCatalog
        case .browse:
            game.isStoreOnly
        case .preorders:
            true
        }
    }

    /// When a game was last played, from the account's recently played list.
    ///
    /// - Parameter game: The game to look up.
    /// - Returns: The last played date, or `nil` when the game was not recently played.
    public func lastPlayed(_ game: CloudGame) -> Date? {
        recency[game.productId].map { recentlyPlayed[$0].lastPlayed }
    }

    private mutating func slice() {
        derivations.pages += 1
        visible = games(onPage: page)
        visibleIDs = visible.map(\.id)
    }
}

extension CloudLibraryListing: Equatable {
    /// Compares the inputs of two listings, which decide everything derived from them.
    public static func == (lhs: CloudLibraryListing, rhs: CloudLibraryListing) -> Bool {
        lhs.page == rhs.page && lhs.pageSize == rhs.pageSize && lhs.query == rhs.query && lhs.filter == rhs
            .filter
            && lhs.platform == rhs.platform && lhs.snapshot == rhs.snapshot
            && lhs.recentlyPlayed == rhs.recentlyPlayed
            && lhs.unstreamable == rhs.unstreamable
            && lhs.trialsWithdrawn == rhs.trialsWithdrawn
            && lhs.now == rhs.now
    }
}

extension CloudGame {
    /// The title id inside the product id, such as `PPSA07632_00` in `UP9000-PPSA07632_00-SAROS00000000000`,
    /// or `nil` when the product id is not in that form.
    var productTitleID: String? {
        let parts = productId.split(separator: "-")
        guard parts.count >= 3 else {
            return nil
        }
        return String(parts[1])
    }
}
