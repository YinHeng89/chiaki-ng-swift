import ChiakiModels
import ComposableArchitecture
import DesignSystem
import SwiftUI

/// What the touch library shows and offers for one console: its name, how it can be reached and the one action
/// that fits.
struct MobileConsoleStatus: Equatable {
    /// The console.
    let console: RegistrationFlow.ConsoleTarget

    /// Whether the console was seen on the home network, and in which state.
    let presence: ConsolePresence

    /// Whether the console must be reached over the internet: it has remote play and is not on the home network.
    var away: Bool {
        console.remoteDeviceID != nil && presence == .notNearby
    }

    /// The route a tap on the action starts.
    var route: PlaybackRoute {
        away
            ? .remote
            : .local
    }

    /// The action the card offers.
    var actionTitle: LocalizedStringResource {
        if away {
            return .mobileConsoleConnect
        }
        return presence == .restMode
            ? .mobileConsoleWake
            : .mobileConsolePlay
    }

    /// The symbol beside the action.
    var actionSymbol: String {
        if away {
            return "globe"
        }
        return presence == .restMode
            ? "power"
            : "play.fill"
    }

    /// Whether the action is the console's main one, drawn prominent.
    var actionProminent: Bool {
        presence == .ready || presence == .restMode
    }

    /// How the console is doing, in words.
    var statusTitle: LocalizedStringResource {
        if away {
            return .mobileConsoleAway
        }
        return presence.title ?? .mobileConsoleLooking
    }

    /// The colour of the status.
    var statusColor: Color {
        away
            ? .blue
            : presence.color
    }

    /// The console's model, in words.
    var modelTitle: LocalizedStringResource {
        console.kind == .ps5
            ? .mobileConsoleModelPs5
            : .mobileConsoleModelPs4
    }

    /// The order consoles are listed in: the ones that can play now first, then resting, then away, then the rest.
    var rank: Int {
        if away {
            return 2
        }
        switch presence {
        case .ready:
            return 0
        case .restMode:
            return 1
        case .unknown:
            return 3
        case .notNearby:
            return 4
        }
    }

    /// The status of each of the library's consoles, in listing order.
    ///
    /// - Parameter state: The library.
    /// - Returns: One status per linked console.
    static func all(in state: LibraryFeature.State) -> [MobileConsoleStatus] {
        state.linkedConsoles.map { status(of: $0, in: state) }
            .enumerated()
            .sorted { lhs, rhs in
                (lhs.element.rank, lhs.offset) < (rhs.element.rank, rhs.offset)
            }
            .map(\.element)
    }

    /// The status of one console.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - state: The library.
    /// - Returns: Its status.
    static func status(of console: RegistrationFlow.ConsoleTarget, in state: LibraryFeature.State) -> Self {
        MobileConsoleStatus(
            console: console,
            presence: ConsolePresence.of(
                console,
                in: state.discovery.snapshot,
                searched: state.discovery.hasSearched
            )
        )
    }
}

/// A console's card in the touch library: its picture, name and status above its model and action.
struct MobileConsoleCard: View {
    /// The console and how it can be reached.
    let status: MobileConsoleStatus

    /// Whether the card shows the larger single-console layout.
    var large = false

    /// Whether the action is unavailable because another console operation runs.
    let busy: Bool

    /// Starts the console.
    let start: () -> Void

    /// Opens the console's page.
    let open: () -> Void

    @Environment(\.streamerMode) private var streamerMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ConsoleArtwork(
                        height: large
                            ? 72
                            : 56,
                        kind: status.console.kind
                    )
                    .frame(width: large
                        ? 52
                        : 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MobileConsoleCard.name(of: status.console, streamerMode: streamerMode))
                            .font(large
                                ? .title2.bold()
                                : .headline)
                                .lineLimit(1)
                        Text(status.statusTitle)
                            .font(.subheadline)
                            .foregroundStyle(status.statusColor)
                        if large {
                            Text(status.modelTitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                if !large {
                    Text(status.modelTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                actionButton
            }
        }
        .padding(16)
        .background(.fill.quaternary, in: .rect(cornerRadius: 24))
        .contextMenu {
            Button(action: start) {
                Label(status.actionTitle, systemImage: status.actionSymbol)
            }
            Button(action: open) {
                Label(.mobileConsoleOpen, systemImage: "info.circle")
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        let label = Label(status.actionTitle, systemImage: status.actionSymbol)
            .font(large
                ? .headline
                : .subheadline.weight(.semibold))
                .frame(maxWidth: large
                    ? .infinity
                    : nil)
        Group {
            if status.actionProminent {
                Button(action: start) {
                    label
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .foregroundStyle(.black)
                .controlSize(large
                    ? .large
                    : .regular)
                    .disabled(busy)
            } else {
                Button(action: start) {
                    label
                }
                .buttonStyle(.glass)
                .controlSize(large
                    ? .large
                    : .regular)
                    .disabled(busy)
            }
        }
        .buttonSizing(large
            ? .flexible
            : .fitted)
            .frame(maxWidth: large
                ? .infinity
                : nil)
    }

    /// The name a console is shown by, hidden in streamer mode.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - streamerMode: Whether streamer mode hides names.
    /// - Returns: The name.
    static func name(of console: RegistrationFlow.ConsoleTarget, streamerMode: Bool) -> String {
        StreamerMode.consoleName(
            console.name,
            address: console.address,
            kind: console.kind.rawValue,
            enabled: streamerMode
        )
    }
}

/// The card that adds a console.
struct MobileAddConsoleCard: View {
    /// Starts adding a console.
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            Label(.mobileConsolesAdd, systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.fill.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
                .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}
