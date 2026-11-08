import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch library's Trophies section: the account's totals beside the list of games, with Show and Sort
/// menus on the list, or one game's trophies once it is opened.
struct MobileTrophiesView: View {
    /// The trophies.
    let store: StoreOf<TrophiesFeature>

    @Environment(\.screenLayout) private var layout

    var body: some View {
        if let opened = store.opened {
            MobileTrophyTitleView(store: store, opened: opened)
        } else {
            overview
        }
    }

    private static let sideWidth: CGFloat = 240

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MobilePageTitle(.mobileTrophiesTitle)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        side
                            .frame(width: Self.sideWidth)
                            .modifier(MobileStickyColumn())
                        titles(showsHeader: false)
                            .frame(minWidth: 360)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        summary
                        titles(showsHeader: true)
                    }
                }
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            if !store.isLoading {
                store.send(.refresh)
            }
        }
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            VStack(spacing: 0) {
                filterMenu {
                    sideRow(caption: .mobileCloudShow, value: store.titleFilter.name)
                }
                Divider().padding(.horizontal, 16)
                sortMenu {
                    sideRow(caption: .mobileTrophiesSort, value: store.titleSort.name)
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 20))
        }
    }

    private func sideRow(caption: LocalizedStringResource, value: LocalizedStringResource) -> some View {
        HStack(spacing: 6) {
            Text(caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Palette.accent)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private func filterMenu(@ViewBuilder label: () -> some View) -> some View {
        Menu {
            Picker(selection: Binding(
                get: { store.titleFilter },
                set: { store.send(.titleFilterChosen($0)) }
            )) {
                ForEach(TrophyTitleFilter.allCases, id: \.self) { filter in
                    Text(filter.name).tag(filter)
                }
            } label: {
                Text(.mobileCloudShow)
            }
        } label: {
            label()
        }
    }

    private func sortMenu(@ViewBuilder label: () -> some View) -> some View {
        Menu {
            ForEach(TrophyTitleSort.allCases, id: \.self) { sort in
                Button {
                    store.send(.titleSortChosen(sort))
                } label: {
                    if sort == store.titleSort {
                        Label(sort.name, systemImage: "checkmark")
                    } else {
                        Text(sort.name)
                    }
                }
            }
        } label: {
            label()
        }
    }

    @ViewBuilder private var summary: some View {
        if let summary = store.overview?.summary {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(.mobileTrophiesLevel(level: summary.level))
                        .font(.title.bold())
                    Text(.mobileTrophiesCount(count: summary.earned.total))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                TrophyCountsView(counts: summary.earned, size: .small)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 24))
        }
    }

    private func titles(showsHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack {
                    Text(.mobileTrophiesGames)
                        .font(.title3.bold())
                    Spacer()
                    filterMenu {
                        MobileMenuLabel(caption: .mobileCloudShow, value: store.titleFilter.name)
                    }
                    sortMenu {
                        MobileMenuLabel(caption: .mobileTrophiesSort, value: store.titleSort.name)
                    }
                }
            }
            let shown = store.shownTitles
            if shown.isEmpty {
                Group {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        ContentUnavailableView {
                            Label(.mobileTrophiesNoGames, systemImage: "trophy")
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { title in
                        Button {
                            store.send(.open(title.id))
                        } label: {
                            MobileTrophyTitleRow(title: title)
                        }
                        .buttonStyle(.plain)
                        if title.id != shown.last?.id {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .background(.fill.quaternary, in: .rect(cornerRadius: 24))
            }
        }
    }
}

/// One game in the trophies list: its art, name, platform and last trophy date, its counts and its progress ring.
struct MobileTrophyTitleRow: View {
    /// The game.
    let title: TrophyTitle

    var body: some View {
        HStack(spacing: 12) {
            CloudArtworkView(url: title.iconURL, contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TrophyCountsView(counts: title.earned, size: .small)
            }
            Spacer(minLength: 8)
            MobileProgressRing(value: title.progress)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var subtitle: String {
        let platforms = title.platforms.map { String(localized: $0.name) }.joined(separator: " · ")
        guard let updated = title.updated else {
            return platforms
        }
        return "\(platforms) · \(updated.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// A small ring showing a percentage, cyan when complete.
struct MobileProgressRing: View {
    /// The percentage, from 0 to 100.
    let value: Int

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.fill.tertiary, lineWidth: 4)
            Circle()
                .inset(by: 2)
                .trim(from: 0, to: CGFloat(min(max(value, 0), 100)) / 100)
                .stroke(
                    value >= 100
                        ? Color.cyan
                        : Palette.accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .frame(width: 38, height: 38)
        .accessibilityElement()
        .accessibilityLabel(Text(.mobileTrophiesPercent(value: value)))
    }
}

/// One opened game's trophies: its header with counts and progress, Show and Sort menus, and the trophies,
/// where tapping a hidden one reveals it.
struct MobileTrophyTitleView: View {
    /// The trophies.
    let store: StoreOf<TrophiesFeature>

    /// The opened game.
    let opened: TrophiesFeature.Opened

    @Environment(\.screenLayout) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    CloudArtworkView(url: opened.title.iconURL, contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(opened.title.name)
                            .font(.title2.bold())
                            .lineLimit(2)
                        TrophyCountsView(counts: opened.title.earned, size: .small)
                    }
                    Spacer()
                    MobileProgressRing(value: opened.title.progress)
                }
                HStack {
                    Text(.mobileTrophiesTitle)
                        .font(.title3.bold())
                    Spacer()
                    Menu {
                        Picker(selection: Binding(
                            get: { store.trophyFilter },
                            set: { store.send(.trophyFilterChosen($0)) }
                        )) {
                            ForEach(TrophyFilter.allCases, id: \.self) { filter in
                                Text(filter.name).tag(filter)
                            }
                        } label: {
                            Text(.mobileCloudShow)
                        }
                    } label: {
                        MobileMenuLabel(caption: .mobileCloudShow, value: store.trophyFilter.name)
                    }
                    Menu {
                        ForEach(TrophySort.allCases, id: \.self) { sort in
                            Button {
                                store.send(.trophySortChosen(sort))
                            } label: {
                                if sort == store.trophySort {
                                    Label(sort.name, systemImage: "checkmark")
                                } else {
                                    Text(sort.name)
                                }
                            }
                        }
                    } label: {
                        MobileMenuLabel(caption: .mobileTrophiesSort, value: store.trophySort.name)
                    }
                }
                trophies
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var trophies: some View {
        switch opened.listing {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        case .failed:
            ContentUnavailableView {
                Label(.mobileTrophiesLoadFailed, systemImage: "trophy")
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        case .loaded:
            LazyVStack(spacing: 0) {
                ForEach(opened.shown) { trophy in
                    let secret = trophy.hidden && !trophy.earned && !opened.revealed.contains(trophy.id)
                    Button {
                        if trophy.hidden, !trophy.earned {
                            store.send(.revealToggled(trophy.id))
                        }
                    } label: {
                        TrophyRow(trophy: trophy, secret: secret)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if trophy.id != opened.shown.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 24))
        }
    }
}
