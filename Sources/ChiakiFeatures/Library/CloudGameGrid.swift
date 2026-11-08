import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

/// Carries the library's controller focus binding into the grid, so its tiles and page bar share focus with
/// the rest of the library.
struct CloudFocusRelay {
    /// The library's focus binding.
    let binding: MenuFocusState<CloudLibraryFocus?>.Binding
}

/// The callbacks the grid uses to report to the library view and to ask it for focus moves and page turns.
struct CloudGridInteraction {
    /// Moves controller focus away from a game's tile in a direction.
    let move: @MainActor (String, MenuMoveDirection) -> Void
    /// Reports that a game's tile appeared, so focus waiting for that game can land on it.
    let appeared: (String) -> Void
    /// Reports the grid's leading edge and width in global coordinates.
    let measured: (CGFloat, CGFloat) -> Void
    /// Turns the page by a number of pages, negative to go back.
    let turn: (Int) -> Void
    /// Reports whether the pointer is over the grid.
    let hovered: (Bool) -> Void
    /// Reads the game whose position should be kept when the grid's shape changes.
    let kept: () -> String?
    /// Moves controller focus away from the page bar in a direction.
    let movePageBar: @MainActor (MenuMoveDirection) -> Void
}

/// The paged grid of cloud game tiles, which fits as many cards as the space allows, slides between pages and
/// shows the loading, empty and failure states in its place.
///
/// A regular window pages with the page bar and the arrows at its sides, which wait for the pointer on a Mac
/// and stay on show on touch. A compact window pages with a swipe on touch, the row following the finger with
/// the next page drawn beside it until it is let go, and a tappable strip of page dots
/// at its foot; a short one lays its cards out in one row, a tall one in the full grid.
struct CloudGameGrid: View {
    /// The space above the cards that leaves room for a focused tile to lift.
    static let liftRoom: CGFloat = 18
    /// The gap between the last row of cards and the page bar.
    static let pageBarGap: CGFloat = 26
    /// The height of the compact page dot strip, which is also its hit area.
    static let dotStripHeight: CGFloat = 44
    /// How far the compact dot strip hangs below the stage, into the margin and the home indicator's inset,
    /// so the dots sit clear of the captions and the cards keep the room above them.
    static let dotStripDrop: CGFloat = 24
    /// The curve the pages slide along when the page turns.
    static let slide = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.62)
    /// The cross-fade used when the page turns with Reduce Motion on.
    static let fade = Animation.easeInOut(duration: 0.25)
    /// The spring a dragged row settles back with when the swipe falls short of a page turn.
    static let settle = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// How far a swipe must travel to turn the page.
    static let swipeDistance: CGFloat = 56
    /// How much of a drag past the first or last page the row follows.
    static let overscroll: CGFloat = 0.3

    /// The page sliding out while the next page slides in.
    struct Leaving: Equatable {
        /// The games on the outgoing page.
        let games: [CloudGame]
        /// Whether the page turned forward, which slides the outgoing page to the left.
        let forward: Bool
    }

    /// The listing and page the grid shows, which tells a page turn apart from a new search or filter.
    struct Shown: Equatable {
        /// The search, filter and platform that produced the listing, joined into one key.
        let listing: String
        /// The page shown.
        let page: Int
    }

    /// The cloud library store that holds the listing, paging and checks.
    let store: StoreOf<CloudLibraryFeature>
    /// The signed-in account, or `nil` when none is chosen, which shows a prompt instead of games.
    let accountID: UUID?
    /// The library's controller focus shared with the grid.
    let focus: CloudFocusRelay
    /// The callbacks into the library view.
    let interaction: CloudGridInteraction
    @State private var fit = CloudGridMetrics.fit(.zero)
    @State private var leaving: Leaving?
    @State private var held: [CloudGame] = []
    @State private var progress: CGFloat = 1
    @State private var drag: CGFloat = 0
    @State private var measured = false
    @State private var pointerOver = false
    @State private var stageSize = CGSize.zero
    @State private var pageBarHeight: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.catalog) private var catalog
    @Environment(\.screenLayout) private var layout

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !reduceMotion, leaving == nil, Self.isSideways(value) || drag != 0 else {
                    return
                }
                let distance = value.translation.width
                let beyond = distance < 0
                    ? store.page + 1 >= store.pageCount
                    : store.page <= 0
                drag = beyond
                    ? distance * Self.overscroll
                    : distance
            }
            .onEnded { value in
                let distance = value.translation.width
                guard abs(distance) > Self.swipeDistance, Self.isSideways(value) else {
                    withAnimation(Self.settle) {
                        drag = 0
                    }
                    return
                }
                let before = store.page
                interaction.turn(distance < 0
                    ? 1
                    : -1)
                if store.page == before {
                    withAnimation(Self.settle) {
                        drag = 0
                    }
                }
            }
    }

    private static func isSideways(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > abs(value.translation.height) * 1.5
    }

    private var pageWidth: CGFloat {
        fit.contentSize.width + fit.columnGap
    }

    private var shown: Shown {
        Shown(listing: "\(store.query)|\(store.filter)|\(store.platform)", page: store.page)
    }

    var body: some View {
        stage
            .overlay(alignment: .bottom) {
                if layout.isCompact, measured, store.pageCount > 1, !store.visibleGames.isEmpty, !loading {
                    CloudPageDotStrip(
                        page: store.page, pageCount: store.pageCount, height: Self.dotStripHeight
                    ) { page in
                        interaction.turn(page - store.page)
                    }
                    .offset(y: Self.dotStripDrop)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if !layout.isCompact, measured {
                    CloudPageBar(
                        page: store.page, pageCount: store.pageCount, control: store.pageControl,
                        focus: focus.binding,
                        send: {
                            store.send(.pageControl($0))
                        },
                        move: interaction.movePageBar
                    )
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        pageBarHeight = height
                        refit()
                    }
                    .padding(.top, Self.liftRoom + fit.contentSize.height + Self.pageBarGap)
                }
            }
            .transition(AppMotion.transition(reduced: reduceMotion))
            .animation(AppMotion.animation(reduced: reduceMotion), value: loading)
    }

    private var stage: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                content
            }
            .onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { size in
                stageSize = size
                refit()
            }
            .onGeometryChange(for: [CGFloat].self) { geometry in
                let frame = geometry.frame(in: .global)
                return [frame.minX, frame.width]
            } action: { values in
                interaction.measured(values[0], values[1])
            }
            .overlay(alignment: .leading) {
                if !layout.isCompact {
                    arrow(forward: false)
                }
            }
            .overlay(alignment: .trailing) {
                if !layout.isCompact {
                    arrow(forward: true)
                }
            }
            .contentShape(.rect)
            .onHover { inside in
                pointerOver = inside
                interaction.hovered(inside)
            }
    }

    @ViewBuilder private var content: some View {
        if case .loading = store.phase {
            cloudLoading
        } else if accountID == nil {
            ContentUnavailableView(
                .libraryGridChooseAccount,
                systemImage: "person.crop.circle",
                description: Text(.libraryGridChooseAccountDetail)
            )
        } else if store.visibleGames.isEmpty, case .failed(let failure) = store.phase {
            unavailable(failure)
        } else if store.phase == .ready && store.visibleGames.isEmpty {
            ContentUnavailableView(
                .libraryGridNoMatches,
                systemImage: "magnifyingglass",
                description: Text(.libraryGridNoMatchesDetail)
            )
        } else if measured, fit.shape == store.gridShape {
            pages
        }
    }

    private var pages: some View {
        let width = pageWidth
        return ZStack(alignment: .topLeading) {
            if let leaving {
                page(leaving.games, live: false)
                    .modifier(PageSlide(
                        offset: (leaving.forward
                            ? -width
                            : width) * progress,
                        opacity: 1 - progress, reduceMotion: reduceMotion
                    ))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if drag < 0, !store.upcomingGames.isEmpty {
                page(store.upcomingGames, live: false)
                    .offset(x: width + drag)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else if drag > 0, !store.previousGames.isEmpty {
                page(store.previousGames, live: false)
                    .offset(x: drag - width)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            page(store.visibleGames, live: true)
                .modifier(PageSlide(
                    offset: (leaving.map { leaving in
                        (leaving.forward
                            ? width
                            : -width) * (1 - progress)
                    } ?? 0) + drag,
                    opacity: leaving == nil
                        ? 1
                        : progress,
                    reduceMotion: reduceMotion
                ))
        }
        .frame(width: fit.contentSize.width, height: fit.contentSize.height, alignment: .topLeading)
        .padding(.top, Self.liftRoom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .clipped()
        .padding(-16)
        .contentShape(.rect)
        .highPriorityGesture(pageSwipe, isEnabled: layout.touch)
        .onChange(of: shown, initial: true) { previous, current in
            turned(from: previous, to: current)
        }
        .task(id: CloudGridPrefetch(shown: shown, box: coverBox)) {
            guard let coverBox else {
                return
            }
            await catalog.prefetch(
                store.upcomingGames.compactMap { URL.secureArtwork($0.imageUrl) },
                coverBox
            )
        }
    }

    private func turned(from previous: Shown, to current: Shown) {
        let outgoing = held
        held = store.visibleGames
        guard previous.listing == current.listing, previous.page != current.page, !outgoing.isEmpty else {
            leaving = nil
            progress = 1
            drag = 0
            return
        }
        let forward = store.pageTurn == .forward
        leaving = Leaving(games: outgoing, forward: forward)
        let dragged = forward
            ? -drag
            : drag
        progress = pageWidth > 0
            ? min(1, max(0, dragged / pageWidth))
            : 0
        drag = 0
        withAnimation(reduceMotion
            ? Self.fade
            : Self.slide) {
                progress = 1
            } completion: {
                if progress == 1 {
                    leaving = nil
                }
            }
    }

    private func page(_ games: [CloudGame], live: Bool) -> some View {
        let columns = fit.shape.columns
        let rows = stride(from: 0, to: games.count, by: columns).map { start in
            Array(games[start..<min(start + columns, games.count)])
        }
        let selection = store.selection
        return VStack(alignment: .leading, spacing: CloudGridMetrics.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: fit.columnGap) {
                    ForEach(row) { game in
                        Group {
                            if live {
                                tile(game, selected: game.id == selection)
                            } else {
                                CloudGameCard(
                                    game: game,
                                    selected: false,
                                    active: false,
                                    lastPlayed: store.filter == .recent
                                        ? store.listing.lastPlayed(game)
                                        : nil,
                                    check: store.cardChecks[game.id]
                                )
                            }
                        }
                        .frame(width: fit.cardWidth, height: fit.cardHeight, alignment: .top)
                    }
                }
            }
        }
        .frame(width: fit.contentSize.width, height: fit.contentSize.height, alignment: .topLeading)
    }

    private func tile(_ game: CloudGame, selected: Bool) -> some View {
        CloudGameTile(
            game: game,
            selected: selected,
            lastPlayed: store.filter == .recent
                ? store.listing.lastPlayed(game)
                : nil,
            check: store.cardChecks[game.id],
            focus: focus.binding,
            select: {
                store.send(.select(game.id))
            },
            move: {
                interaction.move(game.id, $0)
            }
        )
        .id(game.id)
        .onAppear {
            interaction.appeared(game.id)
        }
        .accessibilityIdentifier("cloud-game-\(game.id)")
    }
}

extension CloudGameGrid {
    private var coverBox: ArtworkBox? {
        ArtworkBox(points: CGSize(width: fit.cardWidth, height: fit.coverHeight), scale: displayScale)
    }
    private var pageBarReserve: CGFloat {
        layout.isCompact
            ? Self.dotStripHeight - Self.dotStripDrop / 2
            : pageBarHeight + Self.pageBarGap
    }

    private func refit() {
        guard stageSize.width > 0, stageSize.height > 0 else {
            return
        }
        let area = CGSize(width: stageSize.width, height: stageSize.height - Self.liftRoom - pageBarReserve)
        let fitted = layout.isCompact && layout.isShort
            ? CloudGridMetrics.row(area)
            : CloudGridMetrics.fit(area)
        guard fitted != fit || !measured else {
            return
        }
        fit = fitted
        measured = true
        store.send(.gridShape(fit.shape, keeping: interaction.kept()))
    }
}

extension CloudGameGrid {
    private func arrow(forward: Bool) -> some View {
        let enabled = forward
            ? store.page + 1 < store.pageCount
            : store.page > 0
        return Button {
            interaction.turn(forward
                ? 1
                : -1)
        } label: {
            Label(
                forward
                    ? .libraryGridNextPage
                    : .libraryGridPreviousPage,
                systemImage: forward
                    ? "chevron.right"
                    : "chevron.left"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.11))
            .frame(width: 26, height: 26)
            .frame(minWidth: arrowSide, minHeight: arrowSide)
        }
        .interactiveGrowth()
        .glassProminentControlStyle()
        .buttonBorderShape(.circle)
        .menuFocusable(false)
        .focusEffectDisabled()
        .disabled(!enabled)
        .opacity(enabled
            ? 1
            : 0.25)
            .padding(.horizontal, 9)
            .opacity(arrowsShown
                ? 1
                : 0)
                .animation(.easeOut(duration: 0.15), value: pointerOver)
    }

    private var arrowSide: CGFloat {
        max(0, layout.controlSize - 18)
    }

    private var arrowsShown: Bool {
        Self.showsArrows(
            layout: layout, pointerOver: pointerOver, pageCount: store.pageCount,
            empty: store.visibleGames.isEmpty, loading: loading
        )
    }

    /// Whether the page arrows are on show: never with one page, nothing to page or while loading, otherwise
    /// under the pointer, and always on touch, where nothing hovers.
    ///
    /// - Parameters:
    ///   - layout: The screen's layout traits.
    ///   - pointerOver: Whether the pointer is over the grid.
    ///   - pageCount: The pages in the listing.
    ///   - empty: Whether the page shows no games.
    ///   - loading: Whether the library is loading.
    /// - Returns: `true` when the arrows are visible and can be pressed.
    static func showsArrows(
        layout: ScreenLayout, pointerOver: Bool, pageCount: Int, empty: Bool, loading: Bool
    ) -> Bool {
        guard pageCount > 1, !empty, !loading else {
            return false
        }
        return pointerOver || !layout.hoverAffordances
    }

    private var cloudLoading: some View {
        let progress = store.phase.fetchProgress
        return VStack(spacing: 18) {
            ChiakiLogo(size: 96, isConnecting: true)
            VStack(spacing: 6) {
                Text(progress?.step ?? .libraryGridLoading)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .id(progress?.stage)
                    .transition(AppMotion.transition(reduced: reduceMotion))
                if let detail = progress?.detail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let pages = progress?.pages {
                    Text(pages)
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .multilineTextAlignment(.center)
            .animation(AppMotion.animation(reduced: reduceMotion), value: progress?.stage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var loading: Bool {
        if case .loading = store.phase {
            return true
        }
        return false
    }

    private func unavailable(_ failure: CloudLibraryFailure) -> some View {
        let message: LocalizedStringResource
        switch failure {
        case .unavailable:
            message = .libraryGridUnavailableCore
        case .signInRequired:
            message = .libraryGridUnavailableSignIn
        case .invalidCatalog:
            message = .libraryGridUnavailableCatalog
        case .network:
            message = .libraryGridUnavailableNetwork
        }
        return ContentUnavailableView(.libraryGridUnavailableTitle, systemImage: "cloud",
                                      description: Text(message))
    }
}

private struct PageSlide: ViewModifier {
    let offset: CGFloat
    let opacity: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(opacity)
        } else {
            content.offset(x: offset)
        }
    }
}

/// The covers the cloud grid prefetches for its next page: one request for each page of a listing and each
/// cover size, so a new page, listing or size starts the prefetch again.
private struct CloudGridPrefetch: Hashable {
    /// The search, filter and platform of the listing.
    let listing: String

    /// The page shown.
    let page: Int

    /// The size covers are drawn at, or `nil` before the grid is measured.
    let box: ArtworkBox?

    /// Creates the request for the page the grid shows.
    ///
    /// - Parameters:
    ///   - shown: The listing and page the grid shows.
    ///   - box: The size covers are drawn at.
    init(shown: CloudGameGrid.Shown, box: ArtworkBox?) {
        listing = shown.listing
        page = shown.page
        self.box = box
    }
}
