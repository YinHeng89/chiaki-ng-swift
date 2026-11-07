import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The console shelf of a regular window: the heading, the status lines, the console grid and the recently
/// played rows, in one scroll view.
struct ConsoleShelfView: View {
    /// The library.
    let store: StoreOf<LibraryFeature>
    /// What the shelf shows.
    let shelf: LibraryShelf
    /// The shelf's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// The measured width of the console grid.
    @Binding var gridWidth: CGFloat
    /// Applies a focus move.
    let apply: (ConsoleShelfFocusGraph.Move) -> Void
    /// Plays a recently played title.
    let playTitle: (UUID, RecentTitle) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cloudLibraryHeight) private var cloudHeight
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var recentTitleWidth = RecentTitleWidth.standard
    @State private var visibleConsoles: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heading
                AccountStatusBanner(store: store, graph: shelf.graph, focus: focus, apply: apply)
                connections
                if store.selectedProfile != nil {
                    RecentlyPlayedSection(
                        recentlyPlayed: store.recentlyPlayed,
                        consoles: store.linkedConsoles,
                        continuing: shelf.plan.continuing,
                        busy: store.consolesBusy,
                        play: playTitle,
                        focus: focus,
                        move: { current, direction in
                            apply(shelf.graph.moveRecent(from: current, direction))
                        }
                    )
                    .padding(.top, 8)
                    .environment(\.trialMarks, store.shelfTrialMarks)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                rowWidth = width
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            viewportHeight = height
        }
        .onChange(of: [viewportHeight, contentHeight, rowWidth]) { _, _ in
            resizeRecentTitles()
        }
        .environment(\.recentTitleWidth, recentTitleWidth)
        .environment(\.recentTitleGap, RecentTitleWidth.spacing(row: rowWidth, width: recentTitleWidth))
        .padding(.horizontal, -28)
        .appVerticalScrollStyle()
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 20) {
            Text(.libraryShelfTitle)
                .font(.system(size: 40, weight: .semibold))
            if store.selectedProfile != nil, !shelf.consoles.isEmpty {
                AddConsoleButton(style: .pill) {
                    store.send(.requested(.addConsole))
                }
                .menuFocused(focus, equals: .addConsole)
                .environment(\.menuMove) { direction in
                    apply(shelf.graph.moveConsole(from: .addConsole, direction))
                }
            }
            Spacer(minLength: 0)
            LibraryMenuHint(section: .consoles)
        }
    }

    @ViewBuilder private var connections: some View {
        if shelf.waiting, shelf.consoles.isEmpty {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(.libraryShelfLoadingConsoles)
        } else if let account = store.selectedProfile {
            Group {
                if shelf.consoles.isEmpty {
                    EmptyConsoleShelf(
                        artHeight: 350,
                        compactArtHeight: 220,
                        minHeight: max(440, cloudHeight - 160)
                    ) {
                        addConsole
                    }
                } else {
                    ConsoleGridLayout {
                        ForEach(shelf.consoles, id: \.self) { item in
                            LibraryConsoleCard(
                                store: store,
                                item: item,
                                shelf: shelf,
                                focus: focus,
                                apply: apply,
                                playTitle: playTitle
                            )
                            .onScrollVisibilityChange(threshold: 0.3) { visible in
                                noteVisibility(of: item, visible)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        gridWidth = width
                    }
                    .onChange(of: artRequests, initial: true) { _, requests in
                        store.send(.requested(.showConsoleArt(requests)))
                    }
                    .onDisappear {
                        store.send(.requested(.showConsoleArt([])))
                    }
                }
            }
            .id(account.id)
            .transition(AppMotion.transition(reduced: reduceMotion))
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.selectedAccount)
        } else {
            FocusButton(.libraryShelfAddAccount) {
                store.send(.requested(.addAccount))
            }
            .glassControlStyle()
            .menuFocused(focus, equals: .addAccount)
            .environment(\.menuMove) { direction in
                apply(.leave(direction))
            }
        }
    }

    private var addConsole: some View {
        AddConsoleButton(style: .prominent) {
            store.send(.requested(.addConsole))
        }
        .padding(.top, 10)
        .menuFocused(focus, equals: .addConsole)
        .environment(\.menuMove) { direction in
            apply(shelf.graph.moveConsole(from: .addConsole, direction))
        }
    }

    private var artRequests: [ConsoleArtRequest] {
        shelf.plan.artRequests(account: store.selectedAccount, visible: visibleConsoles)
    }

    private func noteVisibility(of item: DisplayedConsole, _ visible: Bool) {
        guard !item.preview, let id = item.target.id else {
            return
        }
        if visible {
            visibleConsoles.insert(id)
        } else {
            visibleConsoles.remove(id)
        }
    }

    private func resizeRecentTitles() {
        let fitted = RecentTitleWidth.fitting(
            viewport: viewportHeight,
            content: contentHeight,
            current: recentTitleWidth,
            row: rowWidth
        )
        if abs(fitted - recentTitleWidth) >= 2 {
            recentTitleWidth = fitted
        }
    }
}

extension LibraryFeature.State {
    /// The trial marks the console shelf's recently played rails show: the cloud library's once it has loaded
    /// for the selected account, since they follow every change, and otherwise the ones the rails read from what
    /// the core already holds.
    var shelfTrialMarks: [String: CloudTrialMark] {
        guard cloudLibrary.snapshot != nil, cloudLibrary.accountID == selectedAccount else {
            return recentlyPlayed.trialMarks
        }
        return cloudLibrary.listing.trialMarks
    }
}

/// The console shelf of a compact window: the status lines and the console cards, with the recently played
/// row of one console when there is room for it.
///
/// A short screen, such as a phone in landscape, pages short cards in one row above the recently played
/// titles, which fill the rest of the height, or stretches the cards to the height when nothing was played.
/// A tall compact screen, such as an iPad in Split View, stacks the cards in one full-width column with the
/// recently played row below, and scrolls.
struct CompactConsoleShelfView: View {
    /// The space above and below the shelf.
    static let insets = EdgeInsets(top: CompactLibraryBarMetrics.gap, leading: 0, bottom: 12, trailing: 0)
    /// The height of a stacked compact card, which keeps its console art on show.
    static let cardHeight: CGFloat = 230
    /// The smallest edge of a recently played tile.
    static let shortTile: CGFloat = 72
    /// The largest edge of a recently played tile.
    static let tallTile: CGFloat = 96
    /// The height the recently played row needs beyond its tiles, for the caption and the names.
    static let recentChrome: CGFloat = 60

    /// The library.
    let store: StoreOf<LibraryFeature>
    /// What the shelf shows.
    let shelf: LibraryShelf
    /// The shelf's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// The width of one card, which the continue plan sizes its titles by.
    @Binding var gridWidth: CGFloat
    /// Applies a focus move.
    let apply: (ConsoleShelfFocusGraph.Move) -> Void
    /// Plays a recently played title.
    let playTitle: (UUID, RecentTitle) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.screenLayout) private var layout
    @AppStorage(DeveloperPreviewSetting.layeredConsoleCards) private var showsLayeredConsoleCards = true
    @State private var visibleConsoles: Set<UUID> = []
    @State private var columnWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: CompactLibraryBarMetrics.gap) {
            AccountStatusBanner(store: store, graph: shelf.graph, focus: focus, apply: apply)
            connections
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, Self.insets.top)
        .padding(.bottom, Self.insets.bottom)
    }

    private var recentRow: RecentlyPlayedSection.Row? {
        shelf.recentRows.first { $0.consoleID == shelf.graph.recentOrigin } ?? shelf.recentRows.first
    }

    @ViewBuilder private var connections: some View {
        if shelf.waiting, shelf.consoles.isEmpty {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(.libraryShelfLoadingConsoles)
        } else if let account = store.selectedProfile {
            Group {
                if shelf.consoles.isEmpty {
                    emptyShelf
                } else if layout.isShort {
                    shortShelf
                } else {
                    stackedShelf
                }
            }
            .id(account.id)
            .transition(AppMotion.transition(reduced: reduceMotion))
            .animation(AppMotion.animation(reduced: reduceMotion), value: store.selectedAccount)
        } else {
            FocusButton(.libraryShelfAddAccount) {
                store.send(.requested(.addAccount))
            }
            .glassControlStyle()
            .menuFocused(focus, equals: .addAccount)
        }
    }

    private var shortShelf: some View {
        GeometryReader { proxy in
            if let row = recentRow, let titles = row.titles {
                VStack(alignment: .leading, spacing: CompactLibraryBarMetrics.gap) {
                    pagedRow(card: CGSize(
                        width: cardWidth(in: proxy.size.width),
                        height: ConsoleCard.compactShortHeight
                    ))
                    recent(row, titles: titles, tile: recentTile(in: proxy.size.height))
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                pagedRow(card: CGSize(
                    width: cardWidth(in: proxy.size.width),
                    height: max(
                        ConsoleCard.compactTallest / 2,
                        min(ConsoleCard.compactTallest, proxy.size.height)
                    )
                ))
            }
        }
    }

    private var artOverhang: CGFloat {
        showsLayeredConsoleCards
            ? ConsoleCard.compactArtOverhang
            : 0
    }

    private func cardWidth(in available: CGFloat) -> CGFloat {
        let paired = (available - CompactLibraryBarMetrics.gap - artOverhang) / 2
        return min(ConsoleCard.compactWidest, max(ConsoleCard.compactNarrowest, paired))
    }

    private func recentTile(in height: CGFloat) -> CGFloat {
        let room = height - ConsoleCard.compactShortHeight - CompactLibraryBarMetrics.gap - Self.recentChrome
        return min(Self.tallTile, max(Self.shortTile, room))
    }

    private var stackedShelf: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: CompactLibraryBarMetrics.gap) {
                ForEach(shelf.consoles, id: \.self) { item in
                    card(item, size: CGSize(width: max(1, columnWidth), height: Self.cardHeight))
                }
                if let row = recentRow, let titles = row.titles {
                    recent(row, titles: titles, tile: Self.tallTile)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onChange(of: artRequests, initial: true) { _, requests in
                store.send(.requested(.showConsoleArt(requests)))
            }
            .onDisappear {
                store.send(.requested(.showConsoleArt([])))
            }
        }
        .scrollIndicators(.never)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            columnWidth = width
            gridWidth = width
        }
    }

    private func recent(_ row: RecentlyPlayedSection.Row, titles: [RecentTitle], tile: CGFloat) -> some View {
        CompactRecentRow(
            caption: .libraryRecentHeading(console: row.console.name ?? row.console.address),
            warning: store.recentlyPlayed.authExpired
                ? .libraryRecentSignInExpired
                : nil,
            consoleID: row.consoleID,
            titles: titles,
            tile: tile,
            disabled: store.consolesBusy || store.recentlyPlayed.launch != .idle,
            play: playTitle,
            focus: focus,
            move: { current, direction in
                apply(shelf.graph.moveRecent(from: current, direction))
            }
        )
    }

    private func pagedRow(card: CGSize) -> some View {
        let short = card.height < ConsoleCard.compactTallest / 2
        return ScrollView(.horizontal) {
            HStack(spacing: CompactLibraryBarMetrics.gap) {
                ForEach(shelf.consoles, id: \.self) { item in
                    self.card(item, size: card)
                }
            }
            .scrollTargetLayout()
            .padding(
                .top,
                short && showsLayeredConsoleCards
                    ? ConsoleCard.compactArtRise
                    : 0
            )
        }
        .contentMargins(
            .leading,
            short
                ? artOverhang
                : 0,
            for: .scrollContent
        )
        .scrollTargetBehavior(.viewAligned)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollIndicators(.never)
        .onAppear {
            gridWidth = card.width
        }
        .onChange(of: artRequests, initial: true) { _, requests in
            store.send(.requested(.showConsoleArt(requests)))
        }
        .onDisappear {
            store.send(.requested(.showConsoleArt([])))
        }
    }

    private func card(_ item: DisplayedConsole, size: CGSize) -> some View {
        LibraryConsoleCard(
            store: store,
            item: item,
            shelf: shelf,
            focus: focus,
            apply: apply,
            playTitle: playTitle,
            compactSize: size
        )
        .onScrollVisibilityChange(threshold: 0.3) { visible in
            noteVisibility(of: item, visible)
        }
    }

    private var artRequests: [ConsoleArtRequest] {
        shelf.plan.artRequests(account: store.selectedAccount, visible: visibleConsoles)
    }

    private var emptyShelf: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 44) {
                ConsoleArtwork(height: layout.isShort
                    ? 140
                    : 200)
                invitation
            }
            invitation
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(.libraryShelfPairFirstConsole)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .lineLimit(2)
            AddConsoleButton(style: .prominent) {
                store.send(.requested(.addConsole))
            }
            .menuFocused(focus, equals: .addConsole)
            .environment(\.menuMove) { direction in
                apply(shelf.graph.moveConsole(from: .addConsole, direction))
            }
        }
        .frame(width: 300, alignment: .leading)
    }

    private func noteVisibility(of item: DisplayedConsole, _ visible: Bool) {
        guard !item.preview, let id = item.target.id else {
            return
        }
        if visible {
            visibleConsoles.insert(id)
        } else {
            visibleConsoles.remove(id)
        }
    }
}

/// A compact horizontal rail of a console's recently played titles, with a caption above and a name under
/// each tile.
///
/// Tiles are a fixed size, so the shelf can tell whether the row fits before it shows it; focusing a tile
/// scrolls it to the centre.
private struct CompactRecentRow: View {
    /// The height of the caption line above the rail.
    static let captionHeight: CGFloat = 18
    /// The vertical gap between the caption and the rail.
    static let captionGap: CGFloat = 8
    /// The height of the title name under each tile.
    static let nameHeight: CGFloat = 18

    /// The caption shown above the rail when there is no warning.
    let caption: LocalizedStringResource
    /// A warning shown in red in place of the caption.
    let warning: LocalizedStringResource?
    /// The console whose titles the rail shows.
    let consoleID: UUID
    /// The recently played titles, in rail order.
    let titles: [RecentTitle]
    /// The edge of each tile's art.
    let tile: CGFloat
    /// Whether the tiles are disabled.
    let disabled: Bool
    /// Starts the given title on the given console.
    let play: (UUID, RecentTitle) -> Void
    /// The shelf's controller focus, bound to the tiles.
    @MenuFocusState.Binding var focus: ConsoleLibraryFocus?
    /// Moves controller focus out of a tile in a direction.
    let move: (ConsoleLibraryFocus, MenuMoveDirection) -> Void
    @State private var position = ScrollPosition(idType: String.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Self.captionGap) {
            Text(warning ?? caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    warning == nil
                        ? Color.secondary
                        : Color.red
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: Self.captionHeight)
            rail
        }
    }

    private var rail: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: CompactLibraryBarMetrics.gap) {
                ForEach(titles) { title in
                    self.tile(title)
                        .id(title.titleID)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollIndicators(.never)
        .onChange(of: focus) { _, target in
            guard case let .recentTitle(console, titleID) = target, console == consoleID else {
                return
            }
            withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                position.scrollTo(id: titleID, anchor: .center)
            }
        }
    }

    private func tile(_ title: RecentTitle) -> some View {
        let target = ConsoleLibraryFocus.recentTitle(consoleID, title.titleID)
        return FocusButton {
            play(consoleID, title)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                CloudArtworkView(url: .secureArtwork(title.imageURL))
                    .frame(width: tile, height: tile)
                    .clipShape(.rect(cornerRadius: 12))
                    .containedFocusGlow(in: .roundedRectangle(12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(CompactRim.color, lineWidth: CompactRim.width)
                    }
                Text(title.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: tile, height: Self.nameHeight, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.contained)
        .disabled(disabled)
        .menuFocused($focus, equals: target)
        .environment(\.menuMove) { direction in
            move(target, direction)
        }
        .accessibilityLabel(.libraryRecentPlay(title: title.name))
    }
}

/// The shelf of an account with no paired console: the console artwork beside an invitation to pair one.
private struct EmptyConsoleShelf<AddConsole: View>: View {
    /// The artwork's height when it sits beside the text.
    let artHeight: CGFloat
    /// The artwork's height when it sits above the text.
    let compactArtHeight: CGFloat
    /// The shelf's least height.
    let minHeight: CGFloat
    /// The Add console button.
    @ViewBuilder public let addConsole: AddConsole

    /// Creates an empty console shelf.
    ///
    /// - Parameters:
    ///   - artHeight: The artwork's height when it sits beside the text.
    ///   - compactArtHeight: The artwork's height when it sits above the text.
    ///   - minHeight: The shelf's least height.
    ///   - addConsole: The Add console button.
    init(
        artHeight: CGFloat,
        compactArtHeight: CGFloat,
        minHeight: CGFloat,
        @ViewBuilder addConsole: () -> AddConsole
    ) {
        self.artHeight = artHeight
        self.compactArtHeight = compactArtHeight
        self.minHeight = minHeight
        self.addConsole = addConsole()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 64) {
                ConsoleArtwork(height: artHeight)
                invitation.fixedSize()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            VStack(spacing: 28) {
                ConsoleArtwork(height: compactArtHeight)
                invitation
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(.libraryShelfPairFirstConsole)
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
            addConsole
        }
        .frame(maxWidth: 390, alignment: .leading)
    }
}

/// The shelf's Add console button.
private struct AddConsoleButton: View {
    /// How the button is drawn.
    enum Style {
        /// The accent-filled button of an empty shelf.
        case prominent
        /// The quiet pill beside the shelf's heading.
        case pill
    }

    /// How the button is drawn.
    let style: Style
    /// Asks to pair a console.
    let action: () -> Void

    /// Creates an add console button.
    ///
    /// - Parameters:
    ///   - style: How the button is drawn.
    ///   - action: Asks to pair a console.
    init(style: Style, action: @escaping () -> Void) {
        self.style = style
        self.action = action
    }

    var body: some View {
        switch style {
        case .prominent:
            FocusButton(action: action) {
                Label(.libraryShelfAddConsole, systemImage: AppIcon.add.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .glassProminentControlStyle()
            .focusBorderShape(.capsule)
            .tint(Palette.accent)
            .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.13))
            .controlSize(.large)
        case .pill:
            FocusButton(action: action) {
                Label(.libraryShelfAddConsole, systemImage: AppIcon.add.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 4)
            }
            .glassControlStyle()
            .tint(.clear)
            .focusBorderShape(.capsule)
            .foregroundStyle(.secondary)
        }
    }
}

/// The status lines above the shelf: a sign-in or refresh problem with its button, and progress of a refresh
/// or an account removal.
private struct AccountStatusBanner: View {
    /// The library.
    let store: StoreOf<LibraryFeature>
    /// Where each direction moves focus.
    let graph: ConsoleShelfFocusGraph
    /// The shelf's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// Applies a focus move.
    let apply: (ConsoleShelfFocusGraph.Move) -> Void

    var body: some View {
        if let account = store.selectedProfile, store.needsSignIn {
            HStack(spacing: 16) {
                Text(.libraryStatusSignInAgain).foregroundStyle(.secondary)
                FocusButton(.libraryStatusSignIn) {
                    store.send(.requested(.reconnectAccount(account.id)))
                }
                .glassControlStyle()
                .modifier(actionFocus)
            }
            .font(.callout)
        } else if store.activity.refresh == .failed {
            HStack(spacing: 16) {
                Text(.libraryStatusRefreshFailed).foregroundStyle(.secondary)
                FocusButton(.libraryStatusRetry) {
                    store.send(.requested(.refreshAccounts))
                    apply(.firstConsole)
                }
                .glassControlStyle()
                .modifier(actionFocus)
            }
            .font(.callout)
        }
        if store.isRefreshing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text(.libraryStatusUpdating).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        switch store.activity.removal {
        case .removing:
            Text(.libraryStatusRemoving).font(.caption).foregroundStyle(.secondary)
        case .failed:
            Text(.libraryStatusRemoveFailed).font(.caption).foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var actionFocus: StatusActionFocus {
        StatusActionFocus(focus: focus) { direction in
            apply(graph.moveStatusAction(direction))
        }
    }
}

/// Makes a status line's button the shelf's status stop and routes its directions.
private struct StatusActionFocus: ViewModifier {
    /// The shelf's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// Moves focus away from the button.
    let move: (MenuMoveDirection) -> Void

    /// Binds the content to the status focus stop and forwards its moves to ``StatusActionFocus/move``.
    func body(content: Content) -> some View {
        content
            .menuFocused(focus, equals: .statusAction)
            .environment(\.menuMove) { direction in
                move(direction)
            }
    }
}

/// One console card on the shelf, wired to the library: its presence, its last title and art, and the
/// requests its buttons send.
private struct LibraryConsoleCard: View {
    /// The library.
    let store: StoreOf<LibraryFeature>
    /// The card's console.
    let item: DisplayedConsole
    /// What the shelf shows.
    let shelf: LibraryShelf
    /// The shelf's focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding
    /// Applies a focus move.
    let apply: (ConsoleShelfFocusGraph.Move) -> Void
    /// Plays a recently played title.
    let playTitle: (UUID, RecentTitle) -> Void
    /// The card's size in the compact shelf.
    var compactSize = ConsoleCard.compactSize
    @Environment(\.sampleArtStudio) private var sampleArt

    var body: some View {
        let console = item.target
        ConsoleCard(
            item: item,
            console: console,
            accountName: store.selectedProfile?.name ?? "",
            busy: store.consolesBusy,
            presence: presence,
            lastPlayed: shelf.plan.title(for: item),
            art: shelf.plan.face(for: item, art: store.consoleArt, samples: sampleArt).layers,
            resume: {
                if let id = console.id, let title = store.state.lastPlayed(on: id) {
                    playTitle(id, title)
                }
            },
            startLocal: {
                start(.local)
            },
            startRemote: {
                start(.remote)
            },
            edit: {
                edit()
            },
            delete: {
                if !item.preview, let id = console.id {
                    store.send(.requested(.deleteConsole(id)))
                }
            },
            focus: focus,
            moveConsole: { direction in
                apply(shelf.graph.moveConsole(from: .console(item), direction))
            },
            moveContinue: { direction in
                apply(shelf.graph.moveConsole(from: .action(item, .resume), direction))
            },
            compactSize: compactSize
        )
    }

    private var presence: ConsolePresence {
        guard !item.preview else {
            return .unknown
        }
        return ConsolePresence.of(
            item.target,
            in: store.discovery.snapshot,
            searched: store.discovery.hasSearched
        )
    }

    private func start(_ route: PlaybackRoute) {
        guard !item.preview else {
            return
        }
        store.send(.requested(.startConsole(item.target, route)))
    }

    private func edit() {
        let console = item.target
        guard !item.preview, let id = console.id else {
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
