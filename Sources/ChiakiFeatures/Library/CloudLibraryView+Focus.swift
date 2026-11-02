import ChiakiModels
import ComposableArchitecture
import CoreGraphics
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

extension CloudLibraryView {
    /// Focuses a game's card, and again when it appears if it is not on screen yet.
    ///
    /// - Parameter id: The game's identifier.
    func focusGame(_ id: String) {
        pendingGameFocus = id
        focus = .game(id)
    }

    /// Puts controller focus on the first visible card, or the card last focused when it is still shown, while
    /// nothing else holds focus. The search field keeps its keyboard: while it is open the cards are left
    /// alone, and focus settles once it closes.
    func focusFirstVisibleGame() {
        let gameIDs = store.visibleGameIDs
        guard focus == nil, store.selectedGame == nil, !store.isSearching, let first = gameIDs.first else {
            return
        }
        let id = if case .game(let held) = lastFocus, gameIDs.contains(held) {
            held
        } else {
            first
        }
        focus = .game(id)
        navigator?.ensureFocus(
            in: { hostWindow },
            reset: {},
            apply: {
                guard focus == nil, store.selectedGame == nil, !store.isSearching,
                      store.visibleGameIDs.contains(id) else {
                    return
                }
                focus = .game(id)
            }
        )
    }

    /// Moves controller focus from a game's card: to a neighbouring card, across a page, up to the header,
    /// down to the page bar or out of the library.
    ///
    /// - Parameters:
    ///   - id: The game whose card has focus.
    ///   - direction: The direction the controller moved in.
    /// - Returns: `true` when the card was on the page and the move was handled.
    @discardableResult
    func moveGame(_ id: String, direction: MenuMoveDirection) -> Bool {
        let games = store.visibleGames
        guard let index = games.firstIndex(where: { $0.id == id }), let move = CloudGridMove(direction) else {
            return false
        }
        let columns = store.gridShape.columns
        switch store.gridNavigation.stop(from: index, move) {
        case .card(let next):
            focusGame(games[next].id)
        case let .turn(forward, row):
            turnPage(
                forward
                    ? 1
                    : -1,
                row: row
            )
        case .header:
            toolbarReturnGameID = id
            focus = headerGraph.control(above: index, columns: columns)
        case .pageBar:
            guard !layout.isCompact else {
                break
            }
            pageBarReturnIndex = index
            focus = .pageBar
        case .edge:
            store.send(.leaveContent(direction, fromFilter: false))
        case .stay:
            break
        }
        return true
    }

    /// Restores focus after the library becomes interactive: the detail's initial control when a game is
    /// open, otherwise the last focused item or the first card when that game left the page.
    func restoreFocus() {
        Task { @MainActor in
            await Task.yield()
            guard isEnabled else {
                return
            }
            let target: FocusItem?
            if let game = store.selectedGame {
                target = store.detail?.shown(for: game.product) == .loading
                    ? .close
                    : detail(game).detailInitialFocus(game)
            } else if case .game(let id) = lastFocus, !store.visibleGames.contains(where: { $0.id == id }) {
                target = store.visibleGames.first.map {
                    .game($0.id)
                }
            } else {
                target = lastFocus ?? store.visibleGames.first.map {
                    .game($0.id)
                }
            }
            focus = nil
            await Task.yield()
            focus = target
            navigator?.ensureFocus(in: hostWindow) {
                focus = nil
            } apply: {
                focus = target
            }
        }
    }

    /// Keeps focus on the focused game when the listing reorders, turning to the page it moved to, or
    /// focusing the game now in its old position when it dropped out.
    ///
    /// - Parameters:
    ///   - previous: The matching games' identifiers before the change.
    ///   - ids: The matching games' identifiers after the change.
    func followFocusedGame(from previous: [String], to ids: [String]) {
        guard case .game(let id) = focus, store.listing.pageSize > 0, !store.isSearching else {
            return
        }
        if let index = ids.firstIndex(of: id) {
            if !store.visibleGameIDs.contains(id) {
                pendingGameFocus = id
                store.send(.showPage(index / store.listing.pageSize))
            }
            return
        }
        guard let old = previous.firstIndex(of: id), !ids.isEmpty else {
            return
        }
        let index = min(old, ids.count - 1)
        store.send(.showPage(index / store.listing.pageSize))
        focusGame(ids[index])
    }

    /// Remembers the position of the open game when it drops out of the listing, so focus can return there
    /// when the detail closes.
    ///
    /// - Parameters:
    ///   - previous: The matching games' identifiers before the change.
    ///   - ids: The matching games' identifiers after the change.
    func noteOpenedSlot(from previous: [String], to ids: [String]) {
        guard let opened = store.selection, !ids.contains(opened),
              let slot = previous.firstIndex(of: opened) else {
            return
        }
        openedSlot = slot
    }

    /// Returns focus to a game after its detail closes, or to the game now in its old position when it left
    /// the listing, turning to its page when needed. A version the listing shows under its other generation's
    /// version returns focus to that version's card. A request SwiftUI drops while the detail fades out, or
    /// that the detail's removal takes down once it has finished, is applied again.
    ///
    /// - Parameter closed: The game whose detail closed.
    func returnFocus(toGame closed: String) {
        let ids = store.matchingGames.map(\.id)
        let other = store.listing.game(closed)?.otherVersion?.productId
        let previous = !ids.contains(closed) && other.map(ids.contains) == true
            ? other ?? closed
            : closed
        let slot = openedSlot
        openedSlot = nil
        let replacement = slot.flatMap { slot in
            ids.isEmpty
                ? nil
                : ids[min(slot, ids.count - 1)]
        }
        guard let id = ids.contains(previous)
            ? previous
            : replacement ?? store.visibleGameIDs.first else {
            return
        }
        if let index = ids.firstIndex(of: id), store.listing.pageSize > 0,
           !store.visibleGameIDs.contains(id) {
            store.send(.showPage(index / store.listing.pageSize))
        }
        focusGame(id)
        ensureGameFocus(id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(AppMotion.duration(reduced: reduceMotion)))
            ensureGameFocus(id)
        }
    }

    /// Applies focus to a game's card again whenever the window holds no control focus, as when the closing
    /// detail takes it down on its way out.
    ///
    /// - Parameter id: The game whose card takes focus.
    func ensureGameFocus(_ id: String) {
        navigator?.ensureFocus(
            in: { hostWindow },
            reset: {
                focus = nil
            },
            apply: {
                guard store.selectedGame == nil else {
                    return
                }
                focusGame(id)
            }
        )
    }

    /// Installs the handler that swallows activation while the open detail loads, or while its check runs
    /// with focus on Close.
    func registerLoadingActivationHandler() {
        guard loadingActivationHandlerID == nil else {
            return
        }
        loadingActivationHandlerID = navigator?.handlers.registerActivation { window in
            guard window === hostWindow, let game = store.selectedGame else {
                return false
            }
            if store.detail?.shown(for: game.product) == .loading {
                return true
            }
            return store.cardChecks[game.id] == .checking && focus == .close
        }
    }

    /// Removes the activation handler for the loading detail.
    func unregisterLoadingActivationHandler() {
        guard let loadingActivationHandlerID else {
            return
        }
        navigator?.handlers.unregister(loadingActivationHandlerID)
        self.loadingActivationHandlerID = nil
    }

    /// Installs the handler that routes controller focus moves to the detail, the header, the cards or the
    /// page bar, along with the loading activation handler.
    func registerFocusMoveHandler() {
        registerLoadingActivationHandler()
        guard focusMoveHandlerID == nil else {
            return
        }
        focusMoveHandlerID = navigator?.handlers.registerFocusMove { window, direction in
            guard window === hostWindow, !(navigator?.isTrackingMenu ?? false),
                  !(navigator?.inputGate.isBlocking ?? false) else {
                return false
            }
            if let game = store.selectedGame {
                detail(game).moveDetails(game, direction: direction)
                return true
            }
            switch focus {
            case .filter, .refresh, .platform:
                moveHeader(direction)
                return true
            case .search:
                moveHeader(direction)
                return true
            case .game(let id):
                return moveGame(id, direction: direction)
            case .pageBar:
                movePageBar(direction)
                return true
            case .pageNumber:
                return true
            default:
                return false
            }
        }
    }

    /// Removes the focus move handler and the loading activation handler.
    func unregisterFocusMoveHandler() {
        unregisterLoadingActivationHandler()
        guard let focusMoveHandlerID else {
            return
        }
        navigator?.handlers.unregister(focusMoveHandlerID)
        self.focusMoveHandlerID = nil
    }

    /// Moves controller focus among the header controls, down to the games or out of the library.
    ///
    /// - Parameter direction: The direction the controller moved in.
    func moveHeader(_ direction: MenuMoveDirection) {
        guard let current = focus else {
            return
        }
        switch headerGraph.move(from: current, direction) {
        case .focus(let next):
            focus = next
        case .leave(let leaving):
            let fromFilter: Bool =
                if case .filter = current {
                    true
                } else {
                    false
                }
            store.send(.leaveContent(leaving, fromFilter: fromFilter))
        case .gameBelow:
            focusGameBelow(current)
        case .stay:
            break
        }
    }

    /// Where directions move focus among the header controls.
    var headerGraph: CloudLibraryFocusGraph {
        CloudLibraryFocusGraph(
            signedIn: accountID != nil,
            filters: store.filters,
            compact: layout.isCompact,
            filter: store.filter,
            platform: store.platform
        )
    }

    /// The detail panel for a game, sized to the screen cover on compact screens.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The detail wired to the library's store and focus.
    func detail(_ game: CloudGame) -> CloudGameDetail {
        CloudGameDetail(
            game: game, accountID: accountID, height: screenCover?.height ?? height, store: store,
            focus: $focus,
            heldFocus: { lastFocus }
        )
    }

    /// The window's content size when the detail and search cover the whole screen on compact screens, or
    /// `nil` otherwise.
    var screenCover: CGSize? {
        guard layout.isCompact, let size = hostWindow.flatMap({ WindowFocus($0).contentBounds })?.size,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }

    /// Centres a view on the whole window on compact screens, and leaves it in place otherwise.
    ///
    /// - Parameter detail: The view covering the library.
    /// - Returns: The positioned view.
    @ViewBuilder
    func coveringScreen(_ detail: some View) -> some View {
        if let size = screenCover {
            detail
                .frame(width: size.width, height: size.height)
                .position(x: size.width / 2 - origin.x, y: size.height / 2 - origin.y)
        } else {
            detail
        }
    }

    /// Records a focus change: follows a pending game request, remembers the item and tells the page control
    /// whether its number is focused.
    ///
    /// - Parameter item: The newly focused item, or `nil` when focus was lost.
    func focusChanged(_ item: FocusItem?) {
        followPendingGame(item)
        if let item, item != lastFocus {
            store.send(.focusMoved(item))
        }
        guard let item else {
            return
        }
        if item != .pageNumber, item != .pageBar, store.pageControl.typed != nil {
            store.send(.pageControl(.cancel))
        }
        store
            .send(.pageControl(.focus(item == .pageNumber || (item == .pageBar && inputMode == .controller))))
    }

    /// Keeps a requested game card focused: the request ends when the card takes focus and is applied again
    /// when focus is lost before it did.
    ///
    /// - Parameter item: The focus that changed.
    func followPendingGame(_ item: FocusItem?) {
        guard let pendingGameFocus else {
            return
        }
        if item == .game(pendingGameFocus) {
            self.pendingGameFocus = nil
        } else if item == nil, store.selectedGame == nil, isEnabled,
                  store.visibleGames.contains(where: { $0.id == pendingGameFocus }) {
            focus = .game(pendingGameFocus)
        }
    }

    /// Moves focus from a header control down to the card in the matching column, on the row focus left the
    /// grid from.
    ///
    /// - Parameter current: The focused header control.
    func focusGameBelow(_ current: FocusItem) {
        let games = store.visibleGames
        let columnCount = store.gridShape.columns
        guard !games.isEmpty,
              let column = headerGraph.column(
                  below: current,
                  columns: columnCount,
                  center: headerCenters[current],
                  grid: gridWidth > 0
                      ? gridMinX...(gridMinX + gridWidth)
                      : nil
              ) else {
            return
        }
        let previousIndex = toolbarReturnGameID.flatMap { id in
            games.firstIndex { $0.id == id }
        } ?? 0
        let rowStart = previousIndex / columnCount * columnCount
        let target = min(rowStart + column, games.count - 1)
        focusGame(games[target].id)
    }
}

extension CloudLibraryView {
    /// Selects the previous or next library filter, wrapping round, and focuses it.
    ///
    /// - Parameters:
    ///   - step: `-1` for the previous filter and `1` for the next.
    ///   - event: The menu command, ignored unless it came from the library's window while nothing blocks
    ///     input.
    func cycleFilter(by step: Int, from event: MenuCommandEvent) {
        guard isEnabled, let window = event.window, window === hostWindow,
              !(navigator?.inputGate.isBlocking ?? false), !(navigator?.isTrackingMenu ?? false),
              store.selectedGame == nil else {
            return
        }
        let shown = store.filters
        guard !shown.isEmpty else {
            return
        }
        let index = shown.firstIndex(of: store.filter) ?? 0
        let next = shown[(index + step + shown.count) % shown.count]
        store.send(.filter(next))
        focus = .filter(next)
    }
}

/// The matching games' order with the search, filter and platform that produced it, so a reorder can be told
/// apart from a new listing.
struct CloudListingOrder: Equatable {
    /// The filter in effect.
    var filter = CloudLibraryFilter.all
    /// The search text in effect.
    var query = ""
    /// The platform filter in effect.
    var platform = CloudPlatformFilter.all
    /// The matching games' identifiers in display order.
    var ids: [String] = []

    /// Creates an empty order for the default listing.
    init() {
    }

    /// Captures the current listing's order from the library state.
    ///
    /// - Parameter state: The cloud library state.
    init(_ state: CloudLibraryFeature.State) {
        filter = state.filter
        query = state.query
        platform = state.platform
        ids = state.matchingGames.map(\.id)
    }

    /// Whether two orders come from the same search, filter and platform.
    ///
    /// - Parameter other: The order to compare with.
    /// - Returns: `true` when only the order of games can differ.
    func sameListing(as other: Self) -> Bool {
        filter == other.filter && query == other.query && platform == other.platform
    }
}

/// Where a direction moves controller focus among the cloud library's header controls and into its grid.
///
/// The graph is a pure value built from the header the library shows; the cloud library view asks it for
/// each move and applies the answer.
public struct CloudLibraryFocusGraph {
    /// What a move from a header control asks the cloud library to do.
    public enum Move: Equatable {
        /// Focus this header control.
        case focus(CloudLibraryFocus)
        /// Leave the cloud content in this direction.
        case leave(MenuMoveDirection)
        /// Focus the game card below the control.
        case gameBelow
        /// Keep focus where it is.
        case stay
    }

    /// The header controls, in order: the filter chips, search, Refresh when signed in, and the platform chips;
    /// on a compact screen the filter and platform drop-downs, each one stop named by the choice in effect,
    /// then search and Refresh.
    public let headerControls: [CloudLibraryFocus]

    /// Creates the graph for a header.
    ///
    /// - Parameters:
    ///   - signedIn: Whether an account is selected, which adds the Refresh button.
    ///   - filters: The filter chips shown.
    ///   - compact: Whether the header shows drop-downs instead of chips.
    ///   - filter: The filter in effect, the drop-down's stop when compact.
    ///   - platform: The platform in effect, the drop-down's stop when compact.
    public init(
        signedIn: Bool,
        filters: [CloudLibraryFilter],
        compact: Bool = false,
        filter: CloudLibraryFilter = .all,
        platform: CloudPlatformFilter = .all
    ) {
        let refresh: [CloudLibraryFocus] = signedIn
            ? [.refresh]
            : []
        if compact {
            headerControls = [.filter(filter), .platform(platform), .search] + refresh
            return
        }
        headerControls = filters.map(CloudLibraryFocus.filter) + [.search] + refresh
            + CloudPlatformFilter.allCases.map(CloudLibraryFocus.platform)
    }

    /// Moves focus from a header control.
    ///
    /// - Parameters:
    ///   - current: The focused control.
    ///   - direction: The direction pressed.
    /// - Returns: The move to apply.
    public func move(from current: CloudLibraryFocus, _ direction: MenuMoveDirection) -> Move {
        guard let index = headerControls.firstIndex(of: current) else {
            return .stay
        }
        switch direction {
        case .left, .right:
            let next = index + (direction == .left
                ? -1
                : 1)
            return headerControls.indices.contains(next)
                ? .focus(headerControls[next])
                : .leave(direction)
        case .up:
            return .leave(.up)
        case .down:
            return .gameBelow
        }
    }

    /// The header control above a game card, spread across the header by the card's column.
    ///
    /// - Parameters:
    ///   - index: The card's index on the page.
    ///   - columns: The grid's columns.
    /// - Returns: The control to focus.
    public func control(above index: Int, columns: Int) -> CloudLibraryFocus {
        let position = columns <= 1
            ? 0
            : (index % columns) * (headerControls.count - 1) / (columns - 1)
        return headerControls[min(position, headerControls.count - 1)]
    }

    /// The header control nearest a horizontal position.
    ///
    /// - Parameters:
    ///   - midX: The horizontal centre to match.
    ///   - centers: The measured centre of each control.
    /// - Returns: The nearest control, or `nil` until every control is measured.
    public func control(nearest midX: CGFloat, centers: [CloudLibraryFocus: CGFloat]) -> CloudLibraryFocus? {
        guard headerControls.allSatisfy({ centers[$0] != nil }) else {
            return nil
        }
        return headerControls.min { first, second in
            abs(centers[first, default: midX] - midX) < abs(centers[second, default: midX] - midX)
        }
    }

    /// The grid column below a header control.
    ///
    /// - Parameters:
    ///   - current: The focused control.
    ///   - columns: The grid's columns.
    ///   - center: The control's measured horizontal centre, if known.
    ///   - grid: The grid's horizontal extent, if measured.
    /// - Returns: The column, or `nil` when the control is not in the header.
    public func column(below current: CloudLibraryFocus, columns: Int, center: CGFloat?,
                       grid: ClosedRange<CGFloat>?) -> Int? {
        guard let index = headerControls.firstIndex(of: current) else {
            return nil
        }
        if let center, let grid, grid.upperBound > grid.lowerBound {
            let fraction = max(0, min(1, (center - grid.lowerBound) / (grid.upperBound - grid.lowerBound)))
            return min(columns - 1, Int(fraction * CGFloat(columns)))
        }
        return headerControls.count == 1
            ? 0
            : index * (columns - 1) / (headerControls.count - 1)
    }
}
