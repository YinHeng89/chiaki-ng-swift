import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import SwiftUI

extension CloudGameDetail {
    /// The card detail, shown while a game has no layered art: cover beside a scrolling column on a short
    /// compact screen, or text over the cover on a glass panel otherwise.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The card with its Close button and focus handling.
    @ViewBuilder
    func details(_ game: CloudGame) -> some View {
        if cardIsWide {
            detailChrome(game, wideDetails(game))
        } else {
            detailChrome(game, tallDetails(game))
        }
    }

    /// The short compact layout: the cover on the left and a scrolling column of name, metadata, countdown
    /// and actions on the right.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The card's content without its chrome.
    func wideDetails(_ game: CloudGame) -> some View {
        HStack(spacing: 0) {
            artwork(game.imageUrl)
                .frame(width: detailHeight(game) * CloudGridMetrics.coverAspect)
                .clipped()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(game.name)
                            .font(.system(size: 22, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .padding(.trailing, 56)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        metadata(game.platform.uppercased(), icon: .console)
                        metadata(entitlement(game), icon: entitlementIcon(game),
                                 highlighted: game.isInCatalog)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 12) {
                        releaseCountdown(game)
                        detailActions(game)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .frame(minHeight: columnHeight, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                columnHeight = height
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.black.opacity(0.18))
        }
    }

    /// The tall layout: the full cover with the name, metadata, countdown and actions on a glass panel at its
    /// foot.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The card's content without its chrome.
    func tallDetails(_ game: CloudGame) -> some View {
        ZStack(alignment: .bottom) {
            artwork(game.imageUrl)
            LinearGradient(
                colors: [.clear, .black.opacity(0.16), .black.opacity(0.52)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 16) {
                Text(game.name)
                    .font(.system(size: 32, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metadata(game.platform.uppercased(), icon: .console)
                metadata(entitlement(game), icon: entitlementIcon(game),
                         highlighted: game.isInCatalog)
                releaseCountdown(game)
                detailActions(game)
            }
            .padding(22)
            .glassPanel(.medium)
            .overlay {
                RoundedRectangle(cornerRadius: GlassPanel.Radius.medium.points)
                    .strokeBorder(.white.opacity(0.18)) }
            .padding(14)
        }
    }

    /// Wraps a card layout with the Close button, rounded corners and the detail's focus section, focusing
    /// the first action on appearance and following focus as the actions change.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - content: The card layout to wrap.
    /// - Returns: The finished card.
    func detailChrome(_ game: CloudGame, _ content: some View) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                detailCloseButton
            }
            .clipShape(.rect(cornerRadius: 24))
            .environment(\.menuMove, { moveDetails(game, direction: $0) })
            .menuFocusSection()
            .onAppear {
                let items = detailFocusItems(game)
                let held = heldFocus().flatMap { item in
                    item != .close && items.contains(item)
                        ? item
                        : nil
                }
                focusDetail(game, held ?? detailInitialFocus(game))
            }
            .onChange(of: detailFocusItems(game)) { previous, items in
                detailFocusItemsChanged(game, from: previous, to: items)
            }
    }
    /// Keeps focus valid when the detail's actions change.
    ///
    /// Focus moves to Play when it appears while focus is unset, on Close or on the old first action; returns
    /// to the
    /// initial control when the focused control disappears; and steps from Add to library to Refresh when
    /// Refresh appears.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - previous: The focus order before the change.
    ///   - items: The focus order after the change.
    func detailFocusItemsChanged(_ game: CloudGame, from previous: [FocusItem], to items: [FocusItem]) {
        let fallback = previous.first { item in
            if case .media = item {
                return false
            }
            return item != .close
        }
        if items.contains(.play), !previous.contains(.play),
           focus == nil || focus == .close || focus == fallback {
            focusDetail(game, .play)
        } else if let focus, !items.contains(focus) {
            self.focus = detailInitialFocus(game)
        } else if focus == .addToLibrary, items.contains(.refreshTitle),
                  !previous.contains(.refreshTitle) {
            Task { @MainActor in
                await Task.yield()
                focus = .refreshTitle
            }
        }
    }
    /// The round glass Close button in the corner, which closes the detail and answers the Cancel shortcut,
    /// sized for a finger on touch.
    @ViewBuilder var detailCloseButton: some View {
        if !closesFromRail {
            FocusButton {
                closeDetail()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .menuFocused($focus, equals: .close)
            .accessibilityIdentifier("cloud-close")
            .glassControlStyle().focusBorderShape(.circle).keyboardShortcut(.cancelAction)
            .padding(16)
        }
    }
    /// Validates a store page address from the catalog.
    ///
    /// - Parameter raw: The address the catalog gave.
    /// - Returns: The address when it is a secure PlayStation Store page; `nil` otherwise.
    func storeURL(_ raw: String?) -> URL? {
        CloudGameActions.storeURL(raw)
    }
}

extension CloudGameDetail {
    /// The game's release countdown, hidden once the game is released.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The countdown line.
    func releaseCountdown(_ game: CloudGame) -> some View {
        CloudReleaseCountdown(release: game.release)
    }
    /// The prominent play button, which opens the bundle picker or runs the launch checks and plays, and is
    /// disabled when the game cannot be played.
    ///
    /// - Parameters:
    ///   - game: The game the button plays.
    ///   - play: The button's offer, title and enabled state.
    /// - Returns: The focusable play button.
    func playButton(_ game: CloudGame, _ play: CloudGameActions.PlayButton) -> some View {
        FocusButton {
            switch play.offer {
            case .chooseGame:
                store.send(.openBundlePicker(game.id))
            case .checkAndPlay(let request):
                store.send(.checkAndPlay(request))
            case nil:
                break
            }
        } label: {
            Label(play.title, systemImage: AppIcon.start.rawValue)
                .font(.system(size: actionTitleSize, weight: .semibold)).frame(maxWidth: .infinity)
        }.glassProminentControlStyle().focusBorderShape(.capsule).controlSize(.large)
            .disabled(!play.isEnabled)
            .menuFocused($focus, equals: .play)
            .accessibilityIdentifier("cloud-play")
    }
    /// The detail's actions: the bundle picker or the play and store buttons, the launch checks and their
    /// reason, the add to library controls and the title notice, as the game's actions allow.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The stacked actions.
    @ViewBuilder func detailActions(_ game: CloudGame) -> some View {
        let actions = actions(game)
        if actions.bundleChoices != nil {
            bundlePicker
        } else if let play = actions.play {
            HStack(spacing: 12) {
                playButton(game, play)
                if let link = actions.store, actions.purchaseCode == nil {
                    storeButton(link, game)
                }
            }
        } else if let link = actions.store, actions.purchaseCode == nil {
            storeButton(link, game)
        }
        if actions.showsLaunchChecks {
            launchSteps(game)
            cardCheckReason(game)
        }
        if let code = actions.purchaseCode {
            if let link = actions.store {
                storeTileHint(link, code, game, owned: actions.play != nil)
            } else {
                purchaseHint(code, owned: actions.play != nil)
            }
        }
        if actions.addToLibrary != nil {
            addToLibraryButton(game)
            refreshTitleButton(game)
            libraryAddHint(actions.addToLibrary)
        }
        if actions.showsTitleNotice {
            titleNotice(game)
        }
        if let version = actions.otherVersion {
            otherVersionButton(version)
        }
    }
    /// A glass button that opens the detail of the game's other generation's version, keeping focus on the
    /// same button there so a second press switches back.
    ///
    /// - Parameter version: The other version and the button's title.
    /// - Returns: The focusable version button.
    func otherVersionButton(_ version: CloudGameActions.VersionSwitch) -> some View {
        FocusButton {
            pendingFocus = .otherVersion
            store.send(.select(version.productId))
        } label: {
            Label(version.title, systemImage: "arrow.left.arrow.right")
                .font(.system(size: 17, weight: .semibold))
        }
        .glassControlStyle()
        .focusBorderShape(.capsule)
        .controlSize(.large)
        .menuFocused($focus, equals: .otherVersion)
        .accessibilityIdentifier("cloud-other-version")
    }
    /// The launch check steps, shown while checks run for this game.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The step row, or nothing when no checks run for the game.
    @ViewBuilder func launchSteps(_ game: CloudGame) -> some View {
        if let checks = store.launchChecks, checks.gameID == game.id {
            CloudLaunchStepRow(checks: checks)
                .transition(.opacity)
        }
    }
    /// The store page check's explanation, with an hourglass while it runs.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The reason, or nothing when the game streams or was not checked.
    @ViewBuilder func cardCheckReason(_ game: CloudGame) -> some View {
        if let reason = store.cardChecks[game.id].flatMap(CloudCardCheckMessage.text(for:)) {
            Label(
                reason,
                systemImage: store.cardChecks[game.id] == .checking
                    ? "hourglass"
                    : "info.circle"
            )
            .font(.callout).foregroundStyle(.white.opacity(0.85))
        }
    }
    /// A glass button that opens the game's store page.
    ///
    /// - Parameters:
    ///   - link: The button's title and fallback page.
    ///   - game: The game whose store page opens.
    /// - Returns: The focusable store button.
    func storeButton(_ link: CloudGameActions.StoreLink, _ game: CloudGame) -> some View {
        FocusButton {
            store.send(.storePageTapped(game.id))
        } label: {
            StoreButtonLabel(title: link.title, opening: store.storeOpening.contains(game.id))
                .font(.system(size: actionTitleSize, weight: .semibold))
        }
        .glassControlStyle()
        .focusBorderShape(.capsule)
        .controlSize(.large)
        .menuFocused($focus, equals: .store)
        .onMenuMoveCommand { moveDetails(game, direction: $0) }
    }
    /// The hint telling the player to add the game in the PS Store and then refresh, beside a code a phone
    /// scans to open the same store page in the PlayStation App.
    ///
    /// - Parameter page: The store page the game is added on.
    /// - Returns: The hint with its code.
    func libraryAddHint(_ page: URL?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let page {
                QRCodeImage(page.absoluteString, side: 96, label: "PlayStation Store page code")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Add to library in the PS Store page and then refresh to play")
                if page != nil {
                    Text("Or scan the code to add it in the PlayStation App on your phone")
                }
            }
            .font(.callout).foregroundStyle(.white.opacity(0.72))
        }
    }
    /// A code for the game's store page, which a phone scans to open the page in the PlayStation App and which
    /// opens the page itself when pressed, so on a phone it is one tap away.
    ///
    /// - Parameters:
    ///   - page: The store page the code opens.
    ///   - owned: Whether the game is already in the library, so the caption does not offer to buy it.
    /// - Returns: The focusable code beside its caption.
    func purchaseHint(_ page: URL, owned: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            purchaseCodeButton(page)
            Text(purchaseCaption(owned: owned))
                .font(.callout).foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    /// The store code tile beside its caption, where the legacy card shows the store page under its buttons.
    ///
    /// - Parameters:
    ///   - link: The store page's link, which titles the tile.
    ///   - code: The store page the code encodes.
    ///   - game: The game whose store page opens.
    ///   - owned: Whether the game is already in the library, so the caption does not offer to buy it.
    /// - Returns: The tile beside its caption.
    func storeTileHint(
        _ link: CloudGameActions.StoreLink, _ code: URL, _ game: CloudGame, owned: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            storeCodeCard(link, code, game)
            Text(purchaseCaption(owned: owned))
                .font(.callout).foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The caption beside the store page code.
    ///
    /// - Parameter owned: Whether the game is already in the library.
    /// - Returns: The caption.
    func purchaseCaption(owned: Bool) -> String {
        if layout.touch {
            return "Tap the code to open the store page, or scan it with your phone"
        }
        return owned
            ? "Scan the code to open the store page in the PlayStation App on your phone"
            : "Scan the code to buy it in the PlayStation App on your phone"
    }
    /// The store page code as a focusable button that opens the page when pressed.
    ///
    /// - Parameter page: The store page the game is bought on.
    /// - Returns: The focusable code.
    func purchaseCodeButton(_ page: URL) -> some View {
        FocusButton {
            openURL(page)
        } label: {
            QRCodeImage(page.absoluteString, side: storeCodeSide, label: "PlayStation Store page code")
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(12))
        .menuFocused($focus, equals: .purchaseCode)
        .accessibilityLabel("Open the store page")
        .accessibilityHint("Scan the code with a phone, or press to open it here")
        .accessibilityIdentifier("cloud-store-code")
    }

    /// The store link as the code tile with its caption when the store page has a code, and as the plain
    /// store button otherwise.
    ///
    /// - Parameters:
    ///   - link: The store page's link.
    ///   - code: The store page the code encodes, when there is one.
    ///   - game: The game whose store page opens.
    /// - Returns: The tile and caption, or the button.
    @ViewBuilder func storeChoice(
        _ link: CloudGameActions.StoreLink, _ code: URL?, _ game: CloudGame
    ) -> some View {
        if let code {
            VStack(alignment: .leading, spacing: 10) {
                storeCodeCard(link, code, game)
                Text(layout.touch
                    ? "Tap or scan to open the store page"
                    : "Scan to open the store page on your phone")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 180, alignment: .leading)
            }
        } else {
            storeButton(link, game)
        }
    }

    /// The store page code with the store link's title under it on one glass tile that is one button, see
    /// ``StoreCodeTile``.
    ///
    /// - Parameters:
    ///   - link: The store page's link, which titles the tile.
    ///   - page: The store page the code encodes.
    ///   - game: The game whose store page opens.
    /// - Returns: The tile, which takes the store focus stop.
    func storeCodeCard(_ link: CloudGameActions.StoreLink, _ page: URL, _ game: CloudGame) -> StoreCodeTile {
        StoreCodeTile(
            page: page,
            title: link.title,
            symbol: "arrow.up.right",
            opening: store.storeOpening.contains(game.id),
            codeSide: storeCodeSide,
            controlSize: layout.controlSize,
            stop: .store,
            focus: $focus,
            openStore: { store.send(.storePageTapped(game.id)) },
            move: { moveDetails(game, direction: $0) }
        )
    }

    /// The store page code with Add to library under it on one glass tile that is one button, which opens
    /// the store page to add the game the way the Add to library button does, see ``StoreCodeTile``.
    ///
    /// - Parameters:
    ///   - page: The store page the game is added on, which the code encodes.
    ///   - game: The game to add.
    /// - Returns: The tile, which takes the Add to library focus stop.
    func libraryAddCard(_ page: URL, _ game: CloudGame) -> StoreCodeTile {
        StoreCodeTile(
            page: page,
            title: "Add to library",
            symbol: "plus",
            opening: store.storeOpening.contains(game.id),
            codeSide: storeCodeSide,
            controlSize: layout.controlSize,
            stop: .addToLibrary,
            focus: $focus,
            openStore: { store.send(.addToLibraryTapped(game.id)) },
            move: { moveDetails(game, direction: $0) }
        )
    }

    /// The size of the play and store buttons' titles: smaller on a compact screen, where the large glass
    /// bezel alone brings the button to finger size.
    var actionTitleSize: CGFloat {
        layout.isCompact
            ? 17
            : 20
    }

    /// The prominent button that opens the store page so the game can be added to the library.
    ///
    /// - Parameter game: The game to add.
    /// - Returns: The focusable add to library button.
    func addToLibraryButton(_ game: CloudGame) -> some View {
        FocusButton {
            store.send(.addToLibraryTapped(game.id))
        } label: {
            Group {
                if store.storeOpening.contains(game.id) {
                    StoreButtonLabel(title: "Add to library", opening: true)
                } else {
                    Label("Add to library", systemImage: "plus")
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .glassProminentControlStyle().focusBorderShape(.capsule).controlSize(.large)
        .menuFocused($focus, equals: .addToLibrary)
    }
    /// The button that refreshes the game's entitlement after it was added in the store, with the time left
    /// beside it while a finished refresh holds the next one.
    ///
    /// - Parameter game: The game to refresh.
    /// - Returns: The refresh button and its countdown.
    func refreshTitleButton(_ game: CloudGame) -> some View {
        HStack(spacing: 10) {
            refreshTitleControl(game)
            if let until = store.titleRefresh.availableAt {
                CloudRefreshCountdown(until: until)
            }
        }
    }
    /// The button that refreshes one title, dimmed while the title refresh is unavailable.
    ///
    /// - Parameter game: The game to refresh.
    /// - Returns: The focusable refresh button.
    func refreshTitleControl(_ game: CloudGame) -> some View {
        let refreshing = store.state.isRefreshing(game)
        return FocusButton {
            store.send(.refreshTitle(game.id))
        } label: {
            HStack(spacing: 8) {
                if refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(refreshing
                    ? "Checking"
                    : "Refresh")
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .glassControlStyle().focusBorderShape(.capsule).controlSize(.large)
        .menuFocused($focus, equals: .refreshTitle)
        .disabled(store.titleRefresh != .idle)
        .allowsHitTesting(store.state.mayRefreshTitle(game.id))
        .opacity(store.state.mayRefreshTitle(game.id)
            ? 1
            : 0.45)
            .help("Refresh this title")
            .accessibilityLabel(refreshing
                ? "Checking this title"
                : "Refresh this title")
    }
    /// The outcome of the last title refresh: a copyable error, or a notice that the game was added or is
    /// still missing.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The notice, or nothing when no refresh ran.
    @ViewBuilder func titleNotice(_ game: CloudGame) -> some View {
        switch store.titleNotice[game.id] {
        case .failed(let message):
            CopyableErrorMessage(message: message, font: .callout)
        case .some(let notice):
            Label(notice.message, systemImage: notice == .added
                ? "checkmark.circle.fill"
                : "info.circle")
                .font(.callout).foregroundStyle(.white.opacity(0.85))
                .transition(.opacity)
        case nil:
            EmptyView()
        }
    }
    /// A cover drawn from a catalog image address, or a placeholder when the address is missing or insecure.
    ///
    /// - Parameter raw: The image address the catalog gave.
    /// - Returns: The cover view.
    func artwork(_ raw: String?) -> some View {
        CloudArtworkView(url: .secureArtwork(raw))
    }
    /// One metadata line of an icon beside text.
    ///
    /// - Parameters:
    ///   - text: The line's text.
    ///   - icon: The icon leading the line.
    ///   - highlighted: Whether the icon is drawn heavy and yellow.
    /// - Returns: The metadata line.
    func metadata(_ text: String, icon: AppIcon, highlighted: Bool = false) -> some View {
        CloudGameMetadata(text: text, icon: icon, highlighted: highlighted)
    }
    /// The icon for how the game is held: library, subscription or store.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The entitlement icon.
    func entitlementIcon(_ game: CloudGame) -> AppIcon {
        game.entitlementIcon
    }
    /// The game's standing as text, after the store page check is taken into account.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The standing's label.
    func entitlement(_ game: CloudGame) -> String {
        game.standingLabel(after: store.cardChecks[game.id])
    }
}

/// The store page code on its white quiet zone with the store link's title under it, both on one glass tile
/// as wide as the code, and the whole tile one button that opens the store page the way the store button
/// does, so a phone scans the code and a pointer or finger presses anywhere on it.
///
/// A view of its own, so the detail's layout branches hold a small concrete type rather than a long opaque
/// modifier chain.
struct StoreCodeTile: View {
    /// The store page the code encodes.
    let page: URL
    /// The tile's title, shown under the code.
    let title: String
    /// The symbol beside the title.
    let symbol: String
    /// Whether the store page is opening, which the title gives way to.
    let opening: Bool
    /// The side of the code.
    let codeSide: CGFloat
    /// The smallest height of the title row, so it takes a finger on touch.
    let controlSize: CGFloat
    /// The focus stop the tile is.
    let stop: CloudLibraryFocus
    /// The detail's focus.
    @MenuFocusState.Binding var focus: CloudLibraryFocus?
    /// Opens the store page.
    let openStore: () -> Void
    /// Moves the detail's focus in a direction the tile does not take.
    let move: (MenuMoveDirection) -> Void

    var body: some View {
        FocusButton {
            openStore()
        } label: {
            VStack(spacing: 4) {
                QRCodeImage(page.absoluteString, side: codeSide, label: "PlayStation Store page code")
                HStack(spacing: 5) {
                    StoreButtonLabel(title: title, opening: opening)
                    if !opening {
                        Image(systemName: symbol)
                            .imageScale(.small)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, minHeight: max(28, controlSize))
                .padding(.horizontal, 8)
            }
            .padding(8)
            .frame(width: codeSide + 16)
            .glassPanel(.medium)
            .contentShape(.rect(cornerRadius: GlassPanel.Radius.medium.points))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(GlassPanel.Radius.medium.points))
        .menuFocused($focus, equals: stop)
        .onMenuMoveCommand { move($0) }
        .accessibilityLabel("Open the store page")
        .accessibilityHint("Scan the code with a phone, or press to open it here")
        .accessibilityIdentifier("cloud-store-code")
    }
}

/// A store button's title, replaced by a spinner and "Opening…" while the store page is being looked up and
/// handed to the browser, so the press is visibly taken.
struct StoreButtonLabel: View {
    /// The button's usual title.
    let title: String
    /// Whether the store page is opening.
    let opening: Bool

    var body: some View {
        if opening {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Opening…")
            }
            .accessibilityLabel("Opening the store page")
        } else {
            Text(title)
        }
    }
}

/// The words the game detail shows for the store page check.
private enum CloudCardCheckMessage {
    /// The player-facing explanation of the check's state, or `nil` when the game streams.
    ///
    /// - Parameter check: The check.
    /// - Returns: The explanation.
    static func text(for check: CloudCardCheck) -> String? {
        switch check {
        case .checking:
            "Checking the store"
        case .streams:
            nil
        case .notStreamable:
            "The store page doesn't list this edition for cloud streaming on PS5"
        case .refused:
            "The stream server refused this game"
        case .unavailable(let detail):
            "Couldn't check the store: \(detail)"
        }
    }
}

/// The launch check steps in a row, each with a symbol for not checked, checking, passed or refused, and the
/// reason underneath when the checks stopped.
private struct CloudLaunchStepRow: View {
    /// The checks the row shows.
    let checks: CloudLaunchChecks
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a cloud launch step row.
    ///
    /// - Parameter checks: The checks the row shows.
    init(checks: CloudLaunchChecks) {
        self.checks = checks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(checks.steps, id: \.self) { step in
                    stepView(step, checks.mark(step))
                }
            }
            if let reason = checks.reason {
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(AppMotion.animation(reduced: reduceMotion), value: checks.phase)
        .accessibilityIdentifier("cloud-launch-checks")
    }

    private func stepView(_ step: CloudLaunchChecks.Step, _ mark: CloudLaunchChecks.Mark) -> some View {
        VStack(spacing: 4) {
            symbol(mark)
                .frame(width: 20, height: 20)
            Text(step.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(mark == .unchecked
                        ? 0.62
                        : 0.92))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.label)
        .accessibilityValue(Self.spoken(mark))
    }

    @ViewBuilder private func symbol(_ mark: CloudLaunchChecks.Mark) -> some View {
        switch mark {
        case .unchecked:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.white.opacity(0.62))
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .refused:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private static func spoken(_ mark: CloudLaunchChecks.Mark) -> String {
        switch mark {
        case .unchecked:
            "Not checked"
        case .checking:
            "Checking"
        case .passed:
            "Passed"
        case .refused:
            "Refused"
        }
    }
}
