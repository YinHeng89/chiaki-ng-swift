import ChiakiModels
import ComposableArchitecture
import SwiftUI
import DesignSystem
import MenuFocus

/// The shelf's recently played section: one horizontally scrolling rail of titles per paired PS5, with a
/// notice when the PlayStation sign-in has expired.
///
/// Rails show placeholders while titles load, and their tiles are disabled while the app is busy or a title
/// is launching.
struct RecentlyPlayedSection: View {
    @Environment(\.streamerMode) private var streamerMode
    /// One console's rail in the section.
    struct Row: Identifiable {
        /// The console the titles were played on.
        let console: RegistrationFlow.ConsoleTarget
        /// The console's stored id.
        let consoleID: UUID
        /// The titles to show, or `nil` while they load and placeholders are shown.
        let titles: [RecentTitle]?
        /// Identifies the row by its console id.
        var id: UUID {
            consoleID
        }
    }

    /// The recently played titles the app loaded.
    let recentlyPlayed: RecentlyPlayedReducer.State
    /// The paired consoles, in shelf order.
    let consoles: [RegistrationFlow.ConsoleTarget]
    /// The consoles whose card already shows their last title, so their rail skips it.
    var continuing: Set<UUID> = []
    /// Whether the app is busy and the tiles are disabled.
    let busy: Bool
    /// Starts the given title on the given console.
    let play: (UUID, RecentTitle) -> Void
    /// The shelf's controller focus, bound to the title tiles.
    @MenuFocusState.Binding var focus: ConsoleLibraryFocus?
    /// Moves controller focus from a tile in a direction.
    let move: (ConsoleLibraryFocus, MenuMoveDirection) -> Void

    /// The rows shown: one per paired PS5 with titles, or a placeholder while the titles load.
    ///
    /// - Parameters:
    ///   - state: The recently played titles.
    ///   - consoles: The paired consoles.
    ///   - continuing: The consoles whose card already shows their last title, which the row then skips.
    /// - Returns: The rows, in console order.
    nonisolated static func rows(
        _ state: RecentlyPlayedReducer.State,
        consoles: [RegistrationFlow.ConsoleTarget],
        continuing: Set<UUID> = []
    ) -> [Row] {
        consoles.compactMap { console in
            guard console.kind == .ps5, let id = console.id else {
                return nil
            }
            if let rail = state.rail(for: id) {
                let titles = continuing.contains(id)
                    ? Array(rail.titles.dropFirst())
                    : rail.titles
                return titles.isEmpty
                    ? nil
                    : Row(console: console, consoleID: id, titles: titles)
            }
            if state.showsPlaceholders {
                return Row(console: console, consoleID: id, titles: nil)
            }
            return nil
        }
    }

    var body: some View {
        let rows = Self.rows(recentlyPlayed, consoles: consoles, continuing: continuing)
        VStack(alignment: .leading, spacing: 28) {
            if recentlyPlayed.authExpired {
                Text(.libraryRecentSignInExpired)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            ForEach(rows) { row in
                RecentTitleRail(
                    heading: heading(row),
                    row: row,
                    disabled: busy || recentlyPlayed.launch != .idle,
                    play: play,
                    focus: $focus,
                    move: move
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: rows.map(\.id))
    }

    private func heading(_ row: Row) -> LocalizedStringResource {
        .libraryRecentHeading(console: StreamerMode.consoleName(
            row.console.name, address: row.console.address, kind: row.console.kind.rawValue,
            enabled: streamerMode
        ))
    }
}

private struct RecentTitleRail: View {
    struct Metrics: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0

        var maximumOffset: CGFloat {
            max(0, content - viewport)
        }
    }

    let heading: LocalizedStringResource
    let row: RecentlyPlayedSection.Row
    let disabled: Bool
    let play: (UUID, RecentTitle) -> Void
    @MenuFocusState.Binding var focus: ConsoleLibraryFocus?
    let move: (ConsoleLibraryFocus, MenuMoveDirection) -> Void
    @State private var position = ScrollPosition(idType: String.self)
    @State private var metrics = Metrics()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.recentTitleWidth) private var titleWidth
    @Environment(\.recentTitleGap) private var titleGap

    private var cardStride: CGFloat {
        titleWidth + titleGap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(heading)
                    .font(.title3.weight(.semibold))
                Spacer()
                if metrics.maximumOffset > 1 {
                    HStack(spacing: 8) {
                        pageButton(forward: false)
                        pageButton(forward: true)
                    }
                    .transition(.opacity)
                }
            }
            rail
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: metrics.maximumOffset > 1)
    }

    private var rail: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: titleGap) {
                if let titles = row.titles {
                    ForEach(titles) { title in
                        RecentTitleCard(
                            title: title,
                            consoleID: row.consoleID,
                            disabled: disabled,
                            play: play,
                            focus: $focus,
                            move: move
                        )
                        .id(title.titleID)
                    }
                } else {
                    ForEach(0 ..< 6, id: \.self) { _ in
                        RecentTitlePlaceholder()
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 8)
        }
        .scrollPosition($position)
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .mask {
            Rectangle()
                .padding(.horizontal, -12)
                .padding(.vertical, -40)
        }
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(
                offset: geometry.contentOffset.x,
                viewport: geometry.containerSize.width,
                content: geometry.contentSize.width
            )
        } action: { _, value in
            metrics = value
        }
        .onChange(of: focus) { _, target in
            guard case let .recentTitle(consoleID, titleID) = target, consoleID == row.consoleID else {
                return
            }
            withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                position.scrollTo(id: titleID, anchor: .center)
            }
        }
    }

    private func pageButton(forward: Bool) -> some View {
        Button {
            page(forward: forward)
        } label: {
            Label(
                forward
                    ? .libraryRailScrollForward
                    : .libraryRailScrollBack,
                systemImage: forward
                    ? "chevron.right"
                    : "chevron.left"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 16, height: 16)
        }
        .interactiveGrowth()
        .glassControlStyle()
        .buttonBorderShape(.circle)
        .menuFocusable(false)
        .focusEffectDisabled()
        .disabled(forward
            ? metrics.offset >= metrics.maximumOffset - 1
            : metrics.offset <= 1)
    }

    private func page(forward: Bool) {
        let step = max(metrics.viewport - cardStride, cardStride)
        let proposed = metrics.offset + (forward
            ? step
            : -step)
        let target = min(max(proposed, 0), metrics.maximumOffset)
        withAnimation(AppMotion.animation(reduced: reduceMotion)) {
            position.scrollTo(x: target)
        }
    }
}

private struct RecentTitleCard: View {
    let title: RecentTitle
    let consoleID: UUID
    let disabled: Bool
    let play: (UUID, RecentTitle) -> Void
    @MenuFocusState.Binding var focus: ConsoleLibraryFocus?
    let move: (ConsoleLibraryFocus, MenuMoveDirection) -> Void
    @State private var hovered = false
    @Environment(\.inputMode) private var inputMode
    @Environment(\.recentTitleWidth) private var titleWidth
    @Environment(\.trialMarks) private var trialMarks

    private var target: ConsoleLibraryFocus {
        .recentTitle(consoleID, title.titleID)
    }

    private var mark: CloudTrialMark? {
        trialMarks[title.titleID]
    }

    private var icon: AppIcon {
        mark?.icon ?? .release
    }

    private var spokenLabel: LocalizedStringResource {
        guard let mark else {
            return .libraryRecentPlay(title: title.name)
        }
        return .libraryRecentPlayMarked(title: title.name, mark: String(localized: mark.label).lowercased())
    }

    private var revealed: Bool {
        hovered || inputMode.shows(focus == target)
    }

    var body: some View {
        FocusButton {
            play(consoleID, title)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CloudArtworkView(url: .secureArtwork(title.imageURL))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12))
                    .containedFocusGlow(in: .roundedRectangle(12))
                    .overlay {
                        AppIcon.start.image
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .glassEffect(AppGlass.control, in: .circle)
                            .opacity(revealed
                                ? 1
                                : 0)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let mark {
                            CloudTrialBadge(icon: mark.icon, label: mark.label)
                        }
                    }
                ScrollingText(text: title.name, font: .system(size: 15, weight: .medium))
                if let lastPlayed = title.lastPlayed {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack(spacing: 6) {
                            icon.image
                                .font(.system(size: 13))
                            Text(lastPlayed.formatted(
                                .relative(presentation: .named).locale(.current)
                            ))
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .id(context.date)
                        }
                        .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        AppIcon.release.image
                            .font(.system(size: 13))
                        Text(verbatim: " ")
                            .font(.system(size: 13))
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
            }
            .frame(width: titleWidth, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.contained)
        .disabled(disabled)
        .menuFocused($focus, equals: target)
        .environment(\.menuMove) { direction in
            move(target, direction)
        }
        .onHover {
            hovered = $0
        }
        .animation(.easeOut(duration: 0.15), value: revealed)
        .accessibilityLabel(spokenLabel)
    }
}

private struct RecentTitlePlaceholder: View {
    @Environment(\.recentTitleWidth) private var titleWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.06))
                .aspectRatio(1, contentMode: .fit)
            Capsule()
                .fill(.white.opacity(0.06))
                .frame(width: 120, height: 14)
        }
        .frame(width: titleWidth, alignment: .leading)
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// The width of a recently played title card on the shelf.
    @Entry var recentTitleWidth: CGFloat = RecentTitleWidth.standard
    /// The gap between recently played title cards on the shelf.
    @Entry var recentTitleGap: CGFloat = RecentTitleWidth.gap
}

/// Sizes recently played title cards so the shelf fills the window's height and each row tiles evenly.
enum RecentTitleWidth {
    /// The default card width.
    static let standard: CGFloat = 168
    /// The widest a card grows.
    static let largest: CGFloat = 280
    /// Height kept free for the logo when growing cards to fill the window.
    static let logoRoom: CGFloat = 16
    /// The default gap between cards.
    static let gap: CGFloat = 20
    /// The widest gap allowed before a row adds another card instead.
    static let widestGap: CGFloat = 48

    /// The card width that grows the shelf to fill the window's height, snapped to tile the row evenly.
    ///
    /// - Parameters:
    /// - viewport: The visible height of the shelf.
    /// - content: The shelf's content height with cards at the current width.
    /// - current: The current card width.
    /// - row: The width of a rail, or zero when it is not known.
    /// - Returns: The standard width when nothing has been measured, otherwise a width from the standard up
    ///   to the largest, fitted to the row.
    static func fitting(viewport: CGFloat, content: CGFloat, current: CGFloat, row: CGFloat = 0) -> CGFloat {
        guard viewport > 0, content > 0 else {
            return filling(row: row, upTo: standard)
        }
        let natural = content - (current - standard)
        let grown = standard + (viewport - logoRoom - natural)
        return filling(row: row, upTo: min(largest, max(standard, grown.rounded(.down))))
    }

    /// The widest card width up to a limit that fills a row with whole cards and a gap no wider than
    /// ``RecentTitleWidth/widestGap``.
    ///
    /// - Parameters:
    /// - row: The width of a rail, or zero to return the limit unchanged.
    /// - width: The widest a card may be.
    static func filling(row: CGFloat, upTo width: CGFloat) -> CGFloat {
        guard row > 0, width > 0 else {
            return width
        }
        let nearest = max(1, ((row + gap) / (width + gap)).rounded())
        let card = min(width, ((row - gap * (nearest - 1)) / nearest).rounded(.down))
        if spacing(row: row, width: card) <= widestGap {
            return card
        }
        let count = max(1, ((row + gap) / (width + gap)).rounded(.up))
        return ((row - gap * (count - 1)) / count).rounded(.down)
    }

    /// The gap that spreads whole cards of a width across a row, or the default gap when that would be wider
    /// than ``RecentTitleWidth/widestGap`` or only one card fits.
    ///
    /// - Parameters:
    /// - row: The width of a rail, or zero for the default gap.
    /// - width: The card width.
    static func spacing(row: CGFloat, width: CGFloat) -> CGFloat {
        guard row > 0, width > 0 else {
            return gap
        }
        let count = max(1, ((row + gap) / (width + gap)).rounded(.down))
        guard count > 1 else {
            return gap
        }
        let spread = (row - count * width) / (count - 1)
        return spread <= widestGap
            ? spread
            : gap
    }
}

extension EnvironmentValues {
    /// The trial mark of each title the account holds only as a trial, by title id, which recently played
    /// cards show as a cover badge and in place of the clock.
    @Entry var trialMarks: [String: CloudTrialMark] = [:]
}
