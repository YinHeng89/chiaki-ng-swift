import ChiakiModels
import SwiftUI
import ChiakiClients
import Dependencies
import DesignSystem
import MenuFocus

/// A focusable cloud game in the library grid that lifts and grows while hovered or focused and opens the
/// game's detail when pressed.
struct CloudGameTile: View {
    /// The spring the tile lifts with, replaced by a short fade when Reduce Motion is on.
    static let lift = Animation.spring(response: 0.35, dampingFraction: 0.62)

    /// The game the tile shows.
    let game: CloudGame
    /// Whether the game is the one whose detail is open, which keeps a faint outline on it.
    let selected: Bool
    /// When the game was last played, shown instead of its standing when known.
    var lastPlayed: Date?
    /// The game's store page check, if one ran, which decides its stream badge and standing.
    var check: CloudCardCheck?
    /// The library's controller focus, which this tile takes when it is the focused game.
    @MenuFocusState.Binding var focus: CloudLibraryFocus?
    /// Opens the game's detail.
    let select: () -> Void
    /// Moves controller focus away from the tile in a direction.
    let move: @MainActor (MenuMoveDirection) -> Void
    @State private var hovered = false
    @Environment(\.inputMode) private var inputMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool {
        hovered || inputMode.shows(focus == .game(game.id))
    }

    var body: some View {
        FocusButton(action: select) {
            CloudGameCard(
                game: game,
                selected: selected,
                active: active,
                lastPlayed: lastPlayed,
                check: check
            )
            .equatable()
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.contained)
        .menuFocused($focus, equals: .game(game.id))
        .environment(\.menuMove, move)
        .accessibilityLabel(game.spokenTileLabel(after: check))
        .offset(y: active && !reduceMotion
            ? -8
            : 0)
            .scaleEffect(active && !reduceMotion
                ? 1.035
                : 1)
                .zIndex(active
                    ? 2
                    : 0)
                    .animation(reduceMotion
                        ? .easeInOut(duration: 0.2)
                        : Self.lift, value: active)
                        .onHover {
                            hovered = $0
                        }
    }
}

/// The cover, platform badge, stream badge, name and status line of one cloud game, outlined when selected
/// and raised when active.
struct CloudGameCard: View, Equatable {
    /// The game the card shows.
    let game: CloudGame
    /// Whether the game's detail is open, which draws a faint outline.
    let selected: Bool
    /// Whether the card is hovered or focused, which draws a full outline and a deeper shadow.
    let active: Bool
    /// When the game was last played, shown in the status line instead of its standing when known.
    var lastPlayed: Date?
    /// The game's store page check, if one ran.
    var check: CloudCardCheck?

    /// The cover's outline colour: the accent when active, a faint accent when selected and clear otherwise.
    var outline: Color {
        if active {
            return Palette.accent
        }
        return selected
            ? Palette.accent.opacity(0.5)
            : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CloudArtworkView(url: .secureArtwork(game.imageUrl))
                .aspectRatio(CloudGridMetrics.coverAspect, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .containedFocusGlow(in: .roundedRectangle(12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(outline, lineWidth: active
                            ? 2
                            : 1.5)
                }
                .overlay(alignment: .topTrailing) {
                    CloudStreamBadge(mark: CloudStreamMark(game, check: check), checking: check == .checking)
                }
                .overlay(alignment: .topLeading) {
                    CloudPlatformBadge(platform: game.platform, alsoOn: game.otherPlatform)
                }
                .overlay(alignment: .bottomLeading) {
                    if let label = game.trialLabel, let icon = game.trialIcon {
                        CloudTrialBadge(icon: icon, label: label)
                    } else if let label = game.trialOfferLabel, let icon = game.trialOfferIcon {
                        CloudTrialBadge(icon: icon, label: label)
                    }
                }
                .shadow(color: .black.opacity(active
                        ? 0.5
                        : 0.3), radius: active
                    ? 19
                    : 13, y: active
                        ? 18
                        : 10)
            ScrollingText(text: game.name, font: .system(size: 16, weight: .semibold))
                .frame(height: 22)
                .padding(.top, 10)
            CloudCardStatus(game: game, lastPlayed: lastPlayed, check: check)
                .frame(height: CloudCardStatus.height, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line under a cloud game's name: when it was last played, its release countdown, or its standing, each with
/// an entitlement icon.
struct CloudCardStatus: View {
    /// The fixed height of the status line, so cards with different statuses line up.
    static let height: CGFloat = 28

    /// The game the line describes.
    let game: CloudGame
    /// When the game was last played, which takes priority over everything else when known.
    var lastPlayed: Date?
    /// The game's store page check, if one ran, which can change the standing shown.
    var check: CloudCardCheck?
    @Environment(\.catalog) private var catalog

    private var mark: CloudStreamMark {
        CloudStreamMark(game, check: check)
    }

    var body: some View {
        if let lastPlayed, lastPlayed.timeIntervalSince1970 > 0 {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(spacing: 6) {
                    icon
                    Text(lastPlayed.formatted(.relative(presentation: .named).locale(.current)))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .id(context.date)
                }
            }
        } else if game.release == .unrestricted {
            line(mark.label ?? game.standingLabel(after: check))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                line(game.release.label(now: catalog.serverTime() ?? timeline.date)
                    ?? game.standingLabel(after: check))
                    .accessibilityIdentifier("cloud-release")
            }
        }
    }

    private var icon: some View {
        CloudMarkSymbol(icon: mark.statusIcon ?? game.entitlementIcon, size: 13)
            .font(.system(size: 13, weight: game.isInCatalog && !game.isTrial && mark == .none
                    ? .heavy
                    : .regular))
                .foregroundStyle(game.isInCatalog && !game.isTrial && mark == .none
                    ? Color.yellow
                    : .white.opacity(0.8))
    }

    private func line(_ standing: LocalizedStringResource) -> some View {
        HStack(spacing: 6) {
            icon
            Text(standing)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
    }
}

/// How a cloud game's ability to stream is marked on its card, combining the catalog's standing with the
/// store page check.
enum CloudStreamMark: Equatable {
    /// Streams as far as anyone knows, so nothing is marked; the catalog may stream but nothing confirmed it;
    /// the store page or stream server said it cannot stream.
    case none, unconfirmed, unavailable

    /// Works out the mark from the catalog's standing and the store page check.
    ///
    /// - Parameters:
    ///   - game: The game being marked.
    ///   - check: The game's store page check, if one ran.
    init(_ game: CloudGame, check: CloudCardCheck?) {
        switch check {
        case .streams:
            self = .none
        case .notStreamable, .refused:
            self = .unavailable
        case .checking, .unavailable, nil:
            self = game.standing == .mayStream
                ? .unconfirmed
                : .none
        }
    }

    /// The badge icon drawn over the cover, or `nil` when nothing is marked.
    var icon: AppIcon? {
        switch self {
        case .none:
            nil
        case .unconfirmed:
            .cloudUnconfirmed
        case .unavailable:
            .cloudUnavailable
        }
    }

    /// The status line text for an unconfirmed game, or `nil` when the line shows the standing instead.
    var label: LocalizedStringResource? {
        self == .unconfirmed
            ? .libraryStreamMarkNotConfirmed
            : nil
    }

    /// The icon the status line uses in place of the entitlement icon, or `nil` to keep the entitlement icon.
    var statusIcon: AppIcon? {
        switch self {
        case .none:
            nil
        case .unconfirmed:
            .cloudUnconfirmed
        case .unavailable:
            .store
        }
    }

    /// The mark as VoiceOver reads it in the card's label, or `nil` when nothing is marked.
    var spoken: LocalizedStringResource? {
        switch self {
        case .none:
            nil
        case .unconfirmed:
            .libraryStreamMarkNotConfirmed
        case .unavailable:
            .libraryStreamMarkNotStreamable
        }
    }

    /// The short caption the badge shows beside its icon on touch, where its help text cannot be hovered, or
    /// `nil` when nothing is marked.
    var caption: LocalizedStringResource? {
        switch self {
        case .none:
            nil
        case .unconfirmed:
            .libraryStreamMarkMayNotStream
        case .unavailable:
            .libraryStreamMarkNotStreamable
        }
    }

    /// The badge's help text explaining the mark, or `nil` when nothing is marked.
    var help: LocalizedStringResource? {
        switch self {
        case .none:
            nil
        case .unconfirmed:
            .libraryStreamMarkUnconfirmedHelp
        case .unavailable:
            .libraryStreamMarkUnavailableHelp
        }
    }
}

/// A glass badge in the cover's corner showing a stream mark, pulsing while the store page check runs;
/// nothing is drawn when there is no mark.
///
/// Under a pointer the badge is a round icon whose meaning is its help text; on touch it carries a short
/// caption instead, since nothing hovers there, except on a compact screen whose narrow cards only fit the
/// icon beside the platform badge.
struct CloudStreamBadge: View {
    /// The mark the badge shows.
    let mark: CloudStreamMark
    /// Whether the store page check is running, which pulses the icon unless Reduce Motion is on.
    var checking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout

    var body: some View {
        if let icon = mark.icon {
            HStack(spacing: 5) {
                CloudMarkSymbol(icon: icon, size: 15)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.pulse, isActive: checking && !reduceMotion)
                    .frame(width: 32, height: 32)
                if !layout.hoverAffordances, !layout.isCompact, let caption = mark.caption {
                    Text(caption)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.3)
                        .lineLimit(1)
                        .padding(.trailing, 10)
                }
            }
            .foregroundStyle(.white)
            .glassEffect(AppGlass.panel, in: .capsule)
            .padding(8)
            .help(mark.help ?? "")
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }
}

/// Glass capsules in the cover's corner naming the game's platform, and the platform of its other generation's
/// version beside it when the card stands for both, stacked under it on a compact screen whose narrow cards
/// cannot fit two side by side, and hidden when the platform is unknown.
struct CloudPlatformBadge: View {
    /// The platform name, drawn in capitals.
    let platform: String
    /// The platform of the other generation's version the card also stands for, or `nil` when it stands for
    /// one version.
    var alsoOn: String?

    @Environment(\.screenLayout) private var layout

    var body: some View {
        if !platform.isEmpty {
            Group {
                if layout.isCompact {
                    VStack(alignment: .leading, spacing: 4) {
                        capsules
                    }
                } else {
                    HStack(spacing: 4) {
                        capsules
                    }
                }
            }
            .padding(10)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var capsules: some View {
        capsule(platform)
        if let alsoOn {
            capsule(alsoOn)
        }
    }

    private func capsule(_ name: String) -> some View {
        Text(name.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .glassEffect(AppGlass.panel, in: .capsule)
    }
}

/// The badge on a trial's cover, or on a store game that offers a trial version: the trial's icon and its state,
/// in the glass of the platform badge.
struct CloudTrialBadge: View {
    /// The hourglass for a Play First Trial or the demo icon for an ordinary trial.
    let icon: AppIcon
    /// The trial's state, such as Trial, Demo, Trial available or Demo available.
    let label: LocalizedStringResource

    var body: some View {
        HStack(spacing: 5) {
            icon.image
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .glassEffect(AppGlass.panel, in: .capsule)
        .padding(10)
        .accessibilityHidden(true)
    }
}

/// An app icon that overlays a question mark on the unconfirmed cloud icon and draws every other icon as is.
struct CloudMarkSymbol: View {
    /// The icon to draw.
    let icon: AppIcon
    /// The icon's point size, which scales the question mark.
    let size: CGFloat

    var body: some View {
        if icon == .cloudUnconfirmed {
            icon.image
                .overlay {
                    Image(systemName: "questionmark")
                        .font(.system(size: size * 0.42, weight: .heavy))
                        .offset(y: size * 0.08)
                }
        } else {
            icon.image
        }
    }
}

/// One line of game detail metadata: an icon beside scrolling text.
struct CloudGameMetadata: View {
    /// The text shown beside the icon.
    let text: String
    /// The icon leading the line.
    let icon: AppIcon
    /// Whether the icon is drawn heavy and yellow to call out catalog games.
    var highlighted = false

    var body: some View {
        HStack(spacing: 9) {
            icon.image.font(.system(size: 18, weight: highlighted
                    ? .heavy
                    : .regular))
                .foregroundStyle(highlighted
                    ? Color.yellow
                    : .white.opacity(0.8))
                    .frame(width: 22)
            ScrollingText(text: text, font: .system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// A metadata line counting down to a game's release in server time, updated every second and hidden once the
/// game is released.
struct CloudReleaseCountdown: View {
    /// The release date counted down to.
    let release: CloudReleaseDate
    @Environment(\.catalog) private var catalog

    var body: some View {
        if release != .unrestricted {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                if let label = release.label(now: catalog.serverTime() ?? timeline.date) {
                    CloudGameMetadata(text: String(localized: label), icon: .release)
                        .accessibilityIdentifier("cloud-release")
                }
            }
        }
    }
}

extension CloudGame {
    /// The game's standing once the store page check is taken into account.
    ///
    /// A refused or unstreamable check sends the game to the store; a confirmed check upgrades a game that
    /// may stream to
    /// in library or included, depending on how it is owned.
    ///
    /// - Parameter check: The game's store page check, if one ran.
    /// - Returns: The standing to show for the game.
    func standing(after check: CloudCardCheck?) -> CloudStanding {
        if check == .notStreamable || check == .refused {
            return .store
        }
        guard standing == .mayStream, check == .streams else {
            return standing
        }
        if isOwnedPS5 {
            return .inLibrary
        }
        if isInCatalog {
            return .included
        }
        return isOwned
            ? .inLibrary
            : .store
    }

    /// The standing as the library labels it: a trial reads Trial or Demo, as the standing alone would call it
    /// a library game, unless it can only be bought.
    ///
    /// - Parameter check: The game's store page check, if one ran.
    /// - Returns: The label to show for the game.
    func standingLabel(after check: CloudCardCheck?) -> LocalizedStringResource {
        let standing = standing(after: check)
        guard let trialLabel, standing != .store, standing != .ownershipUnknown else {
            return standing.label
        }
        return trialLabel
    }

    /// What VoiceOver says for the game's tile: that it opens the details, then the stream mark and the trial
    /// badge, when either is shown.
    ///
    /// - Parameter check: The game's store page check, if one ran.
    /// - Returns: The spoken label.
    func spokenTileLabel(after check: CloudCardCheck?) -> LocalizedStringResource {
        let notes = [CloudStreamMark(self, check: check).spoken, trialLabel ?? trialOfferLabel]
            .compactMap { $0.map { String(localized: $0).lowercased() } }
        guard !notes.isEmpty else {
            return .libraryCardShowDetails(name: name)
        }
        return .libraryCardShowDetailsNotes(name: name, notes: notes.joined(separator: ", "))
    }

    /// The icon for how the game is held: the trial or demo icon for trials, library for owned games,
    /// subscription for catalog games and store otherwise.
    var entitlementIcon: AppIcon {
        if let trialIcon {
            return trialIcon
        }
        if isOwnedPS5 {
            return .library
        }
        if isInCatalog {
            return .subscription
        }
        return isOwned
            ? .library
            : .store
    }
}
