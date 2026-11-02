import ChiakiDiagnostics
import ChiakiModels
import ComposableArchitecture
import Dependencies
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The library screen: the rail or compact header, the console shelf or the cloud library, and the account
/// sheet.
///
/// Everything it shows comes from ``LibraryFeature``'s state and the app data the feature reads. The view
/// owns controller focus, which only a view can hold: it walks the shelf with ``ConsoleShelfFocusGraph``,
/// applies the hand-offs the feature keeps in ``LibraryFeature/State/focusRequest``, and sends every intent
/// to the store.
struct LibraryView: View {
    /// The library.
    @Bindable var store: StoreOf<LibraryFeature>
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.requestQuit) private var requestQuit
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.logger) private var logger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.screenLayout) private var layout
    @Environment(\.quitControlShown) private var quitControlShown
    @Environment(\.libraryRailEdge) private var railEdge
    @Environment(\.liveLogButtonShown) private var liveLogButtonShown
    @AppStorage(DeveloperPreviewSetting.samplePS5) private var showsSamplePS5 = false
    @AppStorage(DeveloperPreviewSetting.samplePS4) private var showsSamplePS4 = false
    @AppStorage(DeveloperPreviewSetting.layeredConsoleCards) private var showsLayeredConsoleCards = true
    @AppStorage(DeveloperPreviewSetting.sampleConsoles) private var sampleConsoles = SampleConsoleList()
    @MenuFocusState private var focus: ConsoleLibraryFocus?
    @State private var focusMemory = LibraryFocusMemory()
    @State private var focusedWhenDisabled: ConsoleLibraryFocus?
    @State private var consoleGridWidth: CGFloat = 0
    @State private var tabCenters = [LibrarySection: CGFloat]()
    @State private var hostWindow: PlatformWindow?
    @State private var firstStopAttempt: UUID?

    var body: some View {
        LibraryLayout(
            store: store,
            shelf: shelf,
            rail: rail,
            focus: $focus,
            tabCenters: $tabCenters,
            gridWidth: $consoleGridWidth,
            actions: LibraryLayoutActions(
                apply: driver.apply,
                joinGame: {
                    driver.request(.joinGame)
                },
                playTitle: { consoleID, title in
                    driver.request(.playTitle(consoleID, title))
                },
                activateRail: driver.activateRail,
                moveRail: driver.moveRail
            )
        )
        .environment(\.libraryMenuFocused, focus.map(driver.isMenuStop) ?? false)
        .overlay {
            CloudToastLayer(toasts: store.scope(state: \.toasts, action: \.toasts))
        }
        .task {
            await store.send(.task).finish()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(
                phase == .active
                    ? .active
                    : .inactive
            ))
        }
        .onDisappear {
            store.send(.disappeared)
        }
        .onChange(of: store.section) { _, section in
            if section == .consoles {
                focusFirstConsole()
            } else {
                focus = nil
            }
        }
        .onChange(of: displayedConsoles, initial: true) { _, _ in
            reconcileFocus()
        }
        .onChange(of: focus) { _, focus in
            noteFocus(focus)
            if focus == nil {
                applyFocusRequest()
            } else if store.focusRequest != nil, hostWindow != nil {
                store.send(.focusRequestHandled)
            }
        }
        .onChange(of: hostWindow) { _, _ in
            applyFocusRequest()
        }
        .onChange(of: store.selectedAccount) { _, _ in
            reconcileFocus()
        }
        .onChange(of: store.focusRequest, initial: true) { _, _ in
            applyFocusRequest()
        }
        .onChange(of: store.consoleLoad) { _, _ in
            applyFocusRequest()
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                restoreFocus()
            } else {
                focusedWhenDisabled = focus
            }
        }
        .onAppear {
            applyFocusRequest()
        }
        .menuHandlers(enabled: isEnabled, back: { window in
            guard window === hostWindow, QuitBack.available(in: window, navigator: navigator),
                  focus?.backQuits == true else {
                return false
            }
            if !rail.contains(focus), driver.focusRail() {
                return true
            }
            requestQuit(.screen)
            return true
        })
        .modifier(LibraryFocusSignals(
            window: hostWindow,
            togglesMenu: store.cloudLibrary.selectedGame == nil,
            content: { store.send(.contentFocusRequested($0)) },
            header: {
                if !driver.focusRail() {
                    focus = .profile
                }
            },
            quit: { focus = .quit },
            liveLogOpener: {
                if rail.contains(.log) {
                    focus = .log
                }
            },
            toggleMenu: driver.toggleMenu
        ))
        .background(WindowAccessor { hostWindow = $0 })
    }

    private var rail: LibraryRail {
        store.state.rail(edge: railEdge, showsQuit: quitControlShown, showsLog: liveLogButtonShown)
    }

    private var displayedConsoles: [DisplayedConsole] {
        var consoles = store.linkedConsoles.map {
            DisplayedConsole(target: $0, preview: false)
        }
        #if DEBUG
            if showsSamplePS5 {
                consoles.append(DisplayedConsole(target: DisplayedConsole.sample(.ps5), preview: true))
            }
            if showsSamplePS4 {
                consoles.append(DisplayedConsole(target: DisplayedConsole.sample(.ps4), preview: true))
            }
        #endif
        return consoles + sampleConsoles.displayed()
    }

    private var shelf: LibraryShelf {
        LibraryShelf(
            state: store.state,
            consoles: displayedConsoles,
            gridWidth: consoleGridWidth,
            layeredArt: showsLayeredConsoleCards,
            compact: layout.isCompact,
            stacked: layout.isCompact && !layout.isShort,
            recentOrigin: focusMemory.recentOrigin,
            tabCenters: tabCenters
        )
    }

    private func applyFocusRequest() {
        guard isEnabled, hostWindow != nil, let request = store.focusRequest else {
            return
        }
        let resolver = LibraryFocusResolver(
            section: store.section,
            waiting: store.consoleLoad.isWaiting,
            graph: shelf.graph,
            rail: rail,
            compact: layout.isCompact,
            focus: focus
        )
        switch resolver.resolve(request) {
        case .focus(let target):
            focus = target
        case .handled:
            store.send(.focusRequestHandled)
        case .firstConsole:
            store.send(.focusRequestHandled)
            focusFirstConsole()
        case .wait:
            break
        }
    }

    private func focusFirstConsole() {
        guard store.section == .consoles, !store.consoleLoad.isWaiting else {
            return
        }
        focus = shelf.graph.firstStop
        let attempt = UUID()
        firstStopAttempt = attempt
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(30))
                guard firstStopAttempt == attempt, isEnabled, store.section == .consoles else {
                    return
                }
                let target = shelf.graph.firstStop
                if focus != target {
                    focus = target
                }
            }
            if firstStopAttempt == attempt {
                firstStopAttempt = nil
            }
        }
    }

    private func reconcileFocus() {
        guard store.section == .consoles, !store.consoleLoad.isWaiting, !shelf.graph.keeps(focus),
              focus != nil || store.focusRequest == nil else {
            return
        }
        focusFirstConsole()
    }

    private func restoreFocus() {
        let held = focusedWhenDisabled
        focusedWhenDisabled = nil
        guard store.section == .consoles else {
            guard let held, driver.isMenuStop(held) else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                focus = nil
                await Task.yield()
                focus = held
            }
            return
        }
        if let target = focusMemory.restored(among: shelf.consoles, shownBy: shelf.graph) {
            focus = target
        } else {
            focusFirstConsole()
        }
    }

    private func noteFocus(_ focus: ConsoleLibraryFocus?) {
        guard let focus else {
            return
        }
        focusMemory.note(focus, inRail: rail.contains(focus))
        if store.heldFocus != focus {
            store.send(.focusMoved(focus))
        }
    }

    private var driver: LibraryFocusDriver {
        LibraryFocusDriver(
            store: store,
            focus: $focus,
            shelf: shelf,
            rail: rail,
            memory: focusMemory,
            firstStopAttempt: $firstStopAttempt,
            focusFirstConsole: focusFirstConsole,
            navigator: navigator,
            window: hostWindow,
            compact: layout.isCompact,
            reduceMotion: reduceMotion,
            requestQuit: requestQuit,
            logger: logger
        )
    }
}

/// Moves the library's controller focus for the rail, the header and the console shelf, and carries out what
/// their stops stand for.
///
/// The library view creates it from its current state for each request; it changes focus through the view's
/// focus binding and sends intents to the store.
@MainActor
private struct LibraryFocusDriver {
    /// The library.
    let store: StoreOf<LibraryFeature>

    /// The library's controller focus.
    let focus: MenuFocusState<ConsoleLibraryFocus?>.Binding

    /// What the console shelf shows and how focus moves across it.
    let shelf: LibraryShelf

    /// The rail's stops.
    let rail: LibraryRail

    /// Where focus has been.
    let memory: LibraryFocusMemory

    /// The running attempt to settle focus on the shelf's first stop, which any other move ends.
    let firstStopAttempt: Binding<UUID?>

    /// Focuses the shelf's first stop and keeps it there briefly while the shelf settles, unless another
    /// section is shown or the shelf waits for consoles.
    let focusFirstConsole: @MainActor () -> Void

    /// The navigator that owns controller focus and text editing.
    let navigator: PlatformMenuNavigator?

    /// The window the library is shown in.
    let window: PlatformWindow?

    /// Whether the window is compact, with the header bar instead of the rail.
    let compact: Bool

    /// Whether Reduce Motion is on.
    let reduceMotion: Bool

    /// Asks to quit the app.
    let requestQuit: RequestQuitAction

    /// The diagnostic log the rail's requests are written to.
    let logger: LoggerClient

    /// Applies a focus move the shelf graph decided.
    ///
    /// - Parameter move: The move.
    func apply(_ move: ConsoleShelfFocusGraph.Move) {
        firstStopAttempt.wrappedValue = nil
        switch move {
        case .focus(let target):
            focus.wrappedValue = target
        case .leave(let direction):
            leaveContent(direction)
        case .firstConsole:
            focusFirstConsole()
        case .content(let request):
            store.send(.contentFocusRequested(request))
        case .stay:
            break
        }
    }

    /// Focuses the rail stop of the shown section.
    ///
    /// - Returns: Whether there is a rail to focus.
    @discardableResult
    func focusRail() -> Bool {
        guard !compact else {
            return false
        }
        focus.wrappedValue = rail.entry(for: store.section)
        return true
    }

    /// Moves focus from the content to the rail, when the rail lies in that direction.
    ///
    /// - Parameter direction: The direction focus leaves in.
    /// - Returns: Whether focus reached the rail.
    @discardableResult
    func leaveContent(_ direction: MenuMoveDirection) -> Bool {
        guard rail.entered(leaving: direction) else {
            return false
        }
        return focusRail()
    }

    /// Moves focus from a rail stop.
    ///
    /// - Parameters:
    ///   - current: The focused rail stop.
    ///   - direction: The direction pressed.
    func moveRail(from current: ConsoleLibraryFocus, _ direction: MenuMoveDirection) {
        firstStopAttempt.wrappedValue = nil
        switch rail.move(from: current, direction) {
        case .stop(let next):
            focus.wrappedValue = next
        case .content:
            enterContent()
        case .stay:
            break
        }
    }

    /// Does what a rail stop stands for.
    ///
    /// - Parameter stop: The activated stop.
    func activateRail(_ stop: ConsoleLibraryFocus) {
        switch stop {
        case .librarySection(let section) where section == store.section:
            enterContent()
        case .librarySection(let section):
            selectSection(section)
            if section == store.section {
                enterContent()
            }
        case .joinGame:
            request(.joinGame)
        case .notifications:
            store.send(.alertsTapped)
        case .settings:
            navigator?.endEditing()
            logger.enqueue(.diagnostic(.app, .info, "Rail asked Settings to open"))
            navigator?.commands.send(.settings, to: window ?? WindowFocus.keyWindow)
        case .log:
            NotificationCenter.default.post(name: .toggleLiveLog, object: window ?? WindowFocus.keyWindow)
        case .profile:
            store.send(.accountTapped)
        case .quit:
            requestQuit(.button)
        default:
            break
        }
    }

    /// Moves between the content and the menu, as Triangle does: from the content to the shown section's
    /// stop in the rail, or the header tab in a compact window, and from a menu stop back into the content.
    func toggleMenu() {
        firstStopAttempt.wrappedValue = nil
        if let current = focus.wrappedValue, isMenuStop(current) {
            enterContent()
        } else {
            focus.wrappedValue = compact
                ? .librarySection(store.section)
                : rail.entry(for: store.section)
        }
    }

    /// Whether a stop belongs to the menu: the rail, or the header's tabs and buttons in a compact window.
    ///
    /// - Parameter stop: The stop.
    /// - Returns: `true` for a menu stop.
    func isMenuStop(_ stop: ConsoleLibraryFocus) -> Bool {
        guard compact else {
            return rail.contains(stop)
        }
        switch stop {
        case .librarySection, .joinGame, .notifications, .profile, .settings, .log, .quit:
            return true
        default:
            return false
        }
    }

    /// Moves focus from the rail into the shown section, back to where it last was.
    func enterContent() {
        if store.section != .consoles {
            store.send(.contentFocusRequested(LibraryContentFocus(.resume)))
            return
        }
        if let target = memory.content(shownBy: shelf.graph) {
            focus.wrappedValue = target
        } else {
            focusFirstConsole()
        }
    }

    /// Shows another section, unless it is shown or cannot be.
    ///
    /// - Parameter section: The section.
    func selectSection(_ section: LibrarySection) {
        guard section != store.section, section != .cloud || !store.cloudUnavailable else {
            return
        }
        navigator?.endEditing()
        withAnimation(AppMotion.animation(reduced: reduceMotion)) {
            _ = store.send(.sectionSelected(section))
        }
    }

    /// Asks the app for something, releasing focus first.
    ///
    /// - Parameter request: What is asked.
    func request(_ request: LibraryRequest) {
        if let window = WindowFocus.keyWindow {
            navigator?.resignFocus(in: window)
        }
        store.send(.requested(request))
    }
}

/// What the library remembers about where focus has been, so it can return there.
///
/// It keeps the last stop that had focus, the last stop of the content rather than the rail, and the console
/// the recently played rows were last entered from.
private struct LibraryFocusMemory: Equatable {
    /// The last stop that had focus.
    private(set) var last: ConsoleLibraryFocus?

    /// The last stop of the content, outside the rail, that had focus.
    private(set) var lastContent: ConsoleLibraryFocus?

    /// The console the recently played rows were last entered from.
    private(set) var recentOrigin: UUID?

    /// Records a stop that took focus.
    ///
    /// - Parameters:
    ///   - focus: The stop.
    ///   - inRail: Whether the stop belongs to the rail.
    mutating func note(_ focus: ConsoleLibraryFocus, inRail: Bool) {
        last = focus
        if !inRail {
            lastContent = focus
        }
        switch focus {
        case .console(let item), .action(let item, _):
            recentOrigin = item.target.id
        default:
            break
        }
    }

    /// The stop focus returns to when the library is enabled again.
    ///
    /// - Parameters:
    ///   - consoles: The consoles the shelf shows.
    ///   - graph: How focus moves across the console shelf.
    /// - Returns: The last stop, unless it was a console that is gone or a stop the shelf no longer shows.
    func restored(
        among consoles: [DisplayedConsole],
        shownBy graph: ConsoleShelfFocusGraph
    ) -> ConsoleLibraryFocus? {
        switch last {
        case .console(let item), .action(let item, _):
            consoles.contains(item)
                ? last
                : nil
        default:
            graph.keeps(last)
                ? last
                : nil
        }
    }

    /// The stop focus returns to when it enters the content from the rail.
    ///
    /// - Parameter graph: How focus moves across the console shelf.
    /// - Returns: The last content stop, while the shelf still shows it.
    func content(shownBy graph: ConsoleShelfFocusGraph) -> ConsoleLibraryFocus? {
        guard let lastContent, graph.shows(lastContent) else {
            return nil
        }
        return lastContent
    }
}

/// Decides where a library focus hand-off lands on the screen as it is now.
///
/// Hand-offs into the console shelf wait while the shelf waits for the console catalog, and are dropped when
/// another section is shown. A hand-off to the stop that already has focus is done at once.
private struct LibraryFocusResolver {
    /// What to do with a hand-off.
    enum Resolution: Equatable {
        /// Focus this stop.
        case focus(ConsoleLibraryFocus)
        /// The hand-off is done without moving focus.
        case handled
        /// The hand-off is done, and focus settles on the shelf's first stop even when it is already there.
        case firstConsole
        /// Keep the hand-off until the shelf can take it.
        case wait
    }

    /// The section shown.
    let section: LibrarySection

    /// Whether the shelf waits for the console catalog.
    let waiting: Bool

    /// How focus moves across the console shelf.
    let graph: ConsoleShelfFocusGraph

    /// The rail's stops.
    let rail: LibraryRail

    /// Whether the window is compact, with the header bar instead of the rail.
    let compact: Bool

    /// The stop that has focus.
    let focus: ConsoleLibraryFocus?

    /// Where a hand-off lands.
    ///
    /// - Parameter request: The hand-off.
    /// - Returns: What to do with it.
    func resolve(_ request: LibraryFocusRequest) -> Resolution {
        let target: ConsoleLibraryFocus?
        switch request {
        case .firstConsole:
            guard section == .consoles else {
                return .handled
            }
            guard !waiting else {
                return .wait
            }
            return .firstConsole
        case .resume(let held):
            guard section == .consoles else {
                return .handled
            }
            guard !waiting else {
                return .wait
            }
            guard graph.keeps(held) else {
                return .firstConsole
            }
            target = held
        case .stop(let stop):
            target = stop
        case .returnToAccount:
            target = focus == nil
                ? .profile
                : nil
        case .rail:
            target = compact
                ? nil
                : rail.entry(for: section)
        case let .leftCloud(direction, fromFilter):
            target = leftCloud(direction, fromFilter: fromFilter)
        case .leftSection(let direction):
            target = leftSection(direction)
        }
        guard let target, target != focus else {
            return .handled
        }
        return .focus(target)
    }

    private func leftSection(_ direction: MenuMoveDirection) -> ConsoleLibraryFocus? {
        if !compact {
            return rail.entered(leaving: direction)
                ? rail.entry(for: section)
                : nil
        }
        return direction == .up
            ? .librarySection(section)
            : nil
    }

    private func leftCloud(_ direction: MenuMoveDirection, fromFilter: Bool) -> ConsoleLibraryFocus? {
        if !compact {
            return rail.entered(leaving: direction)
                ? rail.entry(for: section)
                : nil
        }
        if direction == .up {
            return fromFilter
                ? .librarySection(.cloud)
                : .profile
        }
        return nil
    }
}

/// Receives the requests other parts of the window send the library to take focus: into its content, onto
/// its header, Quit control or live log stop, or between the content and the menu.
///
/// Requests aimed at another window, and requests while the library is disabled, are ignored.
private struct LibraryFocusSignals: ViewModifier {
    /// The window the library is shown in.
    let window: PlatformWindow?

    /// Whether Triangle, or the stream menu buttons outside a stream, may move between the content and the menu.
    let togglesMenu: Bool

    /// Enters the content.
    let content: (LibraryContentFocus) -> Void

    /// Focuses the rail, or the profile when there is no rail.
    let header: () -> Void

    /// Focuses the Quit control.
    let quit: () -> Void

    /// Focuses the rail's live log stop.
    let liveLogOpener: () -> Void

    /// Moves between the content and the menu.
    let toggleMenu: () -> Void

    @Environment(\.menuNavigator) private var navigator
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.screenLayout) private var layout
    @Environment(\.quitControlShown) private var quitControlShown

    /// The content, listening for the window's focus requests.
    ///
    /// - Parameter body: The library.
    /// - Returns: The library with the requests applied.
    func body(content body: Content) -> some View {
        body
            .onReceive(NotificationCenter.default.publisher(for: .focusLibraryContent)) { notification in
                guard isEnabled, Self.ownsKeyWindow(notification) else {
                    return
                }
                content(Self.contentFocus(of: notification))
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusLibraryHeader)) { notification in
                guard isEnabled, Self.ownsKeyWindow(notification) else {
                    return
                }
                header()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusQuitControl)) { notification in
                guard !layout.isCompact, quitControlShown,
                      let source = notification.object as? PlatformWindow,
                      source === window else {
                    return
                }
                quit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusLiveLogOpener)) { notification in
                guard !layout.isCompact, let source = notification.object as? PlatformWindow,
                      source === window else {
                    return
                }
                liveLogOpener()
            }
            .onMenuCommand([.focusToolbar, .streamMenu]) { event in
                guard isEnabled, !(navigator?.inputGate.isBlocking ?? false),
                      !(navigator?.isTrackingMenu ?? false),
                      togglesMenu, let source = event.window, source === window else {
                    return
                }
                toggleMenu()
            }
    }

    private static func ownsKeyWindow(_ notification: Notification) -> Bool {
        guard let window = notification.object as? PlatformWindow else {
            return false
        }
        return window === WindowFocus.keyWindow
    }

    private static func contentFocus(of notification: Notification) -> LibraryContentFocus {
        LibraryContentFocus(
            notification.userInfo?["entry"] as? LibraryFocusEntry ?? .selectedFilter,
            horizontalPosition: (notification.userInfo?["horizontalPosition"] as? CGFloat).map(Double.init)
        )
    }
}
