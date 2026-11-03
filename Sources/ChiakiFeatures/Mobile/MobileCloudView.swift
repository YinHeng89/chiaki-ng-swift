import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// The touch library's Cloud section: a search field and the Show and Platform menus above one scrolling grid
/// of the matching games, refreshed by pulling down.
struct MobileCloudView: View {
    /// The cloud library.
    @Bindable var store: StoreOf<CloudLibraryFeature>

    @Environment(\.screenLayout) private var layout
    @Environment(\.catalog) private var catalog
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controls
                content
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .task(id: store.matchingGames.map(\.id)) {
            guard let box = ArtworkBox(points: CGSize(width: 124, height: 124), scale: displayScale) else {
                return
            }
            await catalog.prefetch(store.matchingGames.compactMap { URL.secureArtwork($0.imageUrl) }, box)
        }
        .refreshable {
            if store.libraryRefresh == .ready, store.accountID != nil {
                store.send(.refresh)
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                searchField
                filterMenu
                platformMenu
                refreshButton
            }
            VStack(spacing: 10) {
                searchField
                HStack(spacing: 10) {
                    filterMenu
                    platformMenu
                    Spacer(minLength: 0)
                    refreshButton
                }
            }
        }
    }

    private var searchField: some View {
        MobileSearchEntry(prompt: "Search Cloud", text: $store.query)
            .padding(.horizontal, 14)
            .frame(minWidth: 220, minHeight: 40)
            .background(.fill.tertiary, in: .capsule)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: Binding(
                get: { store.filter },
                set: { store.send(.filter($0)) }
            )) {
                ForEach(store.filters, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            MobileMenuLabel(caption: "Show", value: store.filter.title)
        }
    }

    private var platformMenu: some View {
        Menu {
            Picker("Platform", selection: Binding(
                get: { store.platform },
                set: { store.send(.platform($0)) }
            )) {
                ForEach(CloudPlatformFilter.allCases, id: \.self) { platform in
                    Text(platform.title).tag(platform)
                }
            }
        } label: {
            MobileMenuLabel(caption: "Platform", value: store.platform.title)
        }
    }

    private var refreshButton: some View {
        CloudRefreshButton(disabled: store.accountID == nil, cooldown: store.libraryRefresh) {
            if store.libraryRefresh.isReady {
                store.send(.refresh)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let games = store.matchingGames
        if let progress = store.phase.fetchProgress, !games.isEmpty {
            MobileCloudProgress(progress: progress, compact: true)
        }
        if games.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96, maximum: 124), spacing: 14, alignment: .top)],
                spacing: 18
            ) {
                ForEach(games) { game in
                    MobileCloudTile(
                        game: game,
                        lastPlayed: store.listing.lastPlayed(game)
                    ) {
                        store.send(.select(game.id))
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch store.phase {
        case .idle:
            ProgressView()
        case .loading:
            MobileCloudProgress(progress: store.phase.fetchProgress, compact: false)
        case .failed:
            ContentUnavailableView(
                "Couldn’t load your games",
                systemImage: "cloud.slash",
                description: Text("Pull down to try again.")
            )
        case .ready:
            ContentUnavailableView(
                store.query.isEmpty
                    ? "No games here"
                    : "No results",
                systemImage: store.query.isEmpty
                    ? "square.grid.2x2"
                    : "magnifyingglass"
            )
        }
    }
}

/// What the cloud library is loading, as the Mac shows it: the connecting logo with the current step, its detail
/// and the pages read, or one line above the grid while games already show.
struct MobileCloudProgress: View {
    /// The load's progress, or `nil` before the first step is known.
    let progress: CloudLibraryFetchProgress?

    /// Whether to show one line above the grid instead of the full loader.
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if compact {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text([progress?.step, progress?.pages].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(.fill.quaternary, in: .capsule)
        } else {
            VStack(spacing: 18) {
                ChiakiLogo(size: 96, isConnecting: true)
                VStack(spacing: 6) {
                    Text(progress?.step ?? "Loading cloud library")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.78))
                        .id(progress?.step)
                        .transition(AppMotion.transition(reduced: reduceMotion))
                    if let detail = progress?.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if let pages = progress?.pages {
                        Text(pages)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .multilineTextAlignment(.center)
                .animation(AppMotion.animation(reduced: reduceMotion), value: progress?.step)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .accessibilityElement(children: .combine)
        }
    }
}

/// One cloud game in the touch grid: its square art, its name on up to two lines and its platform with when it
/// was last played.
struct MobileCloudTile: View {
    /// The game.
    let game: CloudGame

    /// When the account last played it, when known.
    let lastPlayed: Date?

    /// Opens the game.
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                CloudArtworkView(url: .secureArtwork(game.imageUrl))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .bottomLeading) {
                        if game.plusCatalog, !game.isOwned {
                            Image(systemName: "plus")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.black)
                                .frame(width: 20, height: 20)
                                .background(.yellow, in: .rect(cornerRadius: 6))
                                .padding(6)
                                .accessibilityLabel("PlayStation Plus")
                        }
                    }
                Text(game.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var caption: String {
        let platforms = [game.platform, game.otherPlatform].compactMap { $0 }.joined(separator: " · ")
        guard let lastPlayed else {
            return platforms
        }
        return "\(platforms) · \(lastPlayed.formatted(.relative(presentation: .named)))"
    }
}

/// A menu's label in the touch library: what it chooses, then the current choice.
struct MobileMenuLabel: View {
    /// What the menu chooses.
    let caption: String

    /// The current choice.
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(caption)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(.fill.tertiary, in: .capsule)
    }
}

/// The open cloud game, drawn over the whole screen with its layered art, as the library shows it elsewhere.
struct MobileCloudDetail: View {
    /// The cloud library.
    let store: StoreOf<CloudLibraryFeature>

    /// The game.
    let game: CloudGame

    /// The height of the screen.
    let height: CGFloat

    @MenuFocusState private var focus: CloudLibraryFocus?

    var body: some View {
        CloudGameDetail(
            game: game,
            accountID: store.accountID,
            height: height,
            store: store,
            focus: $focus,
            heldFocus: { nil }
        )
    }
}
