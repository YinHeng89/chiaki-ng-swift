import ChiakiDiagnostics
import PlatformUI
import Observation
import ComposableArchitecture
import SwiftUI
import DesignSystem
import MenuFocus

/// The controls in the live developer log that can hold controller focus, and the record of which one is
/// focused in each window.
enum LiveLogFocus: Hashable {
    /// The log toggle button, the pause or resume button, the copy button, the close button and the follow
    /// toggle.
    case button, pauseResume, copy, close, follow

    @MainActor private static var owners = [ObjectIdentifier: LiveLogFocus]()

    /// Returns the log control focused in a window, or `nil` when none is.
    /// - Parameter window: The window to look up.
    /// - Returns: The focused control, if any.
    @MainActor static func focus(in window: PlatformWindow?) -> LiveLogFocus? {
        window.flatMap { owners[ObjectIdentifier($0)] }
    }

    /// Records which log control is focused in a window, or clears it with `nil`.
    /// - Parameters:
    ///   - focus: The focused control, or `nil`.
    ///   - window: The window it belongs to; nothing is recorded when this is `nil`.
    @MainActor static func record(_ focus: LiveLogFocus?, in window: PlatformWindow?) {
        guard let window else {
            return
        }
        owners[ObjectIdentifier(window)] = focus
    }
}

/// Shared layout state for the controls along the top trailing edge, so the settings and log buttons can line
/// up and know where each other is.
@MainActor @Observable
final class TopControlsLayout {
    /// Where the settings control is drawn.
    enum SettingsHost {
        /// As a floating overlay in the window corner.
        case overlay
        /// Inside the library bar, while some library bar hosts it.
        case libraryBar
    }

    /// The identifiers of the views currently hosting the settings control in the library bar.
    private(set) var settingsHosts = Set<UUID>()
    /// The leading edge of the settings control in global coordinates, once measured.
    var settingsMinX: CGFloat?
    /// The leading edge of the live log button in global coordinates, once measured.
    var logMinX: CGFloat?
    /// Whether the settings control currently holds controller focus.
    var settingsFocused = false

    /// The leftmost leading edge among the measured top controls, or `nil` when none is measured.
    var minX: CGFloat? {
        [settingsMinX, logMinX].compactMap { $0 }.min()
    }

    /// Hosts settings in the library bar while any view claims it, otherwise as an overlay.
    var settingsHost: SettingsHost {
        settingsHosts.isEmpty
            ? .overlay
            : .libraryBar
    }

    /// Adds or removes a view's claim to host the settings control in the library bar.
    /// - Parameters:
    ///   - host: The identifier of the claiming view.
    ///   - hosting: Whether the view now hosts the control.
    func hostSettings(_ host: UUID, _ hosting: Bool) {
        if hosting {
            settingsHosts.insert(host)
        } else {
            settingsHosts.remove(host)
        }
    }
}

private struct TopControlsLayoutKey: EnvironmentKey {
    static let defaultValue: TopControlsLayout? = nil
}

private struct LiveLogButtonShownKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The diagnostic log the screens write to, which the app supplies at its root.
    @Entry public var logger = LoggerClient.disabled

    /// The shared top controls layout for this part of the view tree, if one is provided.
    var topControlsLayout: TopControlsLayout? {
        get {
            self[TopControlsLayoutKey.self]
        }
        set {
            self[TopControlsLayoutKey.self] = newValue
        }
    }

    /// Whether the live developer log button is shown, so neighbouring controls can make room and route focus
    /// to it.
    var liveLogButtonShown: Bool {
        get {
            self[LiveLogButtonShownKey.self]
        }
        set {
            self[LiveLogButtonShownKey.self] = newValue
        }
    }
}

/// The live developer log in the top trailing corner: a log panel and, where no menu holds a Log stop, the
/// button that toggles it, with controller navigation between the button, the panel and neighbouring
/// controls.
///
/// The library rail and the stream menu dock open the panel with `toggleLiveLog` instead of the button;
/// leaving the panel then hands focus back to their Log stop with `focusLiveLogOpener`.
struct LiveLogControl: View {
    /// The menu navigator that registers this control's back handler.
    @Environment(\.menuNavigator) var navigator
    /// Asks the app to show its quit prompt when back is pressed on the button.
    @Environment(\.requestQuit) var requestQuit
    /// The store that holds the log's visibility and entries.
    let store: StoreOf<LiveLogReducer>
    /// A failure message shown in the panel, if any.
    let failure: String?
    /// The size of the area the panel may fill.
    let size: CGSize
    /// Extra trailing padding applied to the button.
    let trailingInset: CGFloat
    /// Whether the control sits over a stream rather than the library, which changes its glass style and
    /// focus routes.
    let inStream: Bool
    /// Whether pressing back on the button may ask to quit the app.
    let allowsQuit: Bool
    /// Whether the toggle button shows, which it does where no menu holds a Log stop.
    let showsButton: Bool
    @MenuFocusState private var focus: LiveLogFocus?
    @Environment(\.topControlsLayout) private var topControlsLayout
    @State private var hostWindow: PlatformWindow?
    @State private var backHandlerID: MenuHandlerID?

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showsButton {
                FocusButton {
                    store.send(.toggle)
                } label: {
                    AppIcon.logging.image.frame(width: 32, height: 32)
                }
                .glassControlStyle((inStream
                        ? AppGlass.control
                        : AppGlass.panel)).focusBorderShape(.circle)
                    .menuFocused($focus, equals: .button)
                    .environment(\.menuMove, move)
                    .accessibilityLabel(
                        store.visible
                            ? .appDeveloperLogHide
                            : .appDeveloperLogShow
                    )
                    .help(.appDeveloperLogToggleHelp)
                    .streamChromeFocus(.topTrailing)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { minX in
                        topControlsLayout?.logMinX = minX
                    }
                    .padding(.trailing, trailingInset)
            }
            if store.visible {
                LiveLogPanel(
                    store: store,
                    failure: failure,
                    bounds: CGSize(
                        width: max(240, size.width - 36),
                        height: max(140, size.height - 110)
                    ),
                    focus: $focus,
                    move: move
                )
            }
        }
        .topChromeInset().padding(.trailing, 18)
        .streamChromePinned(.topTrailing, store.visible)
        .streamChromeCorner(.topTrailing)
        .background(WindowAccessor { hostWindow = $0 })
        .onReceive(NotificationCenter.default.publisher(for: .toggleLiveLog)) { notification in
            guard let window = notification.object as? PlatformWindow, window === hostWindow else {
                return
            }
            store.send(.toggle)
            if store.visible, navigator?.inputMode.mode == .controller {
                focus = .pauseResume
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLiveLogButton)) { notification in
            guard showsButton, let window = notification.object as? PlatformWindow,
                  window === hostWindow else {
                return
            }
            focus = .button
            Task { @MainActor in
                await Task.yield()
                if focus == nil {
                    focus = .button
                }
            }
        }
        .onChange(of: hostWindow) { previous, window in
            LiveLogFocus.record(nil, in: previous)
            LiveLogFocus.record(focus, in: window)
        }
        .onChange(of: focus) { _, value in
            LiveLogFocus.record(value, in: hostWindow)
            updateBackHandler(active: value != nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .streamControlsDismissed)) { notification in
            if let window = notification.object as? PlatformWindow, window === hostWindow, focus != nil {
                focus = nil
            }
        }
        .onChange(of: showsButton) { _, shown in
            if !shown {
                topControlsLayout?.logMinX = nil
            }
        }
        .onChange(of: allowsQuit) { _, _ in
            if backHandlerID != nil {
                updateBackHandler(active: false)
                updateBackHandler(active: true)
            }
        }
        .onChange(of: store.visible) { _, visible in
            if !visible, focus != nil, focus != .button {
                returnToOpener()
            }
        }
        .onDisappear {
            topControlsLayout?.logMinX = nil
            if focus != nil {
                LiveLogFocus.record(nil, in: hostWindow)
            }
            updateBackHandler(active: false)
        }
    }

    private static let panelMoves: [LiveLogFocus: [MenuMoveDirection: LiveLogFocus]] = [
        .pauseResume: [.right: .copy, .up: .button, .down: .follow],
        .copy: [.left: .pauseResume, .right: .close, .up: .button, .down: .follow],
        .close: [.left: .copy, .up: .button, .down: .follow],
        .follow: [.up: .close]
    ]

    private func move(_ direction: MenuMoveDirection) {
        guard let current = focus else {
            return
        }
        if current == .button {
            moveFromButton(direction)
        } else if let next = Self.panelMoves[current]?[direction] {
            if next == .button {
                returnToOpener()
            } else {
                focus = next
            }
        }
    }

    private func returnToOpener() {
        if showsButton {
            focus = .button
        } else {
            NotificationCenter.default.post(name: .focusLiveLogOpener, object: hostWindow)
        }
    }

    private func moveFromButton(_ direction: MenuMoveDirection) {
        switch direction {
        case .left:
            NotificationCenter.default.post(
                name: inStream
                    ? .focusStreamMenuSettings
                    : .focusLibraryHeader,
                object: hostWindow
            )
        case .right:
            NotificationCenter.default.post(name: .focusSettingsControl, object: hostWindow)
        case .down:
            if store.visible {
                focus = .pauseResume
            } else {
                NotificationCenter.default.post(
                    name: inStream
                        ? .focusStreamMenuSettings
                        : .focusLibraryContent,
                    object: hostWindow
                )
            }
        default:
            break
        }
    }

    private func updateBackHandler(active: Bool) {
        if active, backHandlerID == nil {
            backHandlerID = navigator?.handlers.registerBack { window in
                guard window === hostWindow, let current = focus else {
                    return false
                }
                if current != .button {
                    store.send(.close)
                    returnToOpener()
                    return true
                }
                if store.visible {
                    store.send(.close)
                    return true
                }
                guard allowsQuit, !WindowFocus(window).hasAttachedSheet,
                      !(navigator?.inputGate.isBlocking ?? false) else {
                    return false
                }
                requestQuit(.screen)
                return true
            }
        } else if !active, let backHandlerID {
            navigator?.handlers.unregister(backHandlerID)
            self.backHandlerID = nil
        }
    }
}
