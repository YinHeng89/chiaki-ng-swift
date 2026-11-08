import ChiakiClients
import ChiakiModels
import PlatformUI
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus

/// Streaming chrome that layers the diagnostics overlay and the stream menu dock over a playing stream, and
/// drives its gameplay and panel navigation levels by controller.
///
/// The dock rises from the bottom with the controller shortcut, which opens its last panel, and for the
/// pointer from a handle that shows near the bottom. As the stream starts a hint naming both ways shows for
/// a few seconds instead. Settings sits in the dock after the divider.
struct StreamMenuOverlay: View {
    /// The window's menu navigator, used to register focus move, activation and Back handlers and to
    /// gate input while another presentation is in front.
    @Environment(\.menuNavigator) var navigator
    /// The controller driving menus, which the overlay takes from and hands back to the stream.
    @Environment(\.controllerNavigation) var controllerNavigation
    /// The on-screen gamepad, which gives way while the menu is open.
    @Environment(\.virtualGamepad) var virtualGamepad
    /// Records what asked the stream to stop.
    @Environment(\.streamStopTrace) var stopTrace
    /// The stream menu store that holds the draft tuning configuration, diagnostics and navigation level.
    let store: StoreOf<StreamMenuReducer>
    /// The title of the destructive button that ends the stream, such as stopping or leaving it.
    let stopTitle: LocalizedStringResource
    /// The couch co-op store behind the Players panel, or `nil` when local players are not available.
    var couch: StoreOf<CouchReducer>?
    /// The Share Play host store whose remote players appear in the Players panel, or `nil`
    /// without Share Play.
    var kakusan: StoreOf<KakusanHostFeature>?
    /// The microphone store behind the Sound panel's microphone button and the microphone toggle shortcut.
    var microphone: StoreOf<MicrophoneReducer>?
    /// The Invitations panel's store, during a cloud stream.
    var invitations: StoreOf<CloudInvitationsFeature>?
    /// The Trophies panel's store, during a cloud stream whose game names a title id.
    var trophies: StoreOf<StreamTrophiesFeature>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.screenLayout) private var layout
    /// Whether the live developer log is turned on, which adds its item to the dock.
    @Environment(\.liveLogButtonShown) var liveLogButtonShown
    /// The chrome corners currently visible, which decide whether the dock's handle shows.
    @Environment(\.streamChromeVisibleCorners) private var visibleCorners
    /// How much of the dock shows while the chrome is visible.
    @Environment(\.streamDock) private var streamDock
    /// Shows the dock from its handle.
    @Environment(\.expandStreamDock) private var expandDock
    /// The controller buttons that open the stream menu, named in the dock's hint.
    @Environment(\.streamMenuShortcut) private var shortcut
    /// The identity this overlay registers with the input gate while it holds controller navigation.
    @State var presentationID = UUID()
    /// Which slider, if any, the controller is adjusting.
    @State var sliderNavigation = StreamMenuSliderNavigationState.navigating
    /// The menu element that holds controller focus, or `nil` when gameplay has the controller.
    @MenuFocusState var focusTarget: StreamMenuFocusTarget?
    /// The registration of the focus move handler, kept so it can be removed when navigation ends.
    @State var focusMoveHandlerID: MenuHandlerID?
    /// The registration of the activation handler for the top controls, kept so it can be removed later.
    @State var activationHandlerID: MenuHandlerID?
    /// The registration of the Back handler that cancels controller picking, kept so it can be removed later.
    @State var backHandlerID: MenuHandlerID?
    /// The most recent non-empty focus target, restored when another presentation closes.
    @State var lastFocusTarget: StreamMenuFocusTarget?
    /// The player seat that last held focus in the Players panel, used to keep vertical moves in that column.
    @State var lastPlayerSeat: UInt8?
    /// The Trophies panel control focus is moving to, set before focus so its page shows first.
    @State var trophiesAnchor: StreamMenuControl?
    /// Whether the Trophies panel was entered on Refresh because no trophy was shown yet, so focus moves to the
    /// first trophy once the list arrives.
    @State var trophiesEntryWaits = false
    /// The overlay's height, which decides how many trophies a page of the Trophies panel holds.
    @State var overlayHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            diagnosticsOverlay
            if store.videoDisabled {
                StreamVideoOffNotice()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Group {
                if !store.diagnostics.level.visible,
                   let percent = store.diagnostics.lossWarning.visiblePercent {
                    PacketLossBadge(percent: percent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 38)
                        .transition(.opacity)
                }
            }
            .animation(
                AppMotion.animation(reduced: reduceMotion),
                value: store.diagnostics.lossWarning.visiblePercent == nil
            )
            measuringCard
            if panelPresented {
                Dimming.standard.color
                    .contentShape(Rectangle())
                    .onTapGesture {
                        returnToGameplay()
                    }
                    .transition(.opacity)
            }
            dockLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            overlayHeight = height
        }
        .disabled(navigator?.inputGate.isBlocking(besides: presentationID) ?? false)
        .animation(AppMotion.animation(reduced: reduceMotion), value: panelPresented)
        .animation(AppMotion.animation(reduced: reduceMotion), value: dockPresentation)
        .modifier(StreamMicrophoneToggleReceiver(microphone: microphone))
        .onReceive(NotificationCenter.default.publisher(for: .controllerFamilyChanged)) { _ in
            if navigationActive, !(controllerNavigation?.navigationConnected ?? false) {
                returnToGameplay()
            }
        }
        .streamChromePinned(.bottom, navigationActive)
        .background(DismissOnOutsideClick(active: navigationActive) {
            returnToGameplay()
        })
        .onMenuCommand([.streamMenu]) { event in
            guard !hasOtherPresentation else {
                return
            }
            if let window = event.window,
               window !== PlaybackWindowControl.keyWindow {
                return
            }
            toggle()
        }
        .onMenuCommand([.settings]) { event in
            guard let window = event.window,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            returnToGameplay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusStreamMenu)) { notification in
            guard let window = notification.object as? PlatformWindow,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            open()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLiveLogOpener)) { notification in
            guard liveLogButtonShown, let window = notification.object as? PlatformWindow,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            open(focusing: .log)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusStreamMenuSettings)) { notification in
            guard let window = notification.object as? PlatformWindow,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            open(focusing: .settings)
        }
        .onMenuCommand([.previous]) { event in
            guard panelPresented,
                  let window = event.window,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            moveTabFocus(by: -1, selecting: true)
        }
        .onMenuCommand([.alternate]) { event in
            guard panelPresented, panel == .trophies, !hasOtherPresentation,
                  let window = event.window,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            trophiesAnchor = .trophiesFilter
            focusTarget = .control(.trophiesFilter)
        }
        .onMenuCommand([.next]) { event in
            guard panelPresented,
                  let window = event.window,
                  window === PlaybackWindowControl.keyWindow else {
                return
            }
            moveTabFocus(by: 1, selecting: true)
        }
        .onChange(of: focusTarget) { _, _ in
            if case .adjusting(let control, _) = sliderNavigation,
               focusTarget != .control(control) {
                sliderNavigation.leave()
            }
            if case .control(let control) = focusTarget, control != .trophiesRefresh {
                trophiesEntryWaits = false
            }
        }
        .onChange(of: trophies?.shown.first?.id) { _, first in
            guard trophiesEntryWaits, focusTarget == .control(.trophiesRefresh), let first else {
                return
            }
            trophiesEntryWaits = false
            trophiesAnchor = .trophy(first)
            focusTarget = .control(.trophy(first))
        }
        .onChange(of: navigationActive) { _, active in
            guard !active, navigator?.inputGate.presentations.contains(presentationID) == true else {
                return
            }
            handBackController()
        }
        .onChange(of: couch
            .map { StreamPlayersPanel.controls(for: $0.state, kakusan: kakusan?.state)
            }) { _, controls in
                guard panel == .players, let controls, case .control(let control) = focusTarget,
                      !controls.contains(control), let first = controls.first else {
                    return
                }
                focusTarget = .control(first)
        }
        .task(id: store.context) {
            store.send(.load)
        }
        .modifier(StreamDiagnosticsLifecycle(store: store))
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                returnToGameplay()
            }
        }
        .modifier(StreamMenuTouchYield(level: navigationLevel))
        .onDisappear {
            virtualGamepad?.send(.streamMenuChanged(.closed))
            store.send(.disappeared)
            unregisterFocusMoveHandler()
            navigator?.inputGate.presentations.remove(presentationID)
            store.send(.diagnostics(.selectAnalysis(.off)))
        }
        .modifier(StreamMenuFocusContinuity(overlay: self))
        .onMenuExitCommand(perform: exitLevel)
    }
}

extension StreamMenuOverlay {
    private var menuTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    /// The level controller navigation is at in the menu.
    var navigationLevel: StreamMenuReducer.Navigation.Level {
        store.navigation.level
    }

    /// The panel the menu shows, or reopens on.
    var panel: StreamMenuPanel {
        store.navigation.panel
    }

    /// Whether the menu holds controller navigation.
    var navigationActive: Bool {
        store.navigation.isActive
    }

    @ViewBuilder private var measuringCard: some View {
        if navigationLevel == .measuring {
            StreamBrightnessMeasureCard(
                focus: $focusTarget,
                nudge: { step in
                    store.send(.nudgeMarker(step))
                },
                done: finishMeasuring
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .topChromeInset()
            .padding(.top, 12)
            .transition(.opacity)
        }
    }

    /// Whether the bottom panel menu is showing, which is the case at the panel navigation level.
    var panelPresented: Bool {
        navigationLevel == .panel
    }

    /// What the dock layer shows: nothing, the stream start hint, the handle, the dock alone, or the dock
    /// with the open panel.
    enum DockPresentation: Equatable {
        /// Nothing shows.
        case hidden
        /// Only the hint that teaches how to reach the dock shows.
        case hint
        /// Only the handle shows.
        case handle
        /// The dock shows without a panel.
        case dock
        /// The dock shows with the open panel.
        case panel
    }

    /// What the dock layer shows now.
    var dockPresentation: DockPresentation {
        if panelPresented {
            return .panel
        }
        guard visibleCorners.contains(.bottom) else {
            return .hidden
        }
        switch streamDock {
        case .collapsed:
            return .handle
        case .introduced:
            return .hint
        case .expanded:
            return .dock
        }
    }

    @ViewBuilder private var dockLayer: some View {
        switch dockPresentation {
        case .hidden:
            EmptyView()
        case .handle:
            StreamDockHandle(opensMenu: layout.touch, height: max(32, layout.controlSize)) {
                if layout.touch {
                    open()
                } else {
                    expandDock()
                }
            }
            .padding(.bottom, 18)
            .transition(.opacity)
        case .hint:
            Text(StreamDockHint.text(
                shortcut: shortcut,
                family: (controllerNavigation?.navigationConnected ?? false)
                    ? controllerNavigation?.navigationFamily
                    : nil
            ))
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(AppGlass.control, in: .capsule)
            .padding(.bottom, 24)
            .transition(.opacity)
        case .dock:
            rail
                .padding(.horizontal, sideMargin)
                .padding(.bottom, bottomMargin)
                .transition(menuTransition)
        case .panel:
            menu
                .padding(.horizontal, sideMargin)
                .padding(.top, layout.isCompact
                    ? 8
                    : 0)
                    .padding(.bottom, bottomMargin)
                    .transition(menuTransition)
        }
    }

    /// How many trophies a page of the Trophies panel holds: as many rows of about 90 points as fit once the
    /// rest of the panel, the dock and the margins have about 540 points, from two to eight.
    var trophiesRows: Int {
        let fitting = Int((overlayHeight - 540) / 90)
        return min(8, max(2, fitting))
    }

    private var sideMargin: CGFloat {
        if layout.touch || layout.isCompact {
            return max(16, layout.sideInset)
        }
        return 28
    }

    private var bottomMargin: CGFloat {
        layout.bottomChromeInset
    }

    private var fittedPanelContent: some View {
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView(.vertical) {
                panelContent
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var menu: some View {
        VStack(spacing: layout.isCompact
            ? 8
            : 14) {
                fittedPanelContent
                    .frame(maxWidth: 700)
                    .padding(layout.isCompact
                        ? 14
                        : 24)
                        .tint(Palette.accent)
                        .glassPanel(.large)
                        .shadow(color: .black.opacity(0.25), radius: 28, y: 12)
                        .overlay {
                            FocusHighlightOverlay()
                                .allowsHitTesting(false)
                        }
                rail
            }
            .menuFocusSection()
    }

    @ViewBuilder private var panelContent: some View {
        if store.loaded {
            StreamMenuPanelContent(
                panel: panel,
                configuration: streamConfiguration,
                statistics: store.diagnostics.telemetry.statistics,
                diagnosticsLevel: diagnosticsBinding(\.level) { .selectLevel($0) },
                diagnosticsGlass: diagnosticsBinding(\.glass) { .selectGlass($0) },
                diagnosticsLayout: diagnosticsBinding(\.layout) { .selectLayout($0) },
                videoAnalysis: Binding(
                    get: {
                        store.diagnostics.analysis
                    },
                    set: { mode in
                        store.send(.diagnostics(.selectAnalysis(mode)))
                    }
                ),
                troubleshootTopic: Binding(
                    get: {
                        store.troubleshootTopic
                    },
                    set: { topic in
                        store.send(.selectTroubleshootTopic(topic))
                    }
                ),
                frameGenerationEligible: frameGenerationEligible,
                audio3DDisabledReason: store.audio3DDisabledReason,
                stopTitle: stopTitle,
                stop: stopAfterSaving,
                goHome: homeAction,
                openSavedData: savedDataAction,
                restart: {
                    store.send(.restartStream)
                },
                measureBrightness: measureBrightnessAction,
                datacenter: store.datacenter,
                bandwidth: store.bandwidth,
                focus: $focusTarget,
                focusedControl: focusedControl,
                couch: couch,
                kakusan: kakusan,
                microphone: microphone,
                invitations: invitations,
                trophies: trophies,
                trophiesPaging: StreamTrophiesPaging(
                    anchor: trophiesAnchor ?? focusedControl,
                    rows: trophiesRows
                )
            )
            .environment(\.streamMenuActivate) { control in
                activateControl(control)
            }
            .environment(\.streamMenuSliderAdjusting, sliderNavigation.adjustingSlider)
        } else {
            VStack(spacing: 12) {
                if store.phase == .failed {
                    Text(.playbackMenuLoadFailed)
                        .foregroundStyle(.secondary)
                    FocusButton(.commonTryAgain) {
                        store.send(.load)
                    }
                    .glassControlStyle()
                    .menuFocused($focusTarget, equals: .control(.retryLoad))
                } else {
                    ProgressView()
                    Text(.playbackMenuLoading)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private var rail: some View {
        ViewThatFits(in: .horizontal) {
            railItems(.labelled)
            railItems(.iconOnly)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    railItems(.iconOnly)
                }
                .scrollIndicators(.hidden)
                .onChange(of: panel, initial: true) { _, item in
                    proxy.scrollTo(StreamMenuFocusTarget.tab(item))
                }
            }
        }
        .padding(7)
        .glassEffect(AppGlass.control, in: .capsule)
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }

    /// How the dock's items are drawn: with a caption under the icon, or as the icon alone when captions
    /// would not fit.
    enum RailStyle {
        /// The icon with its caption, 86 by 54 points.
        case labelled
        /// The icon alone, 54 by 44 points.
        case iconOnly
    }

    private func railItems(_ style: RailStyle) -> some View {
        HStack(spacing: 6) {
            ForEach(panels, id: \.self) { item in
                railTab(item, style: style)
            }
            Divider().frame(height: 36).padding(.horizontal, 4)
            FocusButton {
                openSettings()
            } label: {
                railLabel(AppIcon.settings.image, .commonSettings, style: style)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focusHighlightShape(.capsule)
            .focusWithoutGrowth()
            .menuFocused($focusTarget, equals: .settings)
            .foregroundStyle(.secondary)
            if liveLogButtonShown {
                railLogItem(style: style)
            }
            if panelPresented {
                railExitItem
            }
        }
    }

    private func railTab(_ item: StreamMenuPanel, style: RailStyle) -> some View {
        FocusButton {
            if navigationActive {
                focusTarget = .tab(item)
                selectPanelFromTab(item)
            } else {
                store.send(.selectPanel(item))
                open(focusing: .tab(item))
            }
        } label: {
            railLabel(Image(systemName: item.symbol), item.title, style: style)
                .background(selectionBackground(item), in: .capsule)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.capsule)
        .focusWithoutGrowth()
        .menuFocused($focusTarget, equals: .tab(item))
        .foregroundStyle(tone(item))
        .accessibilityAddTraits(selectionTraits(item))
        .id(StreamMenuFocusTarget.tab(item))
    }

    private func railLogItem(style: RailStyle) -> some View {
        FocusButton {
            NotificationCenter.default.post(
                name: .toggleLiveLog,
                object: PlaybackWindowControl.keyWindow
            )
        } label: {
            railLabel(AppIcon.logging.image, .playbackMenuDockLog, style: style)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.capsule)
        .focusWithoutGrowth()
        .menuFocused($focusTarget, equals: .log)
        .foregroundStyle(.secondary)
        .accessibilityLabel(.playbackMenuDockLogAccessibility)
    }

    private var railExitItem: some View {
        FocusButton {
            returnToGameplay()
        } label: {
            Image(systemName: "xmark")
                .frame(width: max(42, layout.controlSize), height: max(42, layout.controlSize))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .menuFocusBinding($focusTarget, equals: .exit)
        .focusHighlightShape(.circle)
        .environment(\.menuItemFocused, focusTarget == .exit)
        .help(Text(.playbackMenuResumeStream))
        .accessibilityLabel(.playbackMenuResumeStream)
    }

    @ViewBuilder private func railLabel(_ icon: Image, _ title: LocalizedStringResource,
                                        style: RailStyle) -> some View {
        switch style {
        case .iconOnly:
            icon
                .font(.system(size: 18, weight: .medium))
                .frame(width: 54, height: 44)
                .accessibilityLabel(title)
        case .labelled:
            VStack(spacing: 6) {
                icon
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption)
            }
            .frame(width: 86, height: 54)
        }
    }

    /// Whether generated 120 fps presentation can be offered, which needs the feature available and a display
    /// that refreshes at least twice as fast as the stream's source frame rate.
    var frameGenerationEligible: Bool {
        store.draft.frameGenerationAvailable
            && PlaybackWindowControl.displayMaximumFramesPerSecond >= store.draft.sourceFPS * 2
    }

    private func diagnosticsBinding<Value>(
        _ key: KeyPath<StreamDiagnosticsAppearance, Value>,
        _ action: @escaping (Value) -> StreamDiagnosticsReducer.Action
    ) -> Binding<Value> {
        Binding(
            get: {
                store.diagnostics.appearance[keyPath: key]
            },
            set: { value in
                store.send(.diagnostics(action(value)))
            }
        )
    }

    private var diagnosticsOverlay: some View {
        StreamDiagnosticsOverlay(
            report: StreamDiagnosticsReport(
                telemetry: store.diagnostics.telemetry,
                history: store.diagnostics.history,
                datacenter: store.datacenter
            ),
            appearance: store.diagnostics.appearance,
            analysisMode: store.diagnostics.analysis,
            selectLevel: { level in
                store.send(.diagnostics(.selectLevel(level)))
            },
            selectGlass: { glass in
                store.send(.diagnostics(.selectGlass(glass)))
            },
            selectLayout: { layout in
                store.send(.diagnostics(.selectLayout(layout)))
            }
        )
    }

    private var streamConfiguration: Binding<StreamTuningConfiguration> {
        Binding(
            get: {
                store.draft
            },
            set: { value in
                store.send(.edit(value))
            }
        )
    }
}

private struct StreamDiagnosticsLifecycle: ViewModifier {
    let store: StoreOf<StreamMenuReducer>

    func body(content: Content) -> some View {
        content
            .task {
                await store.send(.diagnostics(.task)).finish()
            }
            .onReceive(NotificationCenter.default
                .publisher(for: .cycleStreamDiagnosticsLevel)) { notification in
                    guard targetsKeyWindow(notification) else {
                        return
                    }
                    store.send(.diagnostics(.cycleLevel))
            }
            .onReceive(NotificationCenter.default
                .publisher(for: .cycleStreamDiagnosticsGlass)) { notification in
                    guard targetsKeyWindow(notification) else {
                        return
                    }
                    store.send(.diagnostics(.cycleGlass))
            }
    }

    private func targetsKeyWindow(_ notification: Notification) -> Bool {
        guard let window = notification.object as? PlatformWindow else {
            return false
        }
        return window === PlaybackWindowControl.keyWindow
    }
}

private struct StreamMicrophoneToggleReceiver: ViewModifier {
    let microphone: StoreOf<MicrophoneReducer>?
    @State private var hostWindow: PlatformWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowAccessor { hostWindow = $0 })
            .onReceive(NotificationCenter.default.publisher(for: .toggleStreamMicrophone)) { notification in
                guard let microphone else {
                    return
                }
                if let window = notification.object as? PlatformWindow, window !== hostWindow {
                    return
                }
                microphone.send(.toggle)
            }
    }
}

private struct StreamMenuTouchYield: ViewModifier {
    @Environment(\.virtualGamepad) private var virtualGamepad

    let level: StreamMenuReducer.Navigation.Level

    func body(content: Content) -> some View {
        content
            .onChange(of: level, initial: true) { _, level in
                switch level {
                case .gameplay:
                    virtualGamepad?.send(.streamMenuChanged(.closed))
                case .panel, .measuring:
                    virtualGamepad?.send(.streamMenuChanged(.panel))
                }
            }
    }
}

extension StreamMenuOverlay {
    /// Whether the streaming Home button is showing, which happens when console commands are available
    /// and the console is prohibiting display of its video.
    var homeButtonShown: Bool {
        store.consoleCommandsAvailable && store.displayProhibited
    }

    /// Recovers a controller move when no tracked target holds focus by focusing the current panel's tab.
    func moveFromUntrackedFocus() {
        focusTarget = .tab(panel)
    }
}

/// The capsule with an up arrow that shows at the bottom of a playing stream while the chrome is visible.
/// Under a pointer, hovering over it or clicking it shows the stream menu dock; on touch a tap opens the menu
/// itself, so no second tap is needed.
///
/// It only duplicates the controller shortcut for the pointer or finger, so it never takes controller focus.
private struct StreamDockHandle: View {
    /// Whether a tap opens the menu rather than widening the dock, which also turns the hover reveal off.
    let opensMenu: Bool
    /// The handle's height, at least a finger's target on touch.
    let height: CGFloat
    /// Shows the dock or the menu.
    let expand: () -> Void

    var body: some View {
        SwiftUI.Button(action: expand) {
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 96, height: height)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .glassEffect(AppGlass.control, in: .capsule)
        .onHover { hovering in
            if hovering, !opensMenu {
                expand()
            }
        }
        .help(Text(.playbackMenuHandleHelp))
        .accessibilityLabel(.playbackMenuHandleAccessibility)
    }
}

/// The line above the dock that teaches how to reach the stream menu as a stream starts.
enum StreamDockHint {
    /// The hint's wording.
    ///
    /// - Parameters:
    ///   - shortcut: The controller buttons that open the stream menu.
    ///   - family: The family of the controller driving menus, or `nil` while none is connected.
    /// - Returns: The shortcut named in the controller's own button names, then the pointer route, or the
    ///   pointer route alone without a controller.
    static func text(shortcut: StreamMenuShortcut, family: ControllerFamily?) -> LocalizedStringResource {
        guard let family else {
            #if os(macOS)
                return .playbackMenuHintPointer
            #else
                return .playbackMenuHintTouch
            #endif
        }
        let chord = shortcut.buttons
            .map { String(localized: ControllerGlyphs.button($0, family: family).name) }
            .joined(separator: " + ")
        #if os(macOS)
            return .playbackMenuHintShortcutPointer(chord: chord)
        #else
            return .playbackMenuHintShortcutTouch(chord: chord)
        #endif
    }
}

/// A non-interactive glass panel shown over the stream when picture is turned off in settings, explaining how
/// to turn it back on.
private struct StreamVideoOffNotice: View {
    /// Creates a stream video off notice.
    public init() {
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 34, weight: .medium))
            Text(.playbackMenuVideoOffTitle)
                .font(.title3.weight(.semibold))
            Text(.playbackMenuVideoOffDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .glassPanel(.large)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The card shown while the HDR heatmap's brightness marker is moved by controller: how to move it and a
/// Done button that returns to the Statistics panel.
struct StreamBrightnessMeasureCard: View {
    /// The stream menu focus binding the Done button registers with.
    let focus: MenuFocusState<StreamMenuFocusTarget?>.Binding
    /// Moves the marker one step.
    let nudge: (BrightnessMarker.Nudge) -> Void
    /// Returns to the Statistics panel.
    let done: () -> Void
    @Environment(\.screenLayout) private var layout

    var body: some View {
        VStack(spacing: 10) {
            Text(.playbackMenuMeasureTitle)
                .font(.headline)
            Text(.playbackMenuMeasureDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ControllerPrompt(button: .east, text: .commonDone)
                arrow(.left, symbol: "chevron.left", label: .playbackMenuMeasureLeft)
                FocusButton(.commonDone, action: done)
                    .glassControlStyle()
                    .menuFocused(focus, equals: .measureDone)
                    .environment(\.menuMove) { direction in
                        nudge(Self.nudge(for: direction))
                    }
                arrow(.right, symbol: "chevron.right", label: .playbackMenuMeasureRight)
            }
        }
        .padding(16)
        .frame(width: 380)
        .glassPanel(.medium)
    }

    /// The side of the arrow buttons, a finger's target.
    static let arrowSide: CGFloat = ScreenLayout.touchTarget

    private func arrow(_ step: BrightnessMarker.Nudge, symbol: String,
                       label: LocalizedStringResource) -> some View {
        SwiftUI.Button {
            nudge(step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: Self.arrowSide, height: Self.arrowSide)
                .glassEffect(AppGlass.control, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(label)
    }

    /// The marker step a controller or arrow key move asks for.
    ///
    /// - Parameter direction: The move.
    /// - Returns: The step.
    static func nudge(for direction: MenuMoveDirection) -> BrightnessMarker.Nudge {
        switch direction {
        case .left:
            .left
        case .right:
            .right
        case .up:
            .up
        case .down:
            .down
        }
    }
}
