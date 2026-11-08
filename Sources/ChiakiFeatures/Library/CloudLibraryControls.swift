import ChiakiModels
import SwiftUI
import ComposableArchitecture
import PlatformUI
import DesignSystem
import MenuFocus

extension CloudLibraryView {
    /// The library's title row: the Cloud heading with the controller hint for reaching the menu.
    var heading: some View {
        HStack(alignment: .center, spacing: 20) {
            Text(.libraryCloudTitle).font(.system(size: 40, weight: .semibold))
            Spacer(minLength: 0)
            LibraryMenuHint(section: .cloud)
        }
    }

    /// The filter, search, refresh and platform row, wired to the library's focus and reporting each
    /// control's centre so focus can move to the nearest one.
    var controls: CloudLibraryControls {
        CloudLibraryControls(
            store: store, accountID: accountID, focus: $focus, move: moveHeader,
            centered: { item, midX in
                headerCenters[item] = midX
            }
        )
    }
}

/// An invisible view that reports every change of the library's controller focus.
struct CloudFocusWatch: View {
    /// The library's controller focus to watch.
    @MenuFocusState.Binding var focus: CloudLibraryFocus?
    /// Called with the newly focused item each time focus changes.
    let changed: (CloudLibraryFocus?) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: focus) { _, item in
                changed(item)
            }
    }
}

/// The library's filter chips, search, refresh button and platform chips in one row.
///
/// The row shows the search field inline while everything fits, swaps the field for a search button when it
/// does not, and scrolls the button row as a last resort, keeping the focused control in view. On touch every
/// chip and button is at least a finger tall.
struct CloudLibraryControls: View {
    /// The library focus the controls take.
    typealias FocusItem = CloudLibraryFocus

    /// How the row shows search.
    enum SearchForm {
        /// The text field, typed into in place.
        case field
        /// A button that opens the search overlay.
        case button
        /// A round button that opens the search overlay, ringed while a search is in effect.
        case icon
    }

    /// The cloud library store whose filter, query and platform the controls change.
    @Bindable var store: StoreOf<CloudLibraryFeature>
    /// The signed-in account, or `nil` when none is chosen, which disables Refresh.
    let accountID: UUID?
    /// The library's controller focus, which moves back to All when the focused filter disappears.
    @MenuFocusState.Binding var focus: FocusItem?
    /// Moves controller focus out of the row in a direction.
    let move: @MainActor (MenuMoveDirection) -> Void
    /// Reports a control's horizontal centre in global coordinates.
    let centered: (FocusItem, CGFloat) -> Void
    @Environment(\.screenLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controllerFamily) private var controllerFamily
    @Environment(\.controllerConnected) private var controllerConnected

    var body: some View {
        Group {
            if layout.isCompact {
                ViewThatFits(in: .horizontal) {
                    compactRow
                    ScrollView(.horizontal, showsIndicators: false) {
                        compactRow
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    row(search: .field)
                    row(search: .button)
                    scrollingRow
                }
            }
        }
        .onChange(of: store.filters) { _, shown in
            if case .filter(let filter) = focus, !shown.contains(filter) {
                focus = .filter(.all)
            }
        }
    }

    private var headerControls: [FocusItem] {
        CloudLibraryFocusGraph(
            signedIn: accountID != nil,
            filters: store.filters,
            compact: layout.isCompact,
            filter: store.filter,
            platform: store.platform
        ).headerControls
    }

    private var compactRow: some View {
        HStack(spacing: layout.controlSpacing) {
            ChoiceDropdown(
                title: .libraryCloudFilterTitle,
                choices: store.filters,
                chosen: store.filter,
                label: \.title,
                stop: FocusItem.filter,
                focus: $focus,
                move: { _, direction in
                    move(direction)
                },
                titleShown: false
            ) { filter in
                store.send(.filter(filter))
            }
            .id(FocusItem.filter(store.filter))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                center(.filter(store.filter), midX)
            }
            ChoiceDropdown(
                title: .libraryCloudPlatformTitle,
                choices: CloudPlatformFilter.allCases,
                chosen: store.platform,
                label: \.title,
                stop: FocusItem.platform,
                focus: $focus,
                move: { _, direction in
                    move(direction)
                },
                titleShown: false
            ) { platform in
                store.send(.platform(platform))
            }
            .id(FocusItem.platform(store.platform))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                center(.platform(store.platform), midX)
            }
            Spacer(minLength: 0)
            search(.icon)
        }
        .padding(4)
        .padding(.horizontal, -4)
    }

    private var toolbarShortcutHelp: LocalizedStringResource {
        guard controllerConnected else {
            return ""
        }
        let button = ControllerGlyphs.button(.north, family: controllerFamily).name
        return .libraryCloudControllerShortcutHelp(button: String(localized: button))
    }

    private func center(_ item: FocusItem, _ midX: CGFloat) {
        centered(item, midX)
    }

    private func row(search form: SearchForm) -> some View {
        HStack(spacing: layout.controlSpacing) {
            filters
                .fixedSize(horizontal: true, vertical: false)
            search(form)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            platforms
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(4)
        .padding(.horizontal, -4)
    }

    private var scrollingRow: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.controlSpacing) {
                    filters
                    Spacer(minLength: 24)
                    search(.button)
                    platforms
                }
                .padding(4)
            }
            .padding(.horizontal, -4)
            .onChange(of: focus) { _, target in
                guard let target, headerControls.contains(target) else {
                    return
                }
                withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                    reader.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    private func search(_ form: SearchForm) -> some View {
        let query: Binding<String> = $store.query
        return HStack(spacing: layout.controlSpacing) {
            switch form {
            case .field:
                searchField(query)
            case .button:
                searchButton(query, iconOnly: false)
            case .icon:
                searchButton(query, iconOnly: true)
            }
            CloudRefreshButton(disabled: accountID == nil, cooldown: store.libraryRefresh) {
                store.send(.refresh)
            }
            .menuFocused($focus, equals: .refresh)
            .environment(\.menuMove, move)
            .id(FocusItem.refresh)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                center(.refresh, midX)
            }
            if let until = store.libraryRefresh.availableAt {
                CloudRefreshCountdown(until: until)
            }
        }
    }

    private func searchButton(_ query: Binding<String>, iconOnly: Bool) -> some View {
        Group {
            if iconOnly {
                FocusButton(action: openSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(query.wrappedValue.isEmpty
                            ? .white
                            : Palette.accent)
                            .frame(width: 24, height: 24)
                }
                .glassControlStyle()
                .focusBorderShape(.circle)
                .overlay {
                    if !query.wrappedValue.isEmpty {
                        Circle()
                            .strokeBorder(Palette.accent, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                FocusButton(action: openSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        Text(
                            query.wrappedValue.isEmpty
                                ? .commonSearch
                                : .verbatim(query.wrappedValue)
                        )
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                    }
                    .font(.system(size: 15, weight: .regular))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: layout.controlSize)
                    .glassEffect(AppGlass.control, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .focusHighlightShape(.capsule)
            }
        }
        .accessibilityLabel(.libraryCloudSearchGames)
        .accessibilityValue(query.wrappedValue)
        .menuFocused($focus, equals: .search)
        .environment(\.menuMove, move)
        .id(FocusItem.search)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
            center(.search, midX)
        }
    }

    private func openSearch() {
        store.send(.searchTapped)
    }

    private func searchField(_ query: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                .libraryCloudSearchGames,
                text: query
            )
            .textFieldStyle(.plain)
            .menuFocusBinding($focus, equals: .search)
            .controllerKeyboard(
                title: .libraryCloudSearchGames,
                text: query,
                isFocused: focus == .search
            )
            .onMenuKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                move(press.key == .upArrow
                    ? .up
                    : .down)
                return .handled
            }
        }.font(.system(size: 15, weight: .regular)).padding(12)
            .frame(minWidth: 140, idealWidth: 140, maxWidth: 280)
            .frame(minHeight: layout.controlSize)
            .glassEffect(AppGlass.control, in: .capsule)
            .modifier(CloudSearchFocusRing(focused: focus == .search))
            .id(FocusItem.search)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                center(.search, midX)
            }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            ForEach(store.filters, id: \.self) { filter in
                FocusButton {
                    store.send(.filter(filter))
                    focus = .filter(filter)
                } label: {
                    Text(filter.title)
                        .font(.system(
                            size: 15,
                            weight: store.filter == filter
                                ? .semibold
                                : .regular
                        ))
                        .foregroundStyle(
                            store.filter == filter
                                ? Palette.accent
                                : .white
                        )
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .frame(minHeight: layout.controlSize)
                        .glassEffect(
                            store.filter == filter
                                ? AppGlass.control.tint(Palette.accent.opacity(0.28))
                                : AppGlass.control,
                            in: .capsule
                        )
                        .contentShape(.capsule)
                }.buttonStyle(.plain)
                    .focusHighlightShape(.capsule)
                    .menuFocused($focus, equals: .filter(filter))
                    .environment(\.menuMove, move)
                    .accessibilityAddTraits(
                        store.filter == filter
                            ? .isSelected
                            : []
                    )
                    .id(FocusItem.filter(filter))
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                        center(.filter(filter), midX)
                    }
            }
        }.padding(2)
            .fixedSize(horizontal: true, vertical: false)
            .help(toolbarShortcutHelp)
    }

    private var platforms: some View {
        CloudPlatformChips(store: store, focus: $focus, move: move, centered: centered)
    }
}

/// The platform filter as a row of chips on one glass capsule, the chosen one highlighted.
struct CloudPlatformChips: View {
    /// The library focus the chips take.
    typealias FocusItem = CloudLibraryFocus

    /// The cloud library store whose platform filter the chips change.
    let store: StoreOf<CloudLibraryFeature>
    /// The library's controller focus.
    @MenuFocusState.Binding var focus: FocusItem?
    /// Moves controller focus out of the chips in a direction.
    let move: @MainActor (MenuMoveDirection) -> Void
    /// Reports a chip's horizontal centre in global coordinates.
    let centered: (FocusItem, CGFloat) -> Void
    @Environment(\.screenLayout) private var layout

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CloudPlatformFilter.allCases, id: \.self) { platform in
                chip(platform)
            }
        }
        .padding(4)
        .glassEffect(AppGlass.control, in: .capsule)
        .fixedSize()
    }

    private func chip(_ platform: CloudPlatformFilter) -> some View {
        let chosen = store.platform == platform
        return FocusButton {
            store.send(.platform(platform))
            focus = .platform(platform)
        } label: {
            Text(platform.title)
                .font(.system(
                    size: 15,
                    weight: chosen
                        ? .semibold
                        : .regular
                ))
                .foregroundStyle(
                    chosen
                        ? Palette.accent
                        : .white
                )
                .padding(.horizontal, 16).padding(.vertical, 6)
                .frame(minHeight: max(0, layout.controlSize - 8))
                .background(
                    chosen
                        ? Palette.accent.opacity(0.22)
                        : .clear,
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.capsule)
        .menuFocused($focus, equals: .platform(platform))
        .environment(\.menuMove, move)
        .accessibilityLabel(platform.spokenTitle)
        .accessibilityAddTraits(chosen
            ? .isSelected
            : [])
            .id(FocusItem.platform(platform))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { midX in
                centered(.platform(platform), midX)
            }
    }
}

/// The time left before a refresh may run again, ticking down each second beside a Refresh button and hidden
/// once it reaches zero.
struct CloudRefreshCountdown: View {
    /// When the next refresh may run.
    let until: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(until.timeIntervalSince(context.date).rounded(.up))
            if left > 0 {
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                    .accessibilityLabel(.libraryCloudRefreshCountdown(seconds: left))
            }
        }
    }
}

/// A round glass Refresh button that reloads the cloud library.
struct CloudRefreshButton: View {
    /// Whether the button is disabled, as it is when no account is signed in.
    let disabled: Bool
    /// Whether a refresh may start; while it waits the button stays focusable but dimmed, and presses are
    /// ignored.
    let cooldown: CloudLibraryRefresh
    /// Reloads the library.
    let action: () -> Void

    var body: some View {
        FocusButton(.commonRefresh, systemImage: "arrow.clockwise", action: action)
            .labelStyle(.iconOnly)
            .glassControlStyle()
            .focusBorderShape(.circle)
            .disabled(disabled)
            .opacity(cooldown.isReady
                ? 1
                : 0.45)
                .help(hint)
                .accessibilityLabel(hint)
    }

    private var hint: LocalizedStringResource {
        guard !cooldown.isReady else {
            return .libraryCloudRefreshLibrary
        }
        guard let available = cooldown.availableAt else {
            return .libraryCloudJustRefreshed
        }
        return .libraryCloudRefreshAgainAt(time: available.formatted(date: .omitted, time: .shortened))
    }
}

/// Draws an accent ring around the search field while it has controller or keyboard focus.
struct CloudSearchFocusRing: ViewModifier {
    /// Whether the search field is focused.
    let focused: Bool
    @Environment(\.inputMode) private var inputMode

    /// Overlays the ring on the field when the current input mode shows focus.
    ///
    /// - Parameter content: The search field.
    /// - Returns: The field with its focus ring.
    func body(content: Content) -> some View {
        content.overlay {
            if inputMode.shows(focused) {
                Capsule()
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}
