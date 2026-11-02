import ChiakiModels
import ComposableArchitecture
import CoreGraphics
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// The settings panel's content: the tab bar and the selected tab's page.
///
/// Only the selected tab's page is mounted, so only it runs appear effects; every pane's state lives in
/// ``SettingsFeature``, so leaving a tab or resizing the window keeps its edits.
struct SettingsView: View {
    @Environment(\.menuNavigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The settings feature that owns every tab's state and the selected route.
    @Bindable var store: StoreOf<SettingsFeature>
    /// Whether the selected tab takes focus when the view appears; when false, the first controller move
    /// settles focus instead.
    var initiallyFocusTabs = true
    /// The widest the tab bar and pages are laid out, in points.
    var pageLayoutWidth: CGFloat = 1180
    /// Whether the tab bar is drawn above the page; the panel leaves it out when the keyboard leaves room for
    /// the page alone.
    var showsTabs = true
    /// The window hosting the panel, used to match controller and keyboard events to it; the view finds its
    /// own window when `nil`.
    let window: PlatformWindow?
    /// The focus state of the panel's Close button, so controller navigation can move between it and the
    /// tabs.
    var closeFocus: MenuFocusState<Bool>.Binding?
    /// Closes the settings panel when Back is pressed on the tabs or the Close button, or `nil` when the view
    /// cannot close itself.
    var close: (() -> Void)?
    @MenuFocusState private var focusedTab: SettingsRoute?
    @MenuFocusState private var networkFocus: NetworkSettingsFocus?
    @State private var entryRequest = 0
    @State private var openingFocus = SettingsOpeningFocus.pending
    @State private var tabBarBottom: CGFloat = 0
    @State private var hostWindow: PlatformWindow?
    @FocusedValue(\.settingsSliderTarget) private var settingsSliderTarget
    @State private var sliderFocus = SettingsSliderFocusReference()
    @State private var sliderNavigation = SettingsSliderNavigationState.navigating

    var body: some View {
        VStack(spacing: 0) {
            if showsTabs {
                SettingsTabBar(
                    store: store,
                    layoutWidth: pageLayoutWidth,
                    focused: focusedTab,
                    focusedTab: $focusedTab,
                    select: selectTab,
                    move: moveTabFocus,
                    bottomChanged: { tabBarBottom = $0 }
                )
            }
            SettingsPage(store: store, route: store.route, networkFocus: $networkFocus)
                .id(store.route)
                .frame(width: min(pageLayoutWidth, CGFloat(SettingsRoute.pageWidth)))
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .overlay {
                    FocusHighlightOverlay()
                        .allowsHitTesting(false)
                }
                .animation(AppMotion.animation(reduced: reduceMotion), value: store.route)
        }
        .appConfirmation(store.clearCacheConfirmation, confirm: {
            store.send(.destination(.presented(.clearCache(.confirm))))
            refocusTabAfterPrompt()
        }, cancel: {
            store.send(.destination(.presented(.clearCache(.cancel))))
            refocusTabAfterPrompt()
        })
        .sheet(item: $store.scope(
            state: \.destination?.errorReport,
            action: \.destination.errorReport
        )) { report in
            ErrorReportSheet(store: report)
        }
        .controlSize(.regular)
        .focusEffectDisabled()
        .background(WindowAccessor { hostWindow = $0 })
        .tint(Palette.accent).toggleStyle(AccentCheckboxToggleStyle())
        .environment(\.settingsMenuFocus, true)
        .environment(\.settingsSliderNavigation, sliderNavigation)
        .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            driver.confirmSlider()
                ? .handled
                : .ignored
        }
        .onMenuKeyPress(keys: [.escape], phases: .down) { _ in
            driver.cancelSliderAdjustment()
                ? .handled
                : .ignored
        }
        .frame(idealWidth: 1320, idealHeight: 900)
        .onAppear {
            if initiallyFocusTabs {
                openingFocus = .settled
                focusedTab = store.route
            }
        }
        .menuHandlers(
            move: { window, direction in
                guard window === (self.window ?? hostWindow), !(navigator?.isTrackingMenu ?? false) else {
                    return false
                }
                return driver.move(direction, in: window)
            },
            activate: { window in
                guard window === (self.window ?? hostWindow) else {
                    return false
                }
                return driver.confirmSlider()
            },
            back: { window in
                guard window === (self.window ?? hostWindow) else {
                    return false
                }
                return driver.back(in: window)
            }
        )
        .onChange(of: store.route) { _, route in
            sliderNavigation.leave()
            networkFocus = nil
            focusedTab = route
        }
        .onChange(of: settingsSliderTarget) { previous, target in
            sliderFocus.target = target
            if previous?.id != target?.id {
                sliderNavigation.leave()
            }
        }
        .task(id: entryRequest) {
            guard entryRequest > 0 else {
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let target = window ?? hostWindow ?? navigator?.activeWindow else {
                return
            }
            if store.route == .network {
                networkFocus = .sweep
            } else {
                driver.pageFocus(in: target).enter()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSettingsTabs)) { notification in
            guard let source = notification.object as? PlatformWindow,
                  source === (window ?? hostWindow) else {
                return
            }
            openingFocus = .settled
            focusedTab = store.route
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsPanelSettled)) { notification in
            guard openingFocus == .pending,
                  let target = window ?? hostWindow,
                  notification.object as? PlatformWindow === target else {
                return
            }
            if navigator?.isEditingText(in: target) == true {
                openingFocus = .settled
                return
            }
            driver.settleOpeningFocus(in: target)
        }
        .onMenuCommand([.previous]) { event in
            moveSettingsTab(by: -1, event: event)
        }
        .onMenuCommand([.next]) { event in
            moveSettingsTab(by: 1, event: event)
        }
    }

    private func selectTab(_ route: SettingsRoute) {
        navigator?.endEditing()
        _ = withAnimation(AppMotion.animation(reduced: reduceMotion)) {
            store.send(.select(route))
        }
    }

    private func moveTabFocus(from route: SettingsRoute, direction: MenuMoveDirection) {
        let routes = store.tabs
        guard let index = routes.firstIndex(of: route) else {
            return
        }
        switch direction {
        case .left, .right:
            let change = direction == .left
                ? -1
                : 1
            focusedTab = routes[(index + change + routes.count) % routes.count]
        case .up:
            closeFocus?.wrappedValue = true
        case .down:
            entryRequest += 1
        @unknown default:
            break
        }
    }

    private var driver: SettingsFocusDriver {
        SettingsFocusDriver(
            store: store,
            navigator: navigator,
            focusedTab: $focusedTab,
            networkFocus: $networkFocus,
            closeFocus: closeFocus,
            openingFocus: $openingFocus,
            slider: sliderFocus.target,
            sliderNavigation: $sliderNavigation,
            tabBarBottom: tabBarBottom,
            close: close
        )
    }

    private func refocusTabAfterPrompt() {
        Task { @MainActor in
            await Task.yield()
            focusedTab = store.route
        }
    }

    private func moveSettingsTab(by offset: Int, event: MenuCommandEvent) {
        let routes = store.tabs
        guard let owner = window ?? hostWindow, let source = event.window, source === owner,
              let index = routes.firstIndex(of: store.route) else {
            return
        }
        openingFocus = .settled
        let next = routes[(index + offset + routes.count) % routes.count]
        store.send(.select(next))
        focusedTab = next
    }
}

/// Answers the settings panel's controller moves, Back and Confirm: between the tabs, the Close button, the
/// network page's own stops and the selected page, and for the slider being adjusted.
///
/// The settings view creates it from its current state for each command; it changes focus through the view's
/// focus bindings and reports whether it took the command.
@MainActor
private struct SettingsFocusDriver {
    /// The settings feature.
    let store: StoreOf<SettingsFeature>

    /// The navigator that owns controller focus and text editing.
    let navigator: PlatformMenuNavigator?

    /// The focused tab, or `nil` when focus is elsewhere.
    let focusedTab: MenuFocusState<SettingsRoute?>.Binding

    /// The focused stop of the network page, or `nil` when focus is elsewhere.
    let networkFocus: MenuFocusState<NetworkSettingsFocus?>.Binding

    /// The focus state of the panel's Close button, or `nil` when the panel has none.
    let closeFocus: MenuFocusState<Bool>.Binding?

    /// Whether the panel has placed its first focus since it opened.
    let openingFocus: Binding<SettingsOpeningFocus>

    /// The slider that holds focus, or `nil` when no slider does.
    let slider: SettingsSliderTarget?

    /// Which slider the controller is adjusting, with its value from when adjusting started.
    let sliderNavigation: Binding<SettingsSliderNavigationState>

    /// The tab strip's bottom edge in global coordinates.
    let tabBarBottom: CGFloat

    /// Closes the panel, or `nil` when it cannot close itself.
    let close: (() -> Void)?

    /// Answers a direction press.
    ///
    /// - Parameters:
    ///   - direction: The direction pressed.
    ///   - window: The panel's window.
    /// - Returns: Whether the panel took the press.
    func move(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
        if navigator?.isEditingText(in: window) == true {
            return false
        }
        if openingFocus.wrappedValue == .pending {
            settleOpeningFocus(in: window)
            return true
        }
        if focusedTab.wrappedValue != nil {
            return false
        }
        if store.route == .network, let focus = networkFocus.wrappedValue {
            if focus == .subnets, store.network.subnetsRejected {
                return true
            }
            if focus == .subnets, direction == .down {
                return moveContent(direction, in: window)
            }
            moveNetworkFocus(from: focus, direction: direction)
            return true
        }
        if closeFocus?.wrappedValue == true {
            if direction == .down || direction == .right {
                focusedTab.wrappedValue = store.route
            }
            return true
        }
        guard moveContent(direction, in: window) else {
            return false
        }
        if store.route == .network, direction == .up, pageFocus(in: window).isOnText {
            networkFocus.wrappedValue = .subnets
        }
        return true
    }

    /// Answers Back: ends a slider adjustment, closes the panel from the tabs or the Close button, or returns
    /// focus to the selected tab.
    ///
    /// - Parameter window: The panel's window.
    /// - Returns: Whether the panel took Back.
    func back(in window: PlatformWindow) -> Bool {
        if cancelSliderAdjustment() {
            return true
        }
        guard store.controls.mode == .idle, !(navigator?.isEditingText(in: window) ?? false) else {
            return false
        }
        openingFocus.wrappedValue = .settled
        if focusedTab.wrappedValue != nil || closeFocus?.wrappedValue == true {
            guard let close else {
                return false
            }
            close()
            return true
        }
        networkFocus.wrappedValue = nil
        focusedTab.wrappedValue = store.route
        return true
    }

    /// Places the panel's first focus on the selected tab.
    ///
    /// - Parameter window: The panel's window.
    func settleOpeningFocus(in window: PlatformWindow) {
        openingFocus.wrappedValue = .settled
        #if os(macOS)
            window.recalculateKeyViewLoop()
        #endif
        focusedTab.wrappedValue = store.route
        let route = store.route
        navigator?.ensureFocus(in: window) {} apply: {
            guard focusedTab.wrappedValue == nil else {
                return
            }
            focusedTab.wrappedValue = route
        }
    }

    /// The focus mover for the selected page.
    ///
    /// - Parameter window: The panel's window.
    /// - Returns: The mover below the tab strip.
    func pageFocus(in window: PlatformWindow) -> SettingsPageFocus {
        SettingsPageFocus(navigator: navigator, window: window, top: tabBarBottom, route: store.route)
    }

    /// Starts adjusting the focused slider, or finishes adjusting it.
    ///
    /// - Returns: Whether a slider has focus.
    func confirmSlider() -> Bool {
        guard let slider else {
            return false
        }
        sliderNavigation.wrappedValue.confirm(slider.id, current: slider.value.wrappedValue)
        return true
    }

    /// Restores the focused slider's value from when adjusting started and stops adjusting it.
    ///
    /// - Returns: Whether the focused slider was being adjusted.
    func cancelSliderAdjustment() -> Bool {
        guard let slider, case .adjusting(slider.id, let original) = sliderNavigation.wrappedValue else {
            return false
        }
        slider.value.wrappedValue = original
        sliderNavigation.wrappedValue.leave()
        return true
    }

    private func moveNetworkFocus(from focus: NetworkSettingsFocus, direction: MenuMoveDirection) {
        switch (focus, direction) {
        case (.sweep, .down):
            networkFocus.wrappedValue = .subnets
        case (.subnets, .up):
            networkFocus.wrappedValue = .sweep
        case (.sweep, .up):
            networkFocus.wrappedValue = nil
            focusedTab.wrappedValue = store.route
        default:
            break
        }
    }

    private func moveContent(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
        switch direction {
        case .up, .down:
            sliderNavigation.wrappedValue.leave()
        case .left, .right:
            if let slider, sliderNavigation.wrappedValue.isAdjusting(slider.id) {
                return false
            }
        @unknown default:
            break
        }
        switch pageFocus(in: window).move(direction) {
        case .moved:
            return true
        case .reachedTabs:
            focusedTab.wrappedValue = store.route
            return true
        case .refused:
            return slider != nil
        }
    }
}

/// Moves controller focus between the stops of a settings page, below the tab strip.
///
/// Vertical moves weigh horizontal distance more while focus sits high on the Controls page, so moving down
/// from a column stays in it.
@MainActor
private struct SettingsPageFocus {
    /// Where a move left focus.
    enum Outcome {
        /// Focus moved, or stays where it is.
        case moved
        /// No stop lies above, so focus returns to the tabs.
        case reachedTabs
        /// No stop lies in that direction.
        case refused
    }

    /// The navigator that moves focus.
    let navigator: PlatformMenuNavigator?

    /// The window the page is shown in.
    let window: PlatformWindow

    /// The tab strip's bottom edge in global coordinates.
    let top: CGFloat

    /// The tab whose page is shown.
    let route: SettingsRoute

    /// Whether focus is on a text view.
    var isOnText: Bool {
        #if os(macOS)
            window.firstResponder is NSTextView
        #else
            false
        #endif
    }

    /// Moves focus to the nearest stop of the page in a direction.
    ///
    /// - Parameter direction: The direction.
    /// - Returns: Where the move left focus.
    func move(_ direction: MenuMoveDirection) -> Outcome {
        switch direction {
        case .up:
            let moved = navigator?.moveGeometric(
                .up, in: window, belowGlobalY: top, allowUnaligned: true, horizontalWeight: verticalWeight
            )
            return moved == true
                ? .moved
                : .reachedTabs
        case .down:
            _ = navigator?.moveGeometric(
                .down, in: window, belowGlobalY: top, allowUnaligned: true, horizontalWeight: verticalWeight
            )
            return .moved
        case .left, .right:
            return navigator?.moveGeometric(direction, in: window, belowGlobalY: top) == true
                ? .moved
                : .refused
        @unknown default:
            return .moved
        }
    }

    /// Moves focus from the tabs into the page's first row, on the stop of that row nearest the selected tab,
    /// or to the page's first stop when none lies below.
    ///
    /// Sideways distance barely counts, so a tab at the far end of the bar still enters the top row rather
    /// than a lower control that happens to sit beneath it.
    func enter() {
        let moved = navigator?.moveGeometric(
            .down, in: window, belowGlobalY: top, allowUnaligned: true, horizontalWeight: 0.1
        )
        if moved != true {
            navigator?.focusEntry(belowGlobalY: top, in: window)
        }
    }

    private var verticalWeight: CGFloat {
        #if os(macOS)
            guard route == .controls,
                  let view = window.firstResponder as? NSView,
                  let content = window.contentView else {
                return 0.1
            }
            let origin = view.convert(view.bounds, to: nil)
            let visible = content.convert(content.bounds, to: nil)
            return origin.midY < visible.minY + visible.height * 0.6
                ? 0.5
                : 0.1
        #else
            guard route == .controls, let origin = navigator?.focusFrame(in: window) else {
                return 0.1
            }
            return origin.midY > window.bounds.minY + window.bounds.height * 0.4
                ? 0.5
                : 0.1
        #endif
    }
}

/// Whether the settings panel has placed its first focus since it opened.
private enum SettingsOpeningFocus {
    /// The first controller move, or the end of the opening animation, places focus on the selected tab.
    case pending

    /// Focus was placed, by the person or by the panel.
    case settled
}

/// The settings tabs on their glass strip: one button for each tab the settings show.
///
/// The strip shows full titles when they fit, then each tab's symbol over a short title, and when even those
/// overflow it scrolls sideways, keeping the selected tab in view. Return and Space choose the focused tab. The
/// arrow keys leave the choice of the next focus to the settings view, which moves along the tabs, up to the
/// Close button or down into the page.
private struct SettingsTabBar: View {
    /// How the tabs are labelled.
    enum Density {
        /// The symbol beside the full title.
        case titled
        /// The symbol over a short title.
        case stacked
    }

    /// The settings feature whose tabs and selected route the bar shows.
    let store: StoreOf<SettingsFeature>

    /// The widest the strip is laid out, in points.
    let layoutWidth: CGFloat

    /// The tab that has focus, read when the settings view draws.
    let focused: SettingsRoute?

    /// The focus binding of the tabs.
    let focusedTab: MenuFocusState<SettingsRoute?>.Binding

    /// Chooses a tab.
    let select: (SettingsRoute) -> Void

    /// Moves focus from a tab in a direction.
    let move: (SettingsRoute, MenuMoveDirection) -> Void

    /// Reports the strip's bottom edge in global coordinates, below which the page's focus stops lie.
    let bottomChanged: (CGFloat) -> Void

    @Environment(\.inputMode) private var inputMode
    @Environment(\.screenLayout) private var layout

    /// The strip of tabs.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(.titled)
            strip(.stacked)
            scrollingStrip
        }
        .padding(stripPadding)
        .frame(maxWidth: layoutWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
            bottomChanged(bottom)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripPadding: CGFloat {
        layout.isCompact
            ? 8
            : 16
    }

    private func strip(_ density: Density) -> some View {
        HStack(spacing: 4) {
            ForEach(store.tabs, id: \.self) { route in
                tabButton(route, density: density)
            }
        }
        .padding(5)
        .glassEffect(AppGlass.control, in: .capsule)
    }

    private var scrollingStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                strip(.stacked)
                    .selfManagedFocusScrolling()
            }
            .scrollIndicators(.never)
            .onChange(of: store.route, initial: true) { _, route in
                proxy.scrollTo(route)
            }
            .onChange(of: focused) { _, route in
                guard let route else {
                    return
                }
                proxy.scrollTo(route)
            }
        }
    }

    @ViewBuilder
    private static func label(_ route: SettingsRoute, density: Density) -> some View {
        switch density {
        case .titled:
            Label(route.title, systemImage: route.symbol)
                .font(.callout)
                .lineLimit(1)
        case .stacked:
            VStack(spacing: 2) {
                Image(systemName: route.symbol)
                    .font(.callout)
                Text(route.shortTitle)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(route.title)
        }
    }

    private func tabButton(_ route: SettingsRoute, density: Density) -> some View {
        Button {
            select(route)
        } label: {
            Self.label(route, density: density)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: layout.controlSize)
                .background(fill(route), in: .capsule)
                .contentShape(.capsule)
                .overlay {
                    if inputMode.shows(focused == route) {
                        Capsule().strokeBorder(Palette.accent, lineWidth: 2)
                    }
                }
        }
        .id(route)
        .buttonStyle(.plain)
        .menuFocusable()
        .focusEffectDisabled()
        .menuFocused(focusedTab, equals: route)
        .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
            select(route)
            return .handled
        }
        .onMenuKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: .down) { press in
            let direction: MenuMoveDirection
            switch press.key {
            case .upArrow:
                direction = .up
            case .downArrow:
                direction = .down
            case .leftArrow:
                direction = .left
            case .rightArrow:
                direction = .right
            default:
                return .ignored
            }
            move(route, direction)
            return .handled
        }
        .accessibilityAddTraits(store.route == route
            ? .isSelected
            : [])
    }

    private func fill(_ route: SettingsRoute) -> Color {
        if inputMode.shows(focused == route) {
            return Palette.accent.opacity(0.32)
        }
        if store.route == route {
            return Palette.accent.opacity(0.18)
        }
        return Color.clear
    }
}
