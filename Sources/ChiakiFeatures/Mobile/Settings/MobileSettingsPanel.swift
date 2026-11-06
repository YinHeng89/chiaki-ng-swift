import ChiakiModels
import ComposableArchitecture
import DesignSystem
import MenuFocus
import PlatformUI
import SwiftUI

/// Settings on a phone: the settings categories, or one category's page, filling the screen over the library or
/// a stream.
///
/// It stands in for the wide settings panel on compact touch screens, whichever way Settings was opened. Touch
/// and a controller both drive it. The controller moves between rows by their position on screen, Confirm
/// activates the focused row, and Back steps out of a slider adjustment, then the button mapping, then the page,
/// and finally closes Settings.
struct MobileSettingsPanel: View {
    /// The settings.
    @Bindable var settings: StoreOf<SettingsFeature>

    /// The window the panel is shown in, or `nil` while it is not yet known.
    let window: PlatformWindow?

    /// Closes Settings.
    let close: () -> Void

    @Environment(\.menuNavigator) private var navigator
    @Environment(\.screenLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: SettingsRoute?
    @State private var forward = true
    @State private var sliders = MobileSliderAdjustment()
    @State private var hostWindow: PlatformWindow?
    @State private var headerBottom: CGFloat = 0
    @MenuFocusState private var focusedCategory: SettingsRoute?
    @MenuFocusState private var headerFocus: HeaderControl?

    /// A control in the panel's header.
    private enum HeaderControl: Hashable {
        case back
        case close
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                content
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .padding(.horizontal, max(16, layout.sideInset))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.windowBackground.ignoresSafeArea())
        .background(WindowAccessor { hostWindow = $0 })
        .environment(\.mobileSliderAdjustment, sliders)
        .animation(AppMotion.animation(reduced: reduceMotion), value: page)
        .menuHandlers(
            move: { window, direction in
                move(direction, in: window)
            },
            back: { window in
                back(in: window)
            }
        )
        .onAppear {
            if let first = MobileSettingsCategories.order(settings.tabs).first {
                restoreCategoryFocus(first)
            }
        }
        .onChange(of: page) {
            sliders.leave()
        }
    }

    private var owner: PlatformWindow? {
        window ?? hostWindow
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let page {
                FocusButton {
                    leave(page)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .glassControlStyle()
                .focusBorderShape(.circle)
                .menuFocused($headerFocus, equals: .back)
                .accessibilityLabel("Back")
                .transition(.opacity)
            }
            Text(page?.title ?? "Settings")
                .font(.title2.bold())
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            FocusButton(action: close) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .glassControlStyle()
            .focusBorderShape(.circle)
            .menuFocused($headerFocus, equals: .close)
            .accessibilityLabel("Close settings")
        }
        .padding(.top, layout.topChromeInset)
        .padding(.bottom, 4)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
            headerBottom = bottom
        }
    }

    @ViewBuilder private var content: some View {
        if let page {
            MobileSettingsPage(settings: settings, route: page)
        } else {
            ScrollView {
                MobileSettingsCategories(settings: settings, focus: $focusedCategory, open: open)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: forward
                ? .trailing
                : .leading).combined(with: .opacity),
            removal: .move(edge: forward
                ? .leading
                : .trailing).combined(with: .opacity)
        )
    }

    private func open(_ route: SettingsRoute) {
        navigator?.endEditing()
        settings.send(.select(route))
        forward = true
        page = route
        let target = owner
        navigator?.ensureFocus(in: target) {} apply: { [navigator, headerBottom] in
            guard let target else {
                return
            }
            navigator?.focusEntry(belowGlobalY: headerBottom, in: target)
        }
    }

    private func leave(_ route: SettingsRoute) {
        navigator?.endEditing()
        forward = false
        page = nil
        restoreCategoryFocus(route)
    }

    private func restoreCategoryFocus(_ route: SettingsRoute) {
        focusedCategory = route
        navigator?.ensureFocus(in: owner) {
            focusedCategory = nil
        } apply: {
            focusedCategory = route
        }
    }

    private func move(_ direction: MenuMoveDirection, in window: PlatformWindow) -> Bool {
        guard window === owner, let navigator, !navigator.isEditingText(in: window) else {
            return false
        }
        if sliders.isAdjusting {
            if direction == .left || direction == .right {
                return false
            }
            sliders.leave()
        }
        if let control = headerFocus {
            moveFromHeader(control, direction: direction, in: window)
            return true
        }
        guard navigator.hasControlFocus(in: window) else {
            navigator.focusEntry(belowGlobalY: headerBottom, in: window)
            return true
        }
        switch direction {
        case .up:
            let moved = navigator.moveGeometric(.up, in: window, belowGlobalY: headerBottom, allowUnaligned: true)
            if !moved {
                headerFocus = page == nil
                    ? .close
                    : .back
            }
        case .down:
            navigator.moveGeometric(.down, in: window, belowGlobalY: headerBottom, allowUnaligned: true)
        case .left, .right:
            navigator.moveGeometric(direction, in: window, belowGlobalY: headerBottom)
        @unknown default:
            break
        }
        return true
    }

    private func moveFromHeader(_ control: HeaderControl, direction: MenuMoveDirection, in window: PlatformWindow) {
        switch (control, direction) {
        case (.back, .right):
            headerFocus = .close
        case (.close, .left) where page != nil:
            headerFocus = .back
        case (_, .down):
            navigator?.focusEntry(belowGlobalY: headerBottom, in: window)
        default:
            break
        }
    }

    private func back(in window: PlatformWindow) -> Bool {
        guard window === owner else {
            return false
        }
        if sliders.cancel() {
            return true
        }
        guard navigator?.isEditingText(in: window) != true else {
            return false
        }
        if page == .controls, unwindControls(in: window) {
            return true
        }
        if let page {
            leave(page)
        } else {
            close()
        }
        return true
    }

    private func unwindControls(in window: PlatformWindow) -> Bool {
        if settings.controls.capture != nil {
            settings.send(.controls(.cancelCapture))
            return true
        }
        guard settings.controls.showsMapping else {
            return false
        }
        settings.send(.controls(.closeMapping))
        navigator?.ensureFocus(in: window) {} apply: { [navigator, headerBottom] in
            navigator?.focusEntry(belowGlobalY: headerBottom, in: window)
        }
        return true
    }
}

/// The settings categories as grouped rows, each opening its page: About on its own, the everyday categories,
/// then the developer tools under Advanced.
struct MobileSettingsCategories: View {
    /// The settings, whose tabs decide which categories are listed.
    let settings: StoreOf<SettingsFeature>

    /// The controller focus of the rows, or `nil` where no controller drives them.
    var focus: MenuFocusState<SettingsRoute?>.Binding?

    /// Opens a category's page.
    let open: (SettingsRoute) -> Void

    var body: some View {
        let routes = settings.tabs
        let everyday = routes.filter { !$0.isDeveloperTool && $0 != .about }
        let tools = routes.filter(\.isDeveloperTool)
        VStack(alignment: .leading, spacing: 20) {
            if routes.contains(.about) {
                MobileGroup(title: nil) {
                    row(.about)
                }
            }
            MobileGroup(title: "Settings") {
                ForEach(everyday, id: \.self, content: row)
            }
            if !tools.isEmpty {
                MobileGroup(title: "Advanced") {
                    ForEach(tools, id: \.self, content: row)
                }
            }
        }
    }

    /// The categories in the order the list shows them.
    ///
    /// - Parameter routes: The settings tabs.
    /// - Returns: About first, then the everyday categories, then the developer tools.
    static func order(_ routes: [SettingsRoute]) -> [SettingsRoute] {
        routes.filter { $0 == .about }
            + routes.filter { !$0.isDeveloperTool && $0 != .about }
            + routes.filter(\.isDeveloperTool)
    }

    @ViewBuilder private func row(_ route: SettingsRoute) -> some View {
        let row = MobileRow(route.title, chevron: true) {
            MobileRowIcon(symbol: route.symbol, color: Self.color(for: route))
        } action: {
            open(route)
        }
        if let focus {
            row.menuFocused(focus, equals: route)
        } else {
            row
        }
    }

    private static func color(for route: SettingsRoute) -> Color {
        switch route {
        case .picture, .accessibility:
            .blue
        case .sound:
            .pink
        case .controls:
            .green
        case .interface:
            .indigo
        case .network:
            .teal
        case .remotePlayers:
            .orange
        case .developer, .entitlements, .caches, .requests, .tokens, .about:
            .gray
        }
    }
}
