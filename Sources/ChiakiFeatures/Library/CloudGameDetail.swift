import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// The detail panel for one cloud game, shown as a card or as layered art, with its play, store and library
/// actions and its own controller focus order starting at Close.
struct CloudGameDetail: View {
    /// The library focus the detail's controls take.
    typealias FocusItem = CloudLibraryFocus

    /// The game the detail shows.
    let game: CloudGame
    /// The account that would play the game, or `nil` when none is signed in.
    let accountID: UUID?
    /// The height available to the panel.
    let height: CGFloat
    /// The cloud library store that holds the detail, its checks and the bundle picker, and receives the
    /// detail's actions.
    let store: StoreOf<CloudLibraryFeature>
    /// The library's controller focus, shared with the grid behind the detail.
    @MenuFocusState.Binding var focus: FocusItem?
    /// Reads the control that held focus before the detail last changed, so the layered detail can return
    /// focus to it.
    let heldFocus: () -> FocusItem?
    /// Whether Reduce Motion is on, which replaces the detail's growth and reveal animations with fades.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// The screen's layout traits: a compact screen makes the panel fill the window, and touch sizes its
    /// controls for a finger.
    @Environment(\.screenLayout) var layout
    /// Opens the store page a code encodes.
    @Environment(\.openURL) var openURL
    /// The app's menu navigator, which puts back a focus request SwiftUI dropped.
    @Environment(\.menuNavigator) var navigator
    /// The window the detail is shown in, once known.
    @State var hostWindow: PlatformWindow?
    /// The measured height of the card's scrolling column, used as the content's minimum height so it fills
    /// the column.
    @State var columnHeight: CGFloat = 0
    /// The control the detail asked to focus, kept until it takes focus.
    @State var pendingFocus: FocusItem?

    /// The panel's height: the full height on compact screens, otherwise the height less a margin with a
    /// floor of 420 points.
    var panelHeight: CGFloat {
        layout.isCompact
            ? height
            : max(420, height - 24)
    }

    /// The width of the card's content column: the width of the cover beside its column on a short compact
    /// screen, otherwise wider when Check & play and a store button share its row so neither title is cut off.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The width in points.
    func cardContentWidth(_ game: CloudGame) -> CGFloat {
        guard !cardIsWide else {
            return 600
        }
        let actions = actions(game)
        return actions.play != nil && actions.store != nil
            ? 470
            : 380
    }

    /// Whether the card lays its cover beside a scrolling column, as it does on a short compact screen where
    /// the cover cannot sit above the actions.
    var cardIsWide: Bool {
        layout.isCompact && layout.isShort
    }

    /// The trailing inset that keeps the layered detail's Close button clear of the screen's side inset, such
    /// as a phone's rounded corners, when the detail covers the window.
    var closeInset: CGFloat {
        layout.isCompact
            ? layout.sideInset
            : 0
    }

    /// The leading inset of the layered detail's sections: clear of the screen's side inset on a compact
    /// screen, and otherwise wider on a wide stage.
    ///
    /// - Parameter stageWidth: The art stage's width.
    /// - Returns: The inset in points.
    func sectionInset(stageWidth: CGFloat) -> CGFloat {
        if layout.isCompact {
            return 24 + layout.sideInset
        }
        return stageWidth >= 900
            ? 64
            : 32
    }

    /// The height of the layered detail's art stage: the whole panel on a short compact screen, a band on a
    /// tall one, and about three quarters of the panel otherwise.
    var stageHeight: CGFloat {
        if layout.isCompact {
            return layout.isShort
                ? panelHeight
                : min(420, max(300, panelHeight * 0.55))
        }
        return min(620, max(380, panelHeight * 0.76))
    }

    /// The side of the store code: larger where there is room, and always big enough for a finger.
    var storeCodeSide: CGFloat {
        max(
            layout.controlSize,
            layout.isCompact
                ? 120
                : 150
        )
    }

    var body: some View {
        detailPanel(game)
            .background(WindowAccessor { hostWindow = $0 })
            .onChange(of: focus) { _, current in
                followPendingFocus(current)
            }
            .onChange(of: game.id) { _, _ in
                followSwitchedVersion()
            }
    }

    private func followSwitchedVersion() {
        guard pendingFocus == .otherVersion else {
            return
        }
        Task { @MainActor in
            focus = nil
            await Task.yield()
            focusDetail(game, .otherVersion)
        }
    }

    private func followPendingFocus(_ current: FocusItem?) {
        guard let pendingFocus else {
            return
        }
        if current == pendingFocus || store.selectedGame?.id != game.id {
            self.pendingFocus = nil
        } else if current == nil {
            focus = pendingFocus
        }
    }

    /// Works out what the detail offers for a game from the library's current state.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The play, store and library actions with their focus order.
    func actions(_ game: CloudGame) -> CloudGameActions {
        store.state.actions(for: game)
    }

    /// The card's height, taller when it shows a store or add to library button, and nearly the full height
    /// on compact screens.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The height in points.
    func detailHeight(_ game: CloudGame) -> CGFloat {
        let actions = actions(game)
        let preferred: CGFloat
        if actions.store != nil, actions.purchaseCode != nil {
            preferred = 680
        } else if actions.store != nil {
            preferred = 620
        } else if actions.addToLibrary != nil {
            preferred = 660
        } else {
            preferred = 560
        }
        return layout.isCompact
            ? height - 96
            : min(preferred, panelHeight)
    }

    /// The control the detail focuses when it opens: the first action after Close, or Close when there is no
    /// action.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: The control to focus, or `nil` when there is nothing to focus.
    func detailInitialFocus(_ game: CloudGame) -> FocusItem? {
        let items = detailFocusItems(game)
        return items.first { $0 != .close } ?? items.first
    }

    /// The card detail's controls in controller focus order, starting with Close.
    ///
    /// - Parameter game: The game the detail shows.
    /// - Returns: Close followed by the game's actions; the store page code is its own stop only when there is
    ///   no store link to share a tile with.
    func detailFocusItems(_ game: CloudGame) -> [FocusItem] {
        let actions = actions(game)
        return [.close] + actions.focusOrder.compactMap { item -> FocusItem? in
            switch item {
            case .play:
                .play
            case .store:
                .store
            case .purchaseCode:
                actions.store == nil
                    ? .purchaseCode
                    : nil
            case .addToLibrary:
                .addToLibrary
            case .refreshTitle:
                .refreshTitle
            case .bundleGame(let id):
                .bundleGame(id)
            case .otherVersion:
                .otherVersion
            }
        }
    }

    /// Moves controller focus through the detail's controls, wrapping at either end.
    ///
    /// Left and up step back and right and down step forward. While the detail loads only Close can take
    /// focus, and the
    /// layered detail moves through its own layout unless the bundle picker is open.
    ///
    /// - Parameters:
    ///   - game: The game the detail shows.
    ///   - direction: The direction the controller moved in.
    func moveDetails(_ game: CloudGame, direction: MenuMoveDirection) {
        switch store.detail?.shown(for: game.product) ?? .card {
        case .loading:
            focus = .close
            return
        case .layered(let expanded) where store.bundlePicker != game.id:
            moveLayeredDetails(game, expanded, direction: direction)
            return
        case .layered, .card:
            break
        }
        let items = detailFocusItems(game)
        guard let focus, let index = items.firstIndex(of: focus) else {
            self.focus = items.first
            return
        }
        let step = direction == .left || direction == .up
            ? -1
            : 1
        self.focus = items[(index + step + items.count) % items.count]
    }
}

extension CloudGameDetail {
    /// The bundle's games stacked in place of the play button, so one can be chosen to play.
    var bundlePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.bundleChoices) { choice in
                bundleChoice(choice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cloud-bundle-picker")
    }

    /// One game in the bundle picker: a play button that launches it, or its name with the stream service's reason
    /// when it cannot be played.
    ///
    /// - Parameter choice: The bundled game to show.
    /// - Returns: A focusable play button, or a plain explanation for a refused game.
    @ViewBuilder func bundleChoice(_ choice: CloudBundleChoice) -> some View {
        if let reason = choice.reason {
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.game.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Label(reason, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cloud-bundle-refused")
        } else {
            FocusButton {
                store.send(.playBundleGame(choice.id))
            } label: {
                Label(choice.game.name, systemImage: AppIcon.start.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .glassProminentControlStyle().focusBorderShape(.capsule).controlSize(.large)
            .menuFocused($focus, equals: .bundleGame(choice.id))
            .accessibilityIdentifier("cloud-bundle-game")
        }
    }
}
