import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The library's Trophies section: the account's level and earned trophies above the games it has trophies in,
/// and, once a game is opened, that game's groups and trophies in place of the list.
///
/// Refresh sits in the heading row and every game or trophy is a row of its own. Both lists build their rows
/// lazily, so a move to a row not built yet first scrolls it into place and then gives it focus. Focus enters on
/// the stop it last held, or on the first game; moving past the content's edge is reported to the store, which
/// hands it to the library's rail or header. Back closes an opened game with focus on its row, and from the list
/// returns to the rail, or offers to quit when there is none.
struct TrophiesView: View {
    /// A focus stop of the section.
    enum Focus: Hashable {
        /// The Refresh button.
        case refresh
        /// The game with this trophy set id.
        case title(String)
        /// The opened game's Back button.
        case back
        /// The opened game's choice of every group.
        case allGroups
        /// The opened game's group with this id.
        case group(String)
        /// The opened game's trophy with this number.
        case trophy(Int)
        /// The choice of which games the list shows.
        case titleFilter(TrophyTitleFilter)
        /// The choice of the games' order.
        case titleSort(TrophyTitleSort)
        /// The search field above the games.
        case search
        /// The choice of which of the opened game's trophies are shown.
        case trophyFilter(TrophyFilter)
        /// The choice of the opened game's trophy order.
        case trophySort(TrophySort)
    }

    /// The section.
    @Bindable var store: StoreOf<TrophiesFeature>
    @MenuFocusState private var focus: Focus?
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.requestQuit) private var requestQuit
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    @Environment(\.libraryRailShown) private var libraryRailShown
    @State private var hostWindow: PlatformWindow?
    @State private var lastFocus: Focus?
    @State private var focusedWhenDisabled = false
    @State private var landsOnFirstTrophy = false
    @State private var revealTarget: Focus?
    @State private var origin = CGPoint.zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
            if store.isSearching {
                coveringScreen(SearchOverlay(
                    prompt: "Search games",
                    query: Binding {
                        store.query
                    } set: { query in
                        store.send(.queryChanged(query))
                    },
                    identifier: "trophies-search-overlay"
                ) {
                    closeSearch()
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGPoint.self) { geometry in
            geometry.frame(in: .global).origin
        } action: { point in
            origin = point
        }
        .preference(key: LibraryCoverKey.self, value: screenCover != nil && store.isSearching)
        .animation(AppMotion.animation(reduced: reduceMotion), value: store.isSearching)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: layout.isCompact
            ? 10
            : 24) {
                if let opened = store.opened {
                    TrophyTitleDetail(
                        opened: opened,
                        trophies: store.shownTrophies,
                        filter: store.trophyFilter,
                        sort: store.trophySort,
                        sortDirection: store.trophySortDirection,
                        focus: $focus,
                        revealTarget: revealTarget,
                        move: move,
                        close: close,
                        select: { group in
                            store.send(.groupSelected(group))
                        },
                        reveal: { trophy in
                            store.send(.revealToggled(trophy))
                        },
                        chooseFilter: { filter in
                            store.send(.trophyFilterChosen(filter))
                        },
                        chooseSort: { sort in
                            store.send(.trophySortChosen(sort))
                        }
                    )
                    .transition(.opacity)
                } else {
                    overview
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .tint(Palette.accent)
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.opened?.title.id)
            .background(WindowAccessor { hostWindow = $0 })
            .onChange(of: store.contentFocus, initial: true) { _, request in
                enterContent(request)
            }
            .onChange(of: hostWindow) { _, _ in
                enterContent(store.contentFocus)
            }
            .onChange(of: focus) { _, focused in
                if let focused {
                    lastFocus = focused
                    if focused != .back {
                        landsOnFirstTrophy = false
                    }
                }
            }
            .onChange(of: store.shownTrophies.first?.id) { _, first in
                guard landsOnFirstTrophy, focus == .back || focus == nil, let first else {
                    return
                }
                landsOnFirstTrophy = false
                land(on: .trophy(first))
            }
            .onChange(of: isEnabled) { _, enabled in
                guard enabled else {
                    focusedWhenDisabled = focus != nil
                    return
                }
                guard focusedWhenDisabled else {
                    return
                }
                focusedWhenDisabled = false
                Task { @MainActor in
                    await Task.yield()
                    focus = intendedFocus
                    ensureFocus()
                }
            }
            .onChange(of: store.shownTitles.first?.id) { _, first in
                guard focus == .refresh, let first else {
                    return
                }
                land(on: .title(first))
            }
            .onMenuCommand([.alternate]) { event in
                jumpToChoices(from: event)
            }
            .onMenuCommand([.previous]) { event in
                cycleFilter(by: -1, from: event)
            }
            .onMenuCommand([.next]) { event in
                cycleFilter(by: 1, from: event)
            }
            .menuHandlers(enabled: isEnabled, move: { window, direction in
                guard window === hostWindow, !(navigator?.inputGate.isBlocking ?? false),
                      !(navigator?.isTrackingMenu ?? false), let current = focus else {
                    return false
                }
                move(from: current, direction)
                return true
            }, back: { window in
                back(in: window)
            })
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: layout.isCompact
            ? 10
            : 20) {
                if layout.isCompact {
                    compactControls
                } else {
                    heading
                }
                if !layout.isShort {
                    summary
                }
                if arranged, !layout.isCompact {
                    arrangement
                }
                titles
            }
    }

    private var arranged: Bool {
        !(store.overview?.titles.isEmpty ?? true)
    }

    private var compactControls: some View {
        ViewThatFits(in: .horizontal) {
            compactControlRow
            ScrollView(.horizontal, showsIndicators: false) {
                compactControlRow
            }
        }
    }

    private var compactControlRow: some View {
        HStack(spacing: layout.controlSpacing) {
            refresh
                .labelStyle(.iconOnly)
            if arranged {
                ChoiceDropdown(
                    title: "Show",
                    choices: TrophyTitleFilter.allCases,
                    chosen: store.titleFilter,
                    label: \.name,
                    stop: Focus.titleFilter,
                    focus: $focus,
                    move: move
                ) { filter in
                    store.send(.titleFilterChosen(filter))
                }
                ChoiceDropdown(
                    title: "Sort",
                    choices: TrophyTitleSort.allCases,
                    chosen: store.titleSort,
                    label: \.name,
                    stop: Focus.titleSort,
                    focus: $focus,
                    move: move,
                    direction: store.titleSortDirection
                ) { sort in
                    store.send(.titleSortChosen(sort))
                }
                Spacer(minLength: 0)
                searchButton
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var searchButton: some View {
        FocusButton {
            store.send(.searchOpened)
        } label: {
            Label("Search games", systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(store.query.isEmpty
                    ? .white
                    : Palette.accent)
                    .frame(width: 24, height: 24)
        }
        .glassControlStyle()
        .focusBorderShape(.circle)
        .overlay {
            if !store.query.isEmpty {
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityValue(store.query.isEmpty
            ? ""
            : "Searching for \(store.query)")
            .menuFocused($focus, equals: .search)
            .environment(\.menuMove) { direction in
                move(from: .search, direction)
            }
    }

    @ViewBuilder private var summary: some View {
        if let summary = store.overview?.summary {
            TrophySummaryCard(summary: summary)
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 20) {
            Text("Trophies").font(.system(size: 40, weight: .semibold))
            refresh
            Spacer(minLength: 0)
            TrophyChoicesHint()
            LibraryMenuHint(section: .trophies)
        }
    }

    private var refresh: some View {
        FocusButton {
            guard !store.isLoading else {
                return
            }
            store.send(.refresh)
        } label: {
            Label("Refresh", systemImage: AppIcon.refreshDetails.rawValue)
                .font(.callout.weight(.medium))
                .opacity(store.isLoading
                    ? 0.5
                    : 1)
        }
        .glassControlStyle()
        .focusBorderShape(.capsule)
        .accessibilityValue(refreshState)
        .menuFocused($focus, equals: .refresh)
        .environment(\.menuMove) { direction in
            move(from: .refresh, direction)
        }
    }

    private var refreshState: String {
        store.isLoading
            ? "Loading"
            : ""
    }

    private var arrangement: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                TrophyChoiceChips(
                    title: "Show games",
                    choices: TrophyTitleFilter.allCases,
                    chosen: store.titleFilter,
                    label: \.name,
                    stop: Focus.titleFilter,
                    focus: $focus,
                    move: move
                ) { filter in
                    store.send(.titleFilterChosen(filter))
                }
                TrophyChoiceChips(
                    title: "Sort games by",
                    choices: TrophyTitleSort.allCases,
                    chosen: store.titleSort,
                    label: \.name,
                    stop: Focus.titleSort,
                    focus: $focus,
                    move: move,
                    direction: store.titleSortDirection
                ) { sort in
                    store.send(.titleSortChosen(sort))
                }
                TrophySearchField(
                    prompt: "Search games",
                    query: Binding {
                        store.query
                    } set: { query in
                        store.send(.queryChanged(query))
                    },
                    focus: $focus,
                    stop: .search,
                    move: move
                )
            }
            .padding(4)
        }
        .padding(.horizontal, -4)
    }

    @ViewBuilder private var titles: some View {
        let titles = store.shownTitles
        if titles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if layout.isShort {
                    summary
                }
                Text(emptyText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if layout.isShort {
                            summary
                                .padding(.bottom, 2)
                        }
                        ForEach(titles) { title in
                            row(title).id(Focus.title(title.id))
                        }
                    }
                    .padding(8)
                }
                .selfManagedFocusScrolling()
                .onChange(of: revealTarget, initial: true) { _, target in
                    guard let target, case .title = target else {
                        return
                    }
                    proxy.scrollTo(target)
                }
                .onChange(of: focus) { _, focused in
                    guard let focused, case .title = focused else {
                        return
                    }
                    withAnimation(reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo(focused)
                        }
                }
            }
        }
    }

    private var emptyText: String {
        if !(store.overview?.titles.isEmpty ?? true) {
            return "No games match these choices."
        }
        return switch store.listing {
        case .idle, .loading:
            "Loading trophies"
        case .failed(let failure):
            Self.readFailure(failure)
        case .loaded:
            "No trophies yet. Trophies you earn in games show up here."
        }
    }

    private func row(_ title: TrophyTitle) -> some View {
        let stop = Focus.title(title.id)
        return FocusButton {
            store.send(.open(title.id))
            landsOnFirstTrophy = true
            land(on: openedFocus)
        } label: {
            TrophyTitleRow(title: title)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(.roundedRectangle(14))
        .menuFocused($focus, equals: stop)
        .environment(\.menuMove) { direction in
            move(from: stop, direction)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the game's trophies")
    }

    /// The overview's stops, row by row: Refresh, the filter, sort and search controls when there are games, then
    /// each game shown.
    ///
    /// On a compact screen the controls share Refresh's row, the filter and sort each as one drop-down whose stop
    /// is the choice in effect; otherwise every chip is a stop on a row of its own.
    ///
    /// - Parameters:
    ///   - titles: The games shown.
    ///   - arranged: Whether the filter, sort and search controls are shown.
    ///   - compact: Whether the screen is compact.
    ///   - filter: The filter in effect.
    ///   - sort: The sort in effect.
    /// - Returns: The rows.
    static func rows(
        for titles: [TrophyTitle],
        arranged: Bool,
        compact: Bool,
        filter: TrophyTitleFilter,
        sort: TrophyTitleSort
    ) -> [[Focus]] {
        let games = titles.map {
            [Focus.title($0.id)]
        }
        if compact {
            let controls: [Focus] = arranged
                ? [.titleFilter(filter), .titleSort(sort), .search]
                : []
            return [[.refresh] + controls] + games
        }
        let controls: [[Focus]] = arranged
            ? [
                TrophyTitleFilter.allCases.map(Focus.titleFilter) + TrophyTitleSort.allCases
                    .map(Focus.titleSort)
                    + [.search]
            ]
            : []
        return [[.refresh]] + controls + games
    }

    /// An opened game's stops, row by row: Back and the group choices, the filter and sort choices, then each
    /// trophy shown.
    ///
    /// On a compact screen the filter and sort are each one drop-down whose stop is the choice in effect;
    /// otherwise every chip is a stop.
    ///
    /// - Parameters:
    ///   - opened: The opened game.
    ///   - trophies: The trophies shown.
    ///   - compact: Whether the screen is compact.
    ///   - filter: The filter in effect.
    ///   - sort: The sort in effect.
    /// - Returns: The rows.
    static func rows(
        for opened: TrophiesFeature.Opened,
        trophies: [PSNTrophy],
        compact: Bool,
        filter: TrophyFilter,
        sort: TrophySort
    ) -> [[Focus]] {
        let groups: [Focus] = opened.groups.isEmpty
            ? []
            : [.allGroups] + opened.groups.map {
                .group($0.id)
            }
        let controls: [Focus] = compact
            ? [.trophyFilter(filter), .trophySort(sort)]
            : TrophyFilter.allCases.map(Focus.trophyFilter) + TrophySort.allCases.map(Focus.trophySort)
        return [[.back] + groups, controls] + trophies.map {
            [.trophy($0.id)]
        }
    }

    private var rows: [[Focus]] {
        if let opened = store.opened {
            return Self.rows(
                for: opened,
                trophies: store.shownTrophies,
                compact: layout.isCompact,
                filter: store.trophyFilter,
                sort: store.trophySort
            )
        }
        return Self.rows(
            for: store.shownTitles,
            arranged: arranged,
            compact: layout.isCompact,
            filter: store.titleFilter,
            sort: store.titleSort
        )
    }

    /// The window's content size when the search covers the whole screen on compact screens, or `nil` otherwise.
    private var screenCover: CGSize? {
        guard layout.isCompact, let size = hostWindow.flatMap({ WindowFocus($0).contentBounds })?.size,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }

    @ViewBuilder private func coveringScreen(_ overlay: some View) -> some View {
        if let size = screenCover {
            overlay
                .frame(width: size.width, height: size.height)
                .position(x: size.width / 2 - origin.x, y: size.height / 2 - origin.y)
        } else {
            overlay
        }
    }

    private func closeSearch() {
        store.send(.searchClosed)
        Task { @MainActor in
            await Task.yield()
            focus = .search
            ensureFocus()
        }
    }

    private func move(from current: Focus, _ direction: MenuMoveDirection) {
        guard rows.joined().contains(current) else {
            land(on: intendedFocus)
            return
        }
        if let next = FocusRows.move(from: current, in: rows, direction) {
            reveal(next)
            return
        }
        store.send(.leaveContent(direction))
    }

    private func reveal(_ target: Focus) {
        switch target {
        case .title, .trophy:
            land(on: target)
        case .refresh, .back, .allGroups, .group, .titleFilter, .titleSort, .search, .trophyFilter,
             .trophySort:
            focus = target
        }
    }

    private func close() {
        let opened = store.opened?.title.id
        store.send(.close)
        guard let opened else {
            return
        }
        land(on: .title(opened))
    }

    private func land(on target: Focus) {
        lastFocus = target
        revealTarget = target
        focus = target
        FocusRestore.settle(target) {
            focus
        } write: { stop in
            focus = stop
        }
        ensureFocus()
    }

    private func ensureFocus() {
        navigator?.ensureFocus(
            in: { hostWindow },
            reset: {
                focus = nil
            },
            apply: {
                focus = intendedFocus
            }
        )
    }

    private var intendedFocus: Focus {
        lastFocus.flatMap {
            rows.joined().contains($0)
                ? $0
                : nil
        } ?? initialFocus
    }

    /// Moves focus to the filter in effect, as the west button does, so the filters, sorts and search are one
    /// press away from anywhere in a long list: the trophy filters inside an opened game, the game filters
    /// otherwise.
    ///
    /// - Parameter event: The command's event, which names its window.
    private func jumpToChoices(from event: MenuCommandEvent) {
        guard isEnabled, !store.isSearching, let window = event.window, window === hostWindow,
              !(navigator?.inputGate.isBlocking ?? false), !(navigator?.isTrackingMenu ?? false) else {
            return
        }
        land(on: store.opened == nil
            ? .titleFilter(store.titleFilter)
            : .trophyFilter(store.trophyFilter))
    }

    /// Selects the previous or next filter, as L1 and R1 do, wrapping at both ends, and focuses its chip: the
    /// trophy filters inside an opened game, the game filters otherwise.
    ///
    /// - Parameters:
    ///   - step: -1 for the previous filter, 1 for the next.
    ///   - event: The command's event, which names its window.
    private func cycleFilter(by step: Int, from event: MenuCommandEvent) {
        guard isEnabled, !store.isSearching, let window = event.window, window === hostWindow,
              !(navigator?.inputGate.isBlocking ?? false), !(navigator?.isTrackingMenu ?? false) else {
            return
        }
        if store.opened != nil {
            let next = Self.stepped(store.trophyFilter, by: step)
            store.send(.trophyFilterChosen(next))
            focus = .trophyFilter(next)
        } else {
            let next = Self.stepped(store.titleFilter, by: step)
            store.send(.titleFilterChosen(next))
            focus = .titleFilter(next)
        }
    }

    private static func stepped<Value: CaseIterable & Equatable>(_ value: Value, by step: Int) -> Value
        where Value.AllCases: RandomAccessCollection, Value.AllCases.Index == Int {
        let all = Value.allCases
        let index = all.firstIndex(of: value) ?? all.startIndex
        return all[(index + step + all.count) % all.count]
    }

    private func back(in window: PlatformWindow) -> Bool {
        guard window === hostWindow else {
            return false
        }
        if store.isSearching {
            closeSearch()
            return true
        }
        guard focus != nil else {
            return false
        }
        if store.opened != nil {
            close()
            return true
        }
        guard QuitBack.available(in: window, navigator: navigator) else {
            return false
        }
        if libraryRailShown {
            store.send(.backToRail)
        } else {
            requestQuit(.screen)
        }
        return true
    }

    private func enterContent(_ request: LibraryContentFocus?) {
        guard request != nil, isEnabled, hostWindow != nil else {
            return
        }
        store.send(.contentFocusHandled)
        Task { @MainActor in
            await Task.yield()
            focus = nil
            revealTarget = intendedFocus
            await Task.yield()
            focus = intendedFocus
            ensureFocus()
        }
    }

    private var openedFocus: Focus {
        store.shownTrophies.first.map {
            .trophy($0.id)
        } ?? .back
    }

    private var initialFocus: Focus {
        if store.opened != nil {
            return openedFocus
        }
        return store.shownTitles.first.map {
            .title($0.id)
        } ?? .refresh
    }

    /// The sentence shown when trophies could not be read.
    ///
    /// - Parameter failure: Why they could not be read.
    /// - Returns: The sentence.
    static func readFailure(_ failure: PSNTrophiesFailure) -> String {
        switch failure {
        case .signedOut:
            "Sign in to PlayStation Network to see your trophies."
        case .auth:
            "PlayStation Network needs you to sign in again."
        case .rateLimited:
            "PlayStation Network asked for a pause. Try again in a few minutes."
        case .notFound:
            "This game is no longer in your trophy list."
        case .unavailable:
            "Trophies could not be loaded. Check your connection and try again."
        case .cancelled:
            "Loading was cancelled."
        }
    }
}

/// The account's trophy level, its progress to the next level and the trophies earned of each grade.
struct TrophySummaryCard: View {
    /// The summary.
    let summary: TrophySummary

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Level \(summary.level)")
                    .font(.title2.weight(.semibold))
                ProgressView(value: Double(summary.progress), total: 100)
                    .frame(width: 220)
                    .accessibilityLabel("Progress to level \(summary.level + 1)")
                    .accessibilityValue("\(summary.progress) percent")
                Text("\(summary.progress)% to level \(summary.level + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            TrophyCountsView(counts: summary.earned, size: .large)
        }
        .padding(20)
        .glassPanel(.medium)
        .accessibilityElement(children: .combine)
    }
}

/// A game's row in the list: its icon, name, platforms, progress and the trophies earned of each grade.
struct TrophyTitleRow: View {
    /// The game.
    let title: TrophyTitle

    var body: some View {
        HStack(spacing: 16) {
            CloudArtworkView(url: title.iconURL)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(title.platforms, id: \.self) { platform in
                        Text(platform.name)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.12), in: .capsule)
                    }
                    if let updated = title.updated {
                        Text(updated.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 12)
            TrophyCountsView(counts: title.earned, size: .small)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(title.progress)%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                ProgressView(value: Double(title.progress), total: 100)
                    .frame(width: 96)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .contentShape(.rect)
    }
}

/// The trophies of each grade, platinum first, with the grade's colour.
struct TrophyCountsView: View {
    /// How large the counts are drawn.
    enum Size {
        /// For the summary card.
        case large
        /// For a game's row.
        case small
    }

    /// The counts.
    let counts: TrophyCounts
    /// How large they are drawn.
    let size: Size

    var body: some View {
        HStack(spacing: size == .large
            ? 18
            : 10) {
                ForEach(TrophyGrade.allCases.reversed(), id: \.self) { grade in
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(grade.color)
                            .accessibilityHidden(true)
                        Text("\(counts[grade])")
                            .monospacedDigit()
                    }
                    .font(size == .large
                        ? .title3.weight(.semibold)
                        : .callout)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(counts[grade]) \(grade.name)")
                }
            }
    }
}

/// An opened game: Back and its name, a choice of group when it has add-ons, and its trophies.
struct TrophyTitleDetail: View {
    /// The opened game.
    let opened: TrophiesFeature.Opened
    /// The trophies shown, filtered and sorted as chosen.
    let trophies: [PSNTrophy]
    /// Which trophies are shown.
    let filter: TrophyFilter
    /// The trophies' order.
    let sort: TrophySort
    /// Whether the trophies run in their sort's order or the other way round.
    let sortDirection: TrophySortDirection
    /// The section's focus.
    let focus: MenuFocusState<TrophiesView.Focus?>.Binding
    /// The row a move is heading to, scrolled into place so the lazy list builds it before it takes focus.
    let revealTarget: TrophiesView.Focus?
    /// Moves focus from a stop.
    let move: (TrophiesView.Focus, MenuMoveDirection) -> Void
    /// Closes the game.
    let close: () -> Void
    /// Chooses a group, or `nil` for every group.
    let select: (String?) -> Void
    /// Reveals or hides a hidden trophy.
    let reveal: (Int) -> Void
    /// Chooses which trophies are shown.
    let chooseFilter: (TrophyFilter) -> Void
    /// Chooses the trophies' order.
    let chooseSort: (TrophySort) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !opened.groups.isEmpty {
                groups
            }
            arrangement
            content
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            stop(.back, action: close) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .frame(
                        minWidth: max(0, layout.controlSize - 16),
                        minHeight: max(0, layout.controlSize - 16)
                    )
            }
            .focusBorderShape(.circle)
            .accessibilityLabel("Back to all games")
            CloudArtworkView(url: opened.title.iconURL)
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(opened.title.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text("\(opened.title.progress)% complete")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if !layout.isCompact {
                TrophyChoicesHint()
            }
            TrophyCountsView(counts: opened.title.earned, size: .large)
        }
    }

    private var groups: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip(.allGroups, name: "All", selected: opened.group == nil) {
                    select(nil)
                }
                ForEach(opened.groups) { group in
                    groupChip(
                        .group(group.id),
                        name: group.name.isEmpty
                            ? group.id
                            : group.name,
                        selected: opened.group == group.id
                    ) {
                        select(group.id)
                    }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder private var arrangement: some View {
        if layout.isCompact {
            HStack(spacing: layout.controlSpacing) {
                ChoiceDropdown(
                    title: "Show",
                    choices: TrophyFilter.allCases,
                    chosen: filter,
                    label: \.name,
                    stop: TrophiesView.Focus.trophyFilter,
                    focus: focus,
                    move: move,
                    choose: chooseFilter
                )
                ChoiceDropdown(
                    title: "Sort",
                    choices: TrophySort.allCases,
                    chosen: sort,
                    label: \.name,
                    stop: TrophiesView.Focus.trophySort,
                    focus: focus,
                    move: move,
                    direction: sortDirection,
                    choose: chooseSort
                )
                Spacer(minLength: 0)
            }
        } else {
            chips
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                TrophyChoiceChips(
                    title: "Show trophies",
                    choices: TrophyFilter.allCases,
                    chosen: filter,
                    label: \.name,
                    stop: TrophiesView.Focus.trophyFilter,
                    focus: focus,
                    move: move,
                    choose: chooseFilter
                )
                TrophyChoiceChips(
                    title: "Sort trophies by",
                    choices: TrophySort.allCases,
                    chosen: sort,
                    label: \.name,
                    stop: TrophiesView.Focus.trophySort,
                    focus: focus,
                    move: move,
                    direction: sortDirection,
                    choose: chooseSort
                )
            }
            .padding(4)
        }
        .padding(.horizontal, -4)
    }

    private func groupChip(
        _ target: TrophiesView.Focus,
        name: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        stop(target, action: action) {
            Text(name)
                .font(.callout.weight(selected
                        ? .semibold
                        : .regular))
                    .lineLimit(1)
                    .frame(minHeight: max(0, layout.controlSize - 16))
        }
        .focusBorderShape(.capsule)
        .accessibilityAddTraits(selected
            ? .isSelected
            : [])
    }

    @ViewBuilder private var content: some View {
        switch opened.listing {
        case .loading:
            Text("Loading trophies")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        case .failed(let failure):
            Text(TrophiesView.readFailure(failure))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        case .loaded where trophies.isEmpty:
            Text("No trophies match these choices.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        case .loaded:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(trophies) { trophy in
                            row(trophy).id(TrophiesView.Focus.trophy(trophy.id))
                        }
                    }
                    .padding(8)
                }
                .selfManagedFocusScrolling()
                .onChange(of: revealTarget, initial: true) { _, target in
                    guard let target, case .trophy = target else {
                        return
                    }
                    proxy.scrollTo(target)
                }
                .onChange(of: focus.wrappedValue) { _, focused in
                    guard let focused, case .trophy = focused else {
                        return
                    }
                    withAnimation(reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.2)) {
                            proxy.scrollTo(focused)
                        }
                }
            }
        }
    }

    private func row(_ trophy: PSNTrophy) -> some View {
        let secret = trophy.hidden && !trophy.earned && !opened.revealed.contains(trophy.id)
        return FocusButton {
            if trophy.hidden, !trophy.earned {
                reveal(trophy.id)
            }
        } label: {
            TrophyRow(trophy: trophy, secret: secret)
        }
        .buttonStyle(.plain)
        .focusWithoutGrowth()
        .focusHighlightShape(.roundedRectangle(14))
        .menuFocused(focus, equals: .trophy(trophy.id))
        .environment(\.menuMove) { direction in
            move(.trophy(trophy.id), direction)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(trophy.hidden && !trophy.earned
            ? secret
                ? "Reveals the hidden trophy"
                : "Hides the trophy again"
            : "")
    }

    private func stop(
        _ target: TrophiesView.Focus,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let content = label()
        return FocusButton(action: action) {
            content
        }
        .glassControlStyle()
        .menuFocused(focus, equals: target)
        .environment(\.menuMove) { direction in
            move(target, direction)
        }
    }
}

/// One trophy: its icon, name, how to earn it, grade, rarity, progress and when it was earned.
struct TrophyRow: View {
    /// The trophy.
    let trophy: PSNTrophy
    /// Whether its name and description stay hidden.
    let secret: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if secret {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
                } else {
                    CloudArtworkView(url: trophy.iconURL)
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                        .opacity(trophy.earned
                            ? 1
                            : 0.45)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(secret
                    ? "Hidden trophy"
                    : trophy.name)
                    .font(.headline)
                Text(secret
                    ? "Press to reveal what this trophy is for."
                    : trophy.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Self.details(of: trophy), id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Label(trophy.grade.name, systemImage: "trophy.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(trophy.grade.color)
                if trophy.earned {
                    Label("Earned", systemImage: AppIcon.selected.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(10)
        .contentShape(.rect)
    }

    /// The lines under a trophy's description: its progress, its rarity and when it was earned.
    ///
    /// - Parameter trophy: The trophy.
    /// - Returns: The lines.
    static func details(of trophy: PSNTrophy) -> [String] {
        var lines: [String] = []
        if let progress = trophy.progress, !trophy.earned {
            lines.append("\(progress.value) of \(progress.target)")
        }
        if let rarity = trophy.rarity {
            if let rate = trophy.earnedRate {
                lines
                    .append(
                        "\(rarity.name), earned by \(rate.formatted(.number.precision(.fractionLength(1))))% of players"
                    )
            } else {
                lines.append(rarity.name)
            }
        }
        if let earned = trophy.earnedAt {
            lines.append("Earned \(earned.formatted(date: .abbreviated, time: .shortened))")
        }
        return lines
    }
}

extension TrophyGrade {
    /// The grade's colour, as trophies are drawn on PlayStation.
    var color: Color {
        switch self {
        case .bronze:
            Color(red: 0.80, green: 0.50, blue: 0.27)
        case .silver:
            Color(red: 0.78, green: 0.80, blue: 0.84)
        case .gold:
            Color(red: 0.93, green: 0.76, blue: 0.27)
        case .platinum:
            Color(red: 0.72, green: 0.82, blue: 0.95)
        }
    }
}

/// The controller prompt for the west button in the Trophies headings: it moves focus to the filters, sorts and
/// search.
private struct TrophyChoicesHint: View {
    var body: some View {
        ControllerPrompt(button: .west, text: "Filters")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
