import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The stream menu's Trophies panel during a PS5 cloud or PS Now stream: the game's progress and earned trophies,
/// Refresh, a choice of which trophies are shown and their order, a toggle that reverses the order, then a row for
/// each trophy. The west button moves
/// focus to the choice of trophies shown from anywhere in the panel, as a hint in the title says. Confirm on a hidden
/// trophy not yet earned reveals its name and description, and again hides them. When the focused trophy leaves the
/// list, as a read or a choice can make it, focus moves to the trophy now in its place, or to Reverse order when
/// none is left.
struct StreamMenuTrophiesControls: View {
    /// The panel's store.
    let store: StoreOf<StreamTrophiesFeature>
    /// The stream menu focus binding, or `nil` when the panel is shown outside controller navigation.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding?
    /// The stream menu control that holds focus.
    let focusedControl: StreamMenuControl?
    /// Which page of trophies shows.
    var paging = StreamTrophiesPaging()

    /// The controls a controller moves through: Refresh, the Show and Sort by choices, Reverse order, then each
    /// trophy shown.
    ///
    /// - Parameter state: The panel's state.
    /// - Returns: The controls in navigation order.
    static func controls(for state: StreamTrophiesFeature.State) -> [StreamMenuControl] {
        [.trophiesRefresh, .trophiesFilter, .trophiesSort, .trophiesReverse] + state.shown.map {
            StreamMenuControl.trophy($0.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(.playbackMenuTrophiesTitle).font(.title2.weight(.semibold))
                Spacer(minLength: 8)
                ControllerPrompt(button: .west, text: .playbackMenuTrophiesFilters)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            summary
            FocusButton {
                store.send(.refresh)
            } label: {
                Label(
                    store.isLoading
                        ? .playbackMenuTrophiesRefreshing
                        : .commonRefresh,
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .modifier(OptionalStreamMenuButtonFocus(
                focus: focus,
                target: .trophiesRefresh,
                focused: focusedControl == .trophiesRefresh
            ))
            .glassControlStyle()
            .controlSize(.large)
            StreamMenuDropdown(
                title: .playbackMenuTrophiesShow,
                options: TrophyFilter.allCases,
                optionTitle: \.name,
                selection: Binding {
                    store.filter
                } set: { filter in
                    store.send(.filterChosen(filter))
                },
                target: .trophiesFilter,
                focus: focus,
                focused: focusedControl == .trophiesFilter
            )
            StreamMenuDropdown(
                title: .playbackMenuTrophiesSortBy,
                options: TrophySort.allCases,
                optionTitle: \.name,
                selection: Binding {
                    store.sort
                } set: { sort in
                    store.send(.sortChosen(sort))
                },
                target: .trophiesSort,
                focus: focus,
                focused: focusedControl == .trophiesSort
            )
            reverseToggle
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(minHeight: CGFloat(paging.rows) * Self.trophyRowHeight, alignment: .top)
        }
        .onAppear {
            store.send(.appeared)
        }
        .onChange(of: store.shown.map(\.id)) { before, after in
            keepFocus(from: before, to: after)
        }
    }

    @ViewBuilder
    private var reverseToggle: some View {
        let toggle = Toggle(.playbackMenuTrophiesReverseOrder, isOn: Binding {
            store.direction == .reversed
        } set: { reversed in
            if reversed != (store.direction == .reversed) {
                store.send(.reverseToggled)
            }
        })
        if let focus {
            toggle.modifier(StreamMenuControlFocus(
                focus: focus,
                target: .trophiesReverse,
                focused: focusedControl == .trophiesReverse,
                highlight: false
            ))
        } else {
            toggle
        }
    }

    private func keepFocus(from before: [Int], to after: [Int]) {
        guard let focus, case .control(.trophy(let focused)) = focus.wrappedValue,
              !after.contains(focused) else {
            return
        }
        let position = before.firstIndex(of: focused) ?? 0
        if after.isEmpty {
            focus.wrappedValue = .control(.trophiesReverse)
            return
        }
        focus.wrappedValue = .control(.trophy(after[min(position, after.count - 1)]))
    }

    @ViewBuilder private var summary: some View {
        if let title = store.current?.title {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(.playbackMenuTrophiesPercentComplete(progress: title.progress))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                TrophyCountsView(counts: title.earned, size: .small)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.listing {
        case .idle, .loading(_, kept: nil):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(.playbackMenuTrophiesLoading)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let failure, kept: nil):
            Text(TrophiesView.readFailure(failure))
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded(nil):
            Text(.playbackMenuTrophiesNoneEarned)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded, .loading, .failed:
            if store.shown.isEmpty {
                Text(.playbackMenuTrophiesNoMatch)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                let shown = store.shown
                let page = Self.page(of: paging, in: shown)
                ForEach(shown[page]) { trophy in
                    row(trophy)
                }
                if shown.count > paging.rows {
                    Text(.playbackMenuTrophiesPage(
                        first: page.lowerBound + 1,
                        last: page.upperBound,
                        total: shown.count
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// How many trophies the panel shows at once, so a long list never pushes the dock off the screen.

    /// About how tall a trophy row is with its spacing, in points, so a page's height is held while the trophies
    /// load and the panel does not grow when they arrive.
    nonisolated static let trophyRowHeight: CGFloat = 90

    /// The trophies shown on the page that holds the paging anchor, or on the first page while the anchor is
    /// above the list.
    ///
    /// - Parameters:
    ///   - paging: The control focus is on or moving to, and the rows a page holds.
    ///   - trophies: The trophies shown, filtered and sorted.
    /// - Returns: The range of `trophies` on the page.
    nonisolated static func page(of paging: StreamTrophiesPaging, in trophies: [PSNTrophy]) -> Range<Int> {
        let rows = max(1, paging.rows)
        var index = 0
        if case .trophy(let id) = paging.anchor, let found = trophies.firstIndex(where: { $0.id == id }) {
            index = found
        }
        let start = index / rows * rows
        return start ..< min(start + rows, trophies.count)
    }

    private func row(_ trophy: PSNTrophy) -> some View {
        let secret = trophy.hidden && !trophy.earned && !store.revealed.contains(trophy.id)
        return FocusButton {
            if trophy.hidden, !trophy.earned {
                store.send(.revealToggled(trophy.id))
            }
        } label: {
            TrophyRow(trophy: trophy, secret: secret)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(14))
        .modifier(OptionalStreamMenuButtonFocus(
            focus: focus,
            target: .trophy(trophy.id),
            focused: focusedControl == .trophy(trophy.id)
        ))
        .accessibilityElement(children: .combine)
        .accessibilityHint(revealHint(trophy, secret: secret))
    }

    private func revealHint(_ trophy: PSNTrophy, secret: Bool) -> Text {
        guard trophy.hidden, !trophy.earned else {
            return Text(verbatim: "")
        }
        return Text(secret
            ? .playbackMenuTrophiesRevealHint
            : .playbackMenuTrophiesHideHint)
    }
}

/// Which page of the stream menu's Trophies panel shows: the page that holds the control focus is on or moving
/// to, decided before focus moves so the row it moves to is already shown, and how many rows a page holds.
struct StreamTrophiesPaging: Equatable, Sendable {
    /// The control focus is on or moving to; a trophy picks its page and anything else the first page.
    var anchor: StreamMenuControl?
    /// How many trophies a page holds, fitted to the window so the dock stays on screen.
    var rows = 6
}
