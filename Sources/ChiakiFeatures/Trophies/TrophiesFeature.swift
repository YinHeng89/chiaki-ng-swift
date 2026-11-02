import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import MenuFocus

/// The library's Trophies section: the account's trophy level and earned trophies, the games it has trophies in,
/// and one game's groups and trophies.
///
/// The overview and an opened game each load through their own small state machine, and every answer carries the
/// operation that asked for it, so an answer for an older account, an older request or a game closed meanwhile is
/// dropped. The core keeps answers for hours and paces requests, so showing the section again is cheap; Refresh
/// forgets what is kept and asks PSN again.
@Reducer public struct TrophiesFeature {
    /// The account's level and games.
    public struct Overview: Equatable, Sendable {
        /// The trophy level and earned trophies, or `nil` when PSN did not give them.
        public var summary: TrophySummary?
        /// The games with trophies, most recently updated first.
        public var titles: [TrophyTitle]

        /// Describes an overview.
        ///
        /// - Parameters:
        ///   - summary: The trophy level.
        ///   - titles: The games with trophies.
        public init(summary: TrophySummary?, titles: [TrophyTitle]) {
            self.summary = summary
            self.titles = titles
        }
    }

    /// Where the overview stands.
    public enum Listing: Equatable, Sendable {
        /// Nothing has been asked yet.
        case idle
        /// The operation with this id is asking, showing the overview read before meanwhile.
        case loading(UUID, kept: Overview?)
        /// PSN answered.
        case loaded(Overview)
        /// The overview could not be read.
        case failed(PSNTrophiesFailure)
    }

    /// Where an opened game's trophies stand.
    public enum TitleListing: Equatable, Sendable {
        /// The operation with this id is reading the game's trophies.
        case loading(UUID)
        /// PSN answered with these groups and trophies.
        case loaded(TitleTrophies)
        /// The game's trophies could not be read.
        case failed(PSNTrophiesFailure)
    }

    /// A game opened from the list.
    public struct Opened: Equatable, Sendable {
        /// The game.
        public var title: TrophyTitle
        /// Where its trophies stand.
        public var listing: TitleListing
        /// The group shown, or `nil` for every group.
        public var group: String?
        /// The hidden trophies the player chose to reveal.
        public var revealed: Set<Int> = []

        /// The trophies of the shown group, in list order.
        public var shown: [PSNTrophy] {
            guard case .loaded(let trophies) = listing else {
                return []
            }
            guard let group else {
                return trophies.trophies
            }
            return trophies.trophies.filter {
                $0.group == group
            }
        }

        /// The game's groups, when it has more than the base game.
        public var groups: [TrophyGroup] {
            guard case .loaded(let trophies) = listing, trophies.groups.count > 1 else {
                return []
            }
            return trophies.groups
        }
    }

    /// The section's state.
    @ObservableState public struct State: Equatable {
        /// The profile whose trophies are shown, or `nil` while the section is not shown.
        public var profile: ProfileID?
        /// Where the overview stands.
        public var listing = Listing.idle
        /// The game opened from the list.
        public var opened: Opened?
        /// A focus hand-off from the library into the section, waiting for the view to apply it.
        public var contentFocus: LibraryContentFocus?
        /// Which games the list shows.
        public var titleFilter = TrophyTitleFilter.all
        /// The order of the games.
        public var titleSort = TrophyTitleSort.recent
        /// Whether the games run in their sort's order or the other way round.
        public var titleSortDirection = TrophySortDirection.standard
        /// Text a game's name must contain to be listed.
        public var query = ""
        /// Whether the search pop-up is open over the games on a compact screen.
        public var isSearching = false
        /// Which of the opened game's trophies are shown.
        public var trophyFilter = TrophyFilter.all
        /// The order of the opened game's trophies.
        public var trophySort = TrophySort.game
        /// Whether the trophies run in their sort's order or the other way round.
        public var trophySortDirection = TrophySortDirection.standard

        /// Creates an empty section.
        public init() {
        }

        /// The overview shown, which stays while it is read again.
        public var overview: Overview? {
            switch listing {
            case .loaded(let overview):
                overview
            case .loading(_, let kept):
                kept
            case .idle, .failed:
                nil
            }
        }

        /// The games listed, filtered, searched and sorted as chosen.
        public var shownTitles: [TrophyTitle] {
            TrophyArrangement.titles(
                overview?.titles ?? [],
                filter: titleFilter,
                sort: titleSort,
                query: query,
                direction: titleSortDirection
            )
        }

        /// The opened game's trophies of the chosen group, filtered and sorted as chosen.
        public var shownTrophies: [PSNTrophy] {
            TrophyArrangement.trophies(
                opened?.shown ?? [],
                filter: trophyFilter,
                sort: trophySort,
                direction: trophySortDirection
            )
        }

        /// Whether the overview is being read.
        public var isLoading: Bool {
            guard case .loading = listing else {
                return false
            }
            return true
        }
    }

    /// What the section can do.
    public enum Action: Equatable, Sendable {
        /// The section is shown for a profile, or hidden with `nil`.
        case show(ProfileID?)
        /// The player asked to read everything again.
        case refresh
        /// The overview read by an operation finished.
        case overviewLoaded(UUID, Result<Overview, PSNTrophiesFailure>)
        /// The player opened a game.
        case open(String)
        /// The game's trophies read by an operation finished.
        case titleLoaded(UUID, Result<TitleTrophies, PSNTrophiesFailure>)
        /// The player chose a group, or `nil` for every group.
        case groupSelected(String?)
        /// The player revealed or hid a hidden trophy's name and description.
        case revealToggled(Int)
        /// The player chose which games the list shows.
        case titleFilterChosen(TrophyTitleFilter)
        /// The player chose the order of the games; choosing the order in effect again reverses it.
        case titleSortChosen(TrophyTitleSort)
        /// The player changed the text games are searched for.
        case queryChanged(String)
        /// The player opened the search pop-up.
        case searchOpened
        /// The player closed the search pop-up; the text searched for stays in effect.
        case searchClosed
        /// The player chose which of the opened game's trophies are shown.
        case trophyFilterChosen(TrophyFilter)
        /// The player chose the order of the opened game's trophies; choosing the order in effect again
        /// reverses it.
        case trophySortChosen(TrophySort)
        /// The player closed the opened game.
        case close
        /// The library asked focus to enter the section.
        case focusRequested(LibraryContentFocus)
        /// The view applied the focus hand-off.
        case contentFocusHandled
        /// Focus left the section's content in a direction.
        case leaveContent(MenuMoveDirection)
        /// Back asked to return to the rail.
        case backToRail
        /// Requests for the library.
        case delegate(Delegate)
    }

    /// Requests for the library.
    public enum Delegate: Equatable, Sendable {
        /// Focus left the content in this direction.
        case leftContent(MenuMoveDirection)
        /// Back asked for the rail.
        case backToRail
    }

    /// Cancellation identifiers for the section's reads.
    public enum CancelID: Sendable {
        /// The overview read.
        case overview
        /// The opened game's read.
        case title
    }

    /// Reads trophies through PSN.
    @Dependency(\.psnTrophies) var client
    /// Generates operation identifiers.
    @Dependency(\.uuid) var uuid

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .show(let profile):
                return show(profile, state: &state)
            case .refresh:
                guard let profile = state.profile else {
                    return .none
                }
                state.opened = nil
                return .concatenate(
                    .cancel(id: CancelID.title),
                    .run { [client] _ in
                        await client.startOver(profile)
                    },
                    load(&state)
                )
            case let .overviewLoaded(operation, result):
                guard case .loading(operation, _) = state.listing else {
                    return .none
                }
                switch result {
                case .success(let overview):
                    state.listing = .loaded(overview)
                case .failure(let failure):
                    state.listing = .failed(failure)
                }
                return .none
            case .open(let id):
                return open(id, state: &state)
            case let .titleLoaded(operation, result):
                guard case .loading(operation) = state.opened?.listing else {
                    return .none
                }
                switch result {
                case .success(let trophies):
                    state.opened?.listing = .loaded(trophies)
                case .failure(let failure):
                    state.opened?.listing = .failed(failure)
                }
                return .none
            case .groupSelected(let group):
                state.opened?.group = group
                return .none
            case .revealToggled(let trophy):
                guard var opened = state.opened else {
                    return .none
                }
                if opened.revealed.contains(trophy) {
                    opened.revealed.remove(trophy)
                } else {
                    opened.revealed.insert(trophy)
                }
                state.opened = opened
                return .none
            case .titleFilterChosen(let filter):
                state.titleFilter = filter
                return .none
            case .titleSortChosen(let sort):
                state.titleSortDirection = sort == state.titleSort
                    ? state.titleSortDirection.flipped
                    : .standard
                state.titleSort = sort
                return .none
            case .queryChanged(let query):
                state.query = query
                return .none
            case .searchOpened:
                state.isSearching = true
                return .none
            case .searchClosed:
                state.isSearching = false
                return .none
            case .trophyFilterChosen(let filter):
                state.trophyFilter = filter
                return .none
            case .trophySortChosen(let sort):
                state.trophySortDirection = sort == state.trophySort
                    ? state.trophySortDirection.flipped
                    : .standard
                state.trophySort = sort
                return .none
            case .close:
                state.opened = nil
                return .cancel(id: CancelID.title)
            case .focusRequested(let request):
                state.contentFocus = request
                return .none
            case .contentFocusHandled:
                state.contentFocus = nil
                return .none
            case .leaveContent(let direction):
                return .send(.delegate(.leftContent(direction)))
            case .backToRail:
                return .send(.delegate(.backToRail))
            case .delegate:
                return .none
            }
        }
    }

    private func show(_ profile: ProfileID?, state: inout State) -> Effect<Action> {
        guard profile != state.profile else {
            return .none
        }
        let changed = state.profile != nil && profile != nil
        state.profile = profile
        guard profile != nil else {
            if case .loading(_, let kept) = state.listing {
                state.listing = kept.map(Listing.loaded) ?? .idle
            }
            return .merge(.cancel(id: CancelID.overview), .cancel(id: CancelID.title))
        }
        if changed || state.listing == .idle {
            state.listing = .idle
            state.opened = nil
        }
        return .merge(.cancel(id: CancelID.title), load(&state))
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard let profile = state.profile else {
            return .none
        }
        let operation = uuid()
        state.listing = .loading(operation, kept: state.overview)
        return .run { [client] send in
            do throws(PSNTrophiesFailure) {
                let titles = try await client.titles(profile)
                let summary: TrophySummary?
                do throws(PSNTrophiesFailure) {
                    summary = try await client.summary(profile)
                } catch .cancelled {
                    throw .cancelled
                } catch {
                    summary = nil
                }
                await send(.overviewLoaded(operation, .success(Overview(summary: summary, titles: titles))))
            } catch {
                await send(.overviewLoaded(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.overview, cancelInFlight: true)
    }

    private func open(_ id: String, state: inout State) -> Effect<Action> {
        guard let profile = state.profile,
              let title = state.overview?.titles.first(where: { $0.id == id }) else {
            return .none
        }
        let operation = uuid()
        state.opened = Opened(title: title, listing: .loading(operation))
        return .run { [client] send in
            do throws(PSNTrophiesFailure) {
                let trophies = try await client.trophies(profile, id)
                await send(.titleLoaded(operation, .success(trophies)))
            } catch {
                await send(.titleLoaded(operation, .failure(error)))
            }
        }
        .cancellable(id: CancelID.title, cancelInFlight: true)
    }
}
