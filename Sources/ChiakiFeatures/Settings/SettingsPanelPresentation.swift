import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import Observation
import PlatformUI
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Opens the settings panel of the focused scene from the menu bar.
struct SettingsPanelOpener {
    /// Opens the focused scene's settings panel.
    let open: @MainActor () -> Void
}

private struct SettingsPresentedKey: FocusedValueKey {
    typealias Value = SettingsPanelOpener
}

/// The focused scene value that lets the menu bar open settings.
extension FocusedValues {
    /// The focused scene's settings opener, or `nil` when no scene can show settings, which disables the menu
    /// command.
    var settingsPresented: SettingsPanelOpener? {
        get {
            self[SettingsPresentedKey.self]
        }
        set {
            self[SettingsPresentedKey.self] = newValue
        }
    }
}

/// Replaces the app's Settings menu item with one that opens the focused scene's settings panel with Command
/// comma.
public struct SettingsPanelCommands: Commands {
    /// The menu navigator whose text editing ends before settings open.
    let navigator: PlatformMenuNavigator
    @FocusedValue(\.settingsPresented) private var presented

    /// Creates the Settings menu item.
    ///
    /// - Parameter navigator: The menu navigator whose text editing ends before settings open.
    public init(navigator: PlatformMenuNavigator) {
        self.navigator = navigator
    }

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(.settingsPanelMenuCommand) {
                navigator.endEditing()
                presented?.open()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(presented == nil)
        }
    }
}

/// Overlays a scene with the settings button and the settings panel, presenting the panel from the button,
/// the menu command, a controller or a launch argument, and returning focus to the library or stream controls
/// when it closes.
struct SettingsPanelPresentation: ViewModifier {
    /// The menu navigator whose input gate blocks the content behind the open panel.
    @Environment(\.menuNavigator) var navigator
    /// Whether the panel opens as soon as the scene appears.
    var startsPresented = false
    /// Whether a Quit control is shown beside the settings button.
    var showsQuit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.logger) private var logger
    @Environment(\.liveLogButtonShown) private var liveLogButtonShown
    @Environment(\.topControlsLayout) private var topControlsLayout
    @Environment(\.screenLayout) private var layout
    @State private var presentationID = UUID()
    @State private var pressStart: SettingsPanelPress?
    @State private var settingsCenterX: CGFloat?
    @State private var hostWindow: PlatformWindow?
    @MenuFocusState private var closeFocused: Bool
    @MenuFocusState private var settingsFocused: Bool
    @MenuFocusState private var quitFocused: Bool
    @State private var quitBackHandlerID: MenuHandlerID?
    @Environment(\.requestQuit) private var requestQuit
    /// The root store whose settings state the panel shows and whose presentation flag it follows.
    let root: StoreOf<RootFeature>

    private var store: StoreOf<SettingsFeature> {
        root.scope(state: \.settings, action: \.settings)
    }

    private var presented: Bool {
        root.settingsPresented
    }

    /// Disables the content while the panel is open and overlays it with the settings button and the panel.
    func body(content: Content) -> some View {
        content
            .disabled(presented)
            .overlay(alignment: .topTrailing) {
                settingsButton
            }
            .overlay {
                presentedPanel
            }
            .streamChromePinned(.topTrailing, presented)
            .focusedSceneValue(\.settingsPresented, SettingsPanelOpener {
                setPresented(true, by: "the Settings menu command")
            })
            .onMenuCommand([.settings], perform: toggleFromController)
            .onReceive(
                NotificationCenter.default.publisher(for: .focusQuitControl),
                perform: focusQuitControl
            )
            .onReceive(NotificationCenter.default.publisher(for: .focusSettingsControl)) { notification in
                guard !presented, let window = notification.object as? PlatformWindow,
                      window === WindowFocus.keyWindow else {
                    return
                }
                settingsFocused = true
            }
            .animation(AppMotion.animation(reduced: reduceMotion), value: presented)
            .onChange(of: presented) { _, value in
                presentedChanged(value)
            }
            .onDisappear {
                navigator?.inputGate.presentations.remove(presentationID)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, !store.tokens.authenticating {
                    setPresented(false, by: "the window stopped being active")
                }
            }
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--show-picture-settings") {
                    store.send(.select(.picture))
                }
                if arguments.contains("--show-settings")
                    || arguments.contains("--show-picture-settings")
                    || startsPresented {
                    setPresented(true, by: "a launch argument")
                }
            }
    }
    private var touchRailHostsSettings: Bool {
        layout.touch && navigator?.inputMode.mode != .controller
    }

    private var settingsButton: some View {
        HStack(spacing: 12) {
            if topControlsLayout?.settingsHost != .libraryBar, !root.streamPlaying, !touchRailHostsSettings {
                SettingsButton {
                    setPresented(true, by: "the Settings button")
                }
                .menuFocused($settingsFocused)
                .streamChromeFocus(.topTrailing)
                .environment(\.menuMove) { direction in
                    if direction == .right, quitShownHere {
                        quitFocused = true
                    } else {
                        moveFromSettingsButton(direction)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                    settingsCenterX = midX
                }
            }
            if quitShownHere {
                AppQuitButton()
                    .menuFocused($quitFocused)
                    .environment(\.menuMove) { direction in
                        if direction == .left {
                            settingsFocused = true
                        } else if direction == .down {
                            moveFromSettingsButton(direction)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .disabled(presented)
        .background(WindowAccessor { hostWindow = $0 })
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { minX in
            topControlsLayout?.settingsMinX = minX
        }
        .onChange(of: settingsFocused) { _, focused in
            topControlsLayout?.settingsFocused = focused
        }
        .onReceive(NotificationCenter.default.publisher(for: .streamControlsDismissed)) { notification in
            if !presented, let window = notification.object as? PlatformWindow, window === hostWindow,
               settingsFocused || quitFocused {
                settingsFocused = false
                quitFocused = false
            }
        }
        .topChromeInset().padding(.trailing, 28)
        .streamChromeCorner(.topTrailing)
        .onChange(of: showsQuit, initial: true) { _, shows in
            updateQuitBackHandler(shows)
        }
        .onDisappear {
            updateQuitBackHandler(false)
        }
    }

    private var presentedPanel: some View {
        GeometryReader { geometry in
            if presented, Self.showsPhoneSettings(on: layout) {
                MobileSettingsPanel(settings: store, window: hostWindow) {
                    setPresented(false, by: "the phone settings")
                }
                .transition(reduceMotion
                    ? .opacity
                    : .move(edge: .trailing).combined(with: .opacity))
            } else if presented {
                Dimming.light.color
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(outsidePress)
                    .accessibilityLabel(.settingsPanelDismiss)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { setPresented(false, by: "accessibility") }
                    .transition(.opacity)
                panel(size: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.horizontal, sideMargin)
                    .padding(.top, panelTop)
                    .padding(.bottom, floatMargin)
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var outsidePress: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressStart == nil {
                    pressStart = SettingsPanelPress.current(openedAt: root.settingsOpenedAt ?? 0)
                }
            }
            .onEnded { _ in
                let start = pressStart
                pressStart = nil
                guard let start, start.afterOpening else {
                    note(
                        "Settings panel kept open: the click began before it opened (\(start?.event ?? "no event"))"
                    )
                    return
                }
                setPresented(false, by: "a click outside the panel (\(start.event))")
            }
    }

    private func presentedChanged(_ value: Bool) {
        note(
            value
                ? "Settings panel is now open"
                : "Settings panel is now closed"
        )
        navigator?.endEditing()
        if value {
            navigator?.inputGate.presentations.insert(presentationID)
        } else {
            navigator?.inputGate.presentations.remove(presentationID)
            if scenePhase == .active {
                NotificationCenter.default.post(name: .focusLibraryContent, object: WindowFocus.keyWindow)
                if Self.returnsToStreamControls(after: (navigator?.inputMode.mode ?? .pointer)) {
                    NotificationCenter.default.post(
                        name: .focusStreamMenuSettings,
                        object: WindowFocus.keyWindow
                    )
                }
            }
        }
    }

    private var floatMargin: CGFloat {
        layout.sheetsFillWidth
            ? 0
            : 20
    }

    private var sideMargin: CGFloat {
        layout.sheetsFillWidth
            ? layout.sideInset
            : 20
    }

    private var panelTop: CGFloat {
        layout.sheetsFillWidth
            ? layout.topChromeInset
            : 32
    }

    private var narrowest: CGFloat {
        Self.narrowestPage(for: layout)
    }

    private var cornerRadius: CGFloat {
        layout.sheetsFillWidth
            ? 0
            : GlassPanel.Radius.modal.points
    }

    private var keyboardDoneBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(.commonDone) {
                navigator?.endEditing()
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(.rect)
            .accessibilityHint(.settingsPanelKeyboardDoneHint)
        }
        .padding(.horizontal, 12)
    }

    private func panel(size: CGSize) -> some View {
        let room = max(0, size.width - sideMargin * 2)
        let width = min(CGFloat(SettingsRoute.pageWidth), room)
        let height = max(0, size.height - panelTop - floatMargin)
        let cramped = height < Self.crampedHeight
        return VStack(spacing: 0) {
            if cramped {
                keyboardDoneBar
            } else {
                SettingsPanelHeader(closeFocus: $closeFocused, window: hostWindow) {
                    setPresented(false, by: "the close button")
                }
            }
            ScrollView(.horizontal) {
                SettingsView(
                    store: store,
                    initiallyFocusTabs: false,
                    pageLayoutWidth: max(narrowest, min(1180, room)),
                    showsTabs: !cramped,
                    window: hostWindow,
                    closeFocus: $closeFocused,
                    close: { setPresented(false, by: "the settings page") }
                )
                .frame(width: max(narrowest, width))
                .frame(maxHeight: .infinity)
            }
            .scrollDisabled(width >= narrowest)
            .scrollIndicators(.never)
        }
        .frame(width: width, height: height, alignment: .top)
        .background(WindowAccessor { hostWindow = $0 })
        .menuFocusSection()
        .background(Palette.windowBackground.opacity(reduceTransparency
                        ? 1
                        : 0.7),
        in: .rect(cornerRadius: cornerRadius))
        .glassEffect(AppGlass.panel, in: .rect(cornerRadius: cornerRadius))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.18), radius: 24, x: -8, y: 8)
        .animation(
            reduceMotion
                ? nil
                : AppMotion.animation(reduced: false),
            value: width
        )
    }
}

extension SettingsPanelPresentation {
    private var quitShownHere: Bool {
        showsQuit && topControlsLayout?.settingsHost != .libraryBar
    }

    private func note(_ event: String) {
        let phase = String(describing: scenePhase)
        logger.enqueue(.diagnostic(.app, .info, "\(event); scene \(phase)"))
    }

    private func setPresented(_ value: Bool, by cause: String) {
        let asked = value
            ? "open"
            : "close"
        let was = presented
            ? "open"
            : "closed"
        note("Settings panel asked to \(asked) by \(cause); it was \(was)")
        navigator?.endEditing()
        if value {
            navigator?.inputGate.presentations.insert(presentationID)
            var opening: TimeInterval?
            withAnimation(AppMotion.animation(reduced: reduceMotion), completionCriteria: .removed) {
                root.send(.view(.openSettings))
                opening = root.settingsOpenedAt
            } completion: {
                guard let opening, root.settingsOpenedAt == opening else {
                    return
                }
                NotificationCenter.default.post(name: .settingsPanelSettled, object: hostWindow)
            }
        } else {
            navigator?.inputGate.presentations.remove(presentationID)
            root.send(.view(.closeSettings))
        }
    }

    private func updateQuitBackHandler(_ active: Bool) {
        if active, quitBackHandlerID == nil {
            quitBackHandlerID = navigator?.handlers.registerBack { window in
                guard !presented, settingsFocused || quitFocused,
                      window === hostWindow, !WindowFocus(window).hasAttachedSheet,
                      !(navigator?.inputGate.isBlocking ?? false) else {
                    return false
                }
                requestQuit(.screen)
                return true
            }
        } else if !active, let quitBackHandlerID {
            navigator?.handlers.unregister(quitBackHandlerID)
            self.quitBackHandlerID = nil
        }
    }

    private func toggleFromController(_ event: MenuCommandEvent) {
        if let ignored = ignoredToggle(
            from: event.window, host: hostWindow ?? WindowFocus.keyWindow
        ) {
            note("Settings panel ignored a toggle: \(ignored)")
            return
        }
        setPresented(!presented, by: "the controller")
    }

    private func ignoredToggle(from window: PlatformWindow?, host: PlatformWindow?) -> String? {
        guard let window else {
            return "it named no window"
        }
        guard window === host else {
            return host == nil
                ? "this panel has no window yet"
                : "it was for another window"
        }
        if WindowFocus(window).isAttachedSheet || WindowFocus(window).hasAttachedSheet {
            return "a sheet is attached"
        }
        if navigator?.inputGate.isPrompting == true {
            return "a prompt is showing"
        }
        return nil
    }

    private func focusQuitControl(_ notification: Notification) {
        guard quitShownHere, !presented, let window = notification.object as? PlatformWindow,
              window === hostWindow else {
            return
        }
        quitFocused = true
    }

    private func moveFromSettingsButton(_ direction: MenuMoveDirection) {
        if direction == .down {
            var info: [String: Any] = ["entry": LibraryFocusEntry.platform]
            if let settingsCenterX {
                info["horizontalPosition"] = settingsCenterX
            }
            NotificationCenter.default.post(
                name: .focusLibraryContent,
                object: WindowFocus.keyWindow,
                userInfo: info
            )
        } else if direction == .left {
            NotificationCenter.default.post(
                name: liveLogButtonShown
                    ? .focusLiveLogButton
                    : .focusLibraryHeader,
                object: hostWindow ?? WindowFocus.keyWindow
            )
        }
    }
}

/// Layout and focus rules of the settings panel.
extension SettingsPanelPresentation {
    /// The narrowest width a settings page is laid out at; a narrower panel scrolls horizontally.
    static let narrowestPage: CGFloat = 700

    /// The narrowest width a settings page is laid out at on a compact screen, such as a phone in landscape or
    /// an iPad in Split View.
    static let narrowestCompactPage: CGFloat = 560

    /// The panel height below which the header and tabs give their room to the page and a Done button that
    /// hides the keyboard, as when the keyboard covers most of a phone held sideways, so the field being typed
    /// in stays in view.
    static let crampedHeight: CGFloat = 300

    /// The narrowest width a settings page is laid out at for a layout.
    ///
    /// - Parameter layout: The screen's layout.
    /// - Returns: ``narrowestCompactPage`` when compact, ``narrowestPage`` otherwise.
    static func narrowestPage(for layout: ScreenLayout) -> CGFloat {
        layout.isCompact
            ? narrowestCompactPage
            : narrowestPage
    }

    /// Returns whether Settings opens as the phone's full-screen categories and pages instead of the wide panel,
    /// which happens on compact touch screens such as an iPhone.
    ///
    /// - Parameter layout: The screen's layout.
    /// - Returns: `true` on a compact touch screen.
    static func showsPhoneSettings(on layout: ScreenLayout) -> Bool {
        layout.touch && layout.isCompact
    }

    /// Returns whether closing the panel should move focus to the stream controls, which happens when the
    /// last input came from a controller.
    static func returnsToStreamControls(after mode: InputMode) -> Bool {
        mode == .controller
    }
}

/// The round button that opens the settings panel.
public struct SettingsButton: View {
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.screenLayout) private var layout
    /// Called when the button is pressed, after any text editing ends, to open the settings panel.
    public let show: () -> Void

    /// Creates a settings button.
    ///
    /// - Parameter show: Called when the button is pressed, after any text editing ends, to open the settings panel.
    public init(show: @escaping () -> Void) {
        self.show = show
    }

    public var body: some View {
        FocusButton {
            navigator?.endEditing()
            show()
        } label: {
            AppIcon.settings.image.frame(width: iconSide, height: iconSide)
        }
        .glassControlStyle()
        .focusBorderShape(.circle)
        .help(Text(.commonSettings))
        .accessibilityLabel(.commonSettings)
    }

    private var iconSide: CGFloat {
        32
    }
}

/// The settings panel's title and close button, stacked above the tab strip.
///
/// Moving right or down from the close button hands focus to the settings tabs of the panel's window.
private struct SettingsPanelHeader: View {
    /// The focus of the close button, which the settings page also moves to.
    let closeFocus: MenuFocusState<Bool>.Binding

    /// The window the panel is shown in.
    let window: PlatformWindow?

    /// Closes the panel.
    let close: () -> Void

    @Environment(\.screenLayout) private var layout

    /// The title, with the close button at the trailing edge.
    var body: some View {
        HStack {
            Text(.commonSettings).font(.headline)
            Spacer()
            FocusButton {
                close()
            } label: {
                Image(systemName: "xmark").frame(width: closeSide, height: closeSide)
            }
            .glassControlStyle().focusBorderShape(.circle)
            .menuFocused(closeFocus)
            .environment(\.menuMove) { direction in
                if direction == .right || direction == .down {
                    NotificationCenter.default.post(name: .focusSettingsTabs, object: window)
                }
            }
            .keyboardShortcut(.cancelAction)
            .help(Text(.settingsPanelCloseSettings)).accessibilityLabel(.settingsPanelCloseSettings)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
    }

    private var closeSide: CGFloat {
        24
    }

    private var horizontalPadding: CGFloat {
        layout.isCompact
            ? 16
            : 24
    }

    private var topPadding: CGFloat {
        layout.isCompact
            ? 8
            : 18
    }
}

/// Where a press outside the settings panel began, which decides whether it closes the panel.
private struct SettingsPanelPress {
    /// Whether the press began after the panel opened.
    let afterOpening: Bool

    /// The event that began the press, for the diagnostic log.
    let event: String

    /// Reads the press that is beginning now.
    ///
    /// - Parameter openedAt: The system uptime when the panel opened.
    /// - Returns: The press, which on touch screens always counts as after opening.
    @MainActor
    static func current(openedAt: TimeInterval) -> SettingsPanelPress {
        #if os(macOS)
            guard let event = NSApp.currentEvent else {
                return SettingsPanelPress(afterOpening: false, event: "no event")
            }
            let pressed = [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
                .contains(event.type)
            return SettingsPanelPress(
                afterOpening: pressed && event.timestamp >= openedAt,
                event: "event type \(event.type.rawValue)"
            )
        #else
            return SettingsPanelPress(afterOpening: true, event: "touch")
        #endif
    }
}
