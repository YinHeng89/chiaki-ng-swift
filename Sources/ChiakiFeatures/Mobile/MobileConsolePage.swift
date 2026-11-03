import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// One console's page in the touch library: its status and main action, how to reach it, Edit and Remove, and
/// the games recently played on it.
struct MobileConsolePage: View {
    /// The library.
    let store: StoreOf<LibraryFeature>

    /// The console.
    let console: RegistrationFlow.ConsoleTarget

    @Environment(\.streamerMode) private var streamerMode
    @Environment(\.screenLayout) private var layout

    var body: some View {
        let status = MobileConsoleStatus.status(of: console, in: store.state)
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    controls(status)
                        .frame(width: 300)
                    games
                        .frame(minWidth: 320, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 24) {
                    controls(status)
                    games
                }
            }
            .padding(.top, MobilePageTitle.topPadding(layout))
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func controls(_ status: MobileConsoleStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ConsoleArtwork(height: 84, kind: console.kind)
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MobileConsoleCard.name(of: console, streamerMode: streamerMode))
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(status.statusTitle)
                        .font(.subheadline)
                        .foregroundStyle(status.statusColor)
                    Text(status.modelTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                start(status.route)
            } label: {
                Label(
                    status.presence == .restMode && !status.away
                        ? "Wake and Play"
                        : status.actionTitle,
                    systemImage: status.actionSymbol
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.accent)
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(store.consolesBusy)
            if console.remoteDeviceID != nil {
                VStack(spacing: 0) {
                    routeRow("Play on Home Network", symbol: "wifi", route: .local)
                        .disabled(status.away)
                    Divider().padding(.leading, 16)
                    routeRow("Play over the Internet", symbol: "globe", route: .remote)
                }
                .background(.fill.quaternary, in: .rect(cornerRadius: 20))
            }
            HStack(spacing: 8) {
                Button {
                    edit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button(role: .destructive) {
                    if let id = console.id {
                        store.send(.requested(.deleteConsole(id)))
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.regular)
            .disabled(console.id == nil || store.consolesBusy)
        }
    }

    private func routeRow(_ title: String, symbol: String, route: PlaybackRoute) -> some View {
        Button {
            start(route)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(store.consolesBusy)
    }

    @ViewBuilder private var games: some View {
        if let id = console.id, let titles = store.recentlyPlayed.rail(for: id)?.titles, !titles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recently Played")
                    .font(.title3.bold())
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 14, alignment: .top)],
                    spacing: 16
                ) {
                    ForEach(titles) { title in
                        MobileRecentTile(title: title) {
                            store.send(.requested(.playTitle(id, title)))
                        }
                        .disabled(store.consolesBusy || store.recentlyPlayed.launch != .idle)
                    }
                }
            }
        }
    }

    private func start(_ route: PlaybackRoute) {
        store.send(.requested(.startConsole(console, route)))
    }

    private func edit() {
        guard let id = console.id else {
            return
        }
        store.send(.requested(.editConsole(ConsoleDraft(
            id: id,
            name: console.name ?? console.address,
            address: console.address,
            generation: console.kind.rawValue,
            remoteAvailable: console.remoteDeviceID != nil,
            hardwareID: console.hardwareID
        ))))
    }
}
