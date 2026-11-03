import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// The touch library's Consoles section: one console with its recently played games beside it, or a grid of
/// compact cards when there are several, with a card that adds a console.
struct MobileConsolesView: View {
    /// The library.
    let store: StoreOf<LibraryFeature>

    @Environment(\.screenLayout) private var layout

    var body: some View {
        let consoles = MobileConsoleStatus.all(in: store.state)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MobilePageTitle("Consoles")
                if consoles.count == 1, let only = consoles.first {
                    single(only)
                } else {
                    grid(consoles)
                }
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            store.send(.requested(.refreshAccounts))
        }
    }

    @ViewBuilder private func single(_ status: MobileConsoleStatus) -> some View {
        if !layout.isCompact || layout.isShort {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 12) {
                    card(status, large: true)
                    MobileAddConsoleCard(add: addConsole)
                        .frame(height: 52)
                }
                .frame(width: 300)
                recent(for: status.console)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                card(status, large: true)
                recent(for: status.console)
                MobileAddConsoleCard(add: addConsole)
                    .frame(height: 52)
            }
        }
    }

    private func grid(_ consoles: [MobileConsoleStatus]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)],
            spacing: 12
        ) {
            ForEach(consoles, id: \.console) { status in
                card(status, large: false)
            }
            MobileAddConsoleCard(add: addConsole)
                .frame(minHeight: 124)
        }
    }

    private func card(_ status: MobileConsoleStatus, large: Bool) -> some View {
        MobileConsoleCard(
            status: status,
            large: large,
            busy: store.consolesBusy,
            start: {
                store.send(.requested(.startConsole(status.console, status.route)))
            },
            open: {
                if let id = status.console.id {
                    store.send(.mobile(.consoleOpened(id)))
                }
            }
        )
    }

    @ViewBuilder private func recent(for console: RegistrationFlow.ConsoleTarget) -> some View {
        if let id = console.id, let titles = store.recentlyPlayed.rail(for: id)?.titles, !titles.isEmpty {
            MobileRecentRow(
                titles: titles,
                disabled: store.consolesBusy || store.recentlyPlayed.launch != .idle
            ) { title in
                store.send(.requested(.playTitle(id, title)))
            }
        }
    }

    private func addConsole() {
        store.send(.requested(.addConsole))
    }
}

/// A console's recently played games in one horizontal row, each started on that console when tapped.
struct MobileRecentRow: View {
    /// The games, most recent first.
    let titles: [RecentTitle]

    /// Whether the games cannot be started now.
    let disabled: Bool

    /// Starts a game.
    let play: (RecentTitle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Played")
                .font(.title3.bold())
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(titles) { title in
                        MobileRecentTile(title: title, size: 100) {
                            play(title)
                        }
                        .disabled(disabled)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// One recently played game: its square art, its name on up to two lines and when it was played.
struct MobileRecentTile: View {
    /// The game.
    let title: RecentTitle

    /// The side of the art, or `nil` to fill the column.
    var size: CGFloat?

    /// Starts the game.
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 5) {
                CloudArtworkView(url: .secureArtwork(title.imageURL))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: 14))
                Text(title.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let played = title.lastPlayed {
                    Text(played.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: size, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// The title at the top of a touch library page.
struct MobilePageTitle: View {
    /// The title.
    let title: String

    /// Creates a page title.
    ///
    /// - Parameter title: The title.
    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title.bold())
            .accessibilityAddTraits(.isHeader)
    }

    /// The space above a page's title, clear of the status bar where there is one.
    ///
    /// - Parameter layout: The screen's layout.
    /// - Returns: The padding in points.
    static func topPadding(_ layout: ScreenLayout) -> CGFloat {
        layout.isShort
            ? 28
            : layout.topChromeInset + 16
    }
}
