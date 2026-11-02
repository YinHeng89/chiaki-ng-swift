import ChiakiModels
import ComposableArchitecture
import DesignSystem
import Foundation
import MenuFocus
import PlatformUI
import SwiftUI

/// The add-console screen of a signed-in account: pick a scanned console, type an address, or pick one from
/// the PSN account.
public struct AddConsoleView: View {
    /// A vertical stop of the screen's controller navigation, walked in order by up and down moves.
    public enum Row: Equatable {
        /// The mode switch, the manual generation switch, the PSN generation switch, or one focusable
        /// control.
        case mode, kind, psnKind, control(AddConsoleFocus)
    }

    /// The add-console feature; the address and generation fields are bound to it.
    @Bindable public var store: StoreOf<AddConsoleFeature>
    /// The shared local-network scan, whose consoles and ranges the automatic mode lists.
    public let discovery: DiscoveryFeature.State
    /// The message of the last failed pairing attempt, shown under the mode switch.
    public let failure: String?
    /// Routes controller moves and Back presses to the handlers this screen registers.
    @Environment(\.menuNavigator) var navigator
    /// The focused button, field or console row.
    @MenuFocusState var focus: AddConsoleFocus?
    /// The focused segment of the mode switch.
    @MenuFocusState var modeFocus: AddConsoleMode?
    /// The focused segment of the manual generation switch.
    @MenuFocusState var kindFocus: RegistrationFlow.ConsoleKind?
    /// The focused segment of the PSN generation switch; `true` is PS5.
    @MenuFocusState var psnKindFocus: Bool?
    /// The PSN picker's focusable rows, reported back so the vertical walk can include them.
    @State var psnLayout = AccountConsolePickerFocus()
    /// Whether the screen is shown, so the first focus stops once it disappears.
    @State var shown = false
    /// The window hosting the screen, so handlers only act on controller input aimed at it.
    @State var hostWindow: PlatformWindow?

    /// Creates an add console view.
    ///
    /// - Parameters:
    ///   - store: The add-console feature; the address and generation fields are bound to it.
    ///   - discovery: The shared local-network scan, whose consoles and ranges the automatic mode lists.
    ///   - failure: The message of the last failed pairing attempt, shown under the mode switch.
    ///   - focus: The focused button, field or console row.
    ///   - modeFocus: The focused segment of the mode switch.
    ///   - kindFocus: The focused segment of the manual generation switch.
    ///   - psnKindFocus: The focused segment of the PSN generation switch; `true` is PS5.
    public init(
        store: StoreOf<AddConsoleFeature>,
        discovery: DiscoveryFeature.State,
        failure: String?,
        focus: AddConsoleFocus? = nil,
        modeFocus: AddConsoleMode? = nil,
        kindFocus: RegistrationFlow.ConsoleKind? = nil,
        psnKindFocus: Bool? = nil
    ) {
        self.store = store
        self.discovery = discovery
        self.failure = failure
        self.focus = focus
        self.modeFocus = modeFocus
        self.kindFocus = kindFocus
        self.psnKindFocus = psnKindFocus
    }

    /// The scanned consoles the account has not paired yet.
    public var availableConsoles: [DiscoveredConsole] {
        store.state.unpaired(in: discovery.snapshot)
    }

    public var body: some View {
        VStack(spacing: 18) {
            Text("Find your console").font(.system(size: 28, weight: .semibold))
                .padding(.bottom, 6)
            FocusableSegments(
                options: store.modes,
                title: Self.title(of:),
                selection: Binding(
                    get: {
                        store.mode
                    },
                    set: {
                        store.send(.view(.selectMode($0)))
                    }
                ),
                focus: $modeFocus
            )
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
            AddConsoleModePane(
                store: store,
                discovery: discovery,
                availableConsoles: availableConsoles,
                focus: $focus,
                focused: focus,
                kindFocus: $kindFocus,
                psnKindFocus: $psnKindFocus,
                psnLayout: $psnLayout,
                retry: {
                    store.send(.view(.retryScan))
                    focusRow(.mode)
                }
            )
            FlowSecondaryButton(label: "Back", focus: AddConsoleFocus.back, focusedAction: $focus) {
                store.send(.view(.back))
            }
        }
        .frame(maxWidth: 440)
        .environment(\.menuMove) { direction in
            _ = move(direction)
        }
        .background(WindowAccessor { hostWindow = $0 })
        .onAppear {
            store.send(.view(.appeared))
            shown = true
            focusInitialRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLibraryContent)) { notification in
            guard let window = notification.object as? PlatformWindow, window === hostWindow else {
                return
            }
            focusInitialRow()
        }
        .onMenuCommand([.previous]) { event in
            cycleMode(by: -1, event: event)
        }
        .onMenuCommand([.next]) { event in
            cycleMode(by: 1, event: event)
        }
        .menuHandlers(
            move: { window, direction in
                guard ownsInput(in: window) else {
                    return false
                }
                return move(direction)
            },
            back: { window in
                guard ownsInput(in: window), !(navigator?.acceptsTextInput(in: window) ?? false) else {
                    return false
                }
                store.send(.view(.back))
                return true
            }
        )
        .onDisappear {
            shown = false
            store.send(.view(.disappeared))
        }
    }

    /// The label of a mode in the mode switch.
    ///
    /// - Parameter mode: The way of finding a console.
    /// - Returns: The segment title.
    public static func title(of mode: AddConsoleMode) -> String {
        switch mode {
        case .automatic:
            "Auto-discovery"
        case .manual:
            "Manual entry"
        case .playStation:
            "PlayStation"
        }
    }

    private var currentRow: Row? {
        if modeFocus != nil {
            return .mode
        }
        if kindFocus != nil {
            return .kind
        }
        if psnKindFocus != nil {
            return .psnKind
        }
        if focus == .continueManual {
            return .control(.address)
        }
        return focus.map {
            .control($0)
        }
    }

    private func focusRow(_ row: Row) {
        switch row {
        case .mode:
            modeFocus = store.mode
        case .kind:
            kindFocus = store.kind
        case .psnKind:
            psnKindFocus = psnLayout.ps5
        case .control(let control):
            focus = control
        }
    }

    private func move(_ direction: MenuMoveDirection) -> Bool {
        guard let currentRow else {
            guard direction == .down else {
                return false
            }
            focusRow(.mode)
            return true
        }
        switch direction {
        case .left, .right:
            return moveHorizontally(from: currentRow, direction: direction)
        case .up, .down:
            moveVertically(from: currentRow, direction: direction)
            return true
        @unknown default:
            return false
        }
    }

    private func moveHorizontally(from row: Row, direction: MenuMoveDirection) -> Bool {
        switch row {
        case .mode, .kind, .psnKind:
            return false
        case .control:
            break
        }
        if focus == .address, direction == .right, store.validAddress != nil {
            focus = .continueManual
        } else if focus == .continueManual, direction == .left {
            focus = .address
        }
        return true
    }

    private func moveVertically(from row: Row, direction: MenuMoveDirection) {
        let rows = AddConsoleRows(
            mode: store.mode,
            layout: psnLayout,
            scanFailed: discovery.phase == .failed,
            available: availableConsoles
        )
        switch rows.neighbour(of: row, going: direction) {
        case .row(let next):
            focusRow(next)
        case .unknown:
            focusRow(.mode)
        case .aboveTop:
            NotificationCenter.default.post(name: .focusSettingsControl, object: WindowFocus.keyWindow)
        case .belowBottom:
            break
        }
    }

    private func ownsInput(in window: PlatformWindow) -> Bool {
        window === WindowFocus.keyWindow
            && window === hostWindow
            && !WindowFocus(window).isAttachedSheet
            && !(navigator?.inputGate.isBlocking ?? false)
            && !(navigator?.isTrackingMenu ?? false)
    }

    private func focusInitialRow() {
        Task { @MainActor in
            for attempt in 0..<20 {
                await Task.yield()
                guard shown, navigator != nil, hostWindow.map({ WindowFocus($0).isOnScreen }) != false else {
                    return
                }
                if attempt == 0 {
                    focusRow(.mode)
                } else if currentRow == nil {
                    if let window = WindowFocus.keyWindow {
                        navigator?.resignFocus(in: window)
                    }
                    focusRow(.mode)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func cycleMode(by offset: Int, event: MenuCommandEvent) {
        let modes = store.modes
        guard let window = event.window,
              window === WindowFocus.keyWindow,
              window === hostWindow,
              !(navigator?.inputGate.isBlocking ?? false),
              let index = modes.firstIndex(of: store.mode) else {
            return
        }
        store.send(.view(.selectMode(modes[(index + offset + modes.count) % modes.count])))
    }
}

/// The add-console screen's vertical stops from top to bottom, which Up and Down walk in order.
///
/// The mode switch comes first and Back last; between them sit the shown mode's switch, retry button and
/// consoles.
private struct AddConsoleRows {
    /// Where a vertical move from a stop leads.
    enum Neighbour: Equatable {
        /// The stop above or below.
        case row(AddConsoleView.Row)
        /// Nothing lies above the first stop.
        case aboveTop
        /// Nothing lies below the last stop.
        case belowBottom
        /// The stop is not on the screen.
        case unknown
    }

    /// The stops, from top to bottom.
    let rows: [AddConsoleView.Row]

    /// Lists the stops of the screen.
    ///
    /// - Parameters:
    ///   - mode: The way of finding a console that is shown.
    ///   - layout: The PSN picker's focusable rows.
    ///   - scanFailed: Whether the local-network scan failed, which shows its Retry button.
    ///   - available: The scanned consoles the account can pair.
    init(
        mode: AddConsoleMode,
        layout: AccountConsolePickerFocus,
        scanFailed: Bool,
        available: [DiscoveredConsole]
    ) {
        var rows: [AddConsoleView.Row] = [.mode]
        switch mode {
        case .manual:
            rows += [.kind, .control(.address)]
        case .playStation:
            rows.append(.psnKind)
            if layout.retry {
                rows.append(.control(.psnRetry))
            }
            rows += layout.consoles.map {
                .control(.psnConsole($0))
            }
        case .automatic:
            if scanFailed {
                rows.append(.control(.retryScan))
            }
            rows += available.map {
                .control(.discovered($0.id))
            }
        }
        rows.append(.control(.back))
        self.rows = rows
    }

    /// The stop a vertical move from a stop leads to.
    ///
    /// - Parameters:
    ///   - row: The focused stop.
    ///   - direction: Up or Down.
    /// - Returns: Where the move leads.
    func neighbour(of row: AddConsoleView.Row, going direction: MenuMoveDirection) -> Neighbour {
        guard let index = rows.firstIndex(of: row) else {
            return .unknown
        }
        let next = direction == .down
            ? index + 1
            : index - 1
        guard rows.indices.contains(next) else {
            return direction == .up
                ? .aboveTop
                : .belowBottom
        }
        return .row(rows[next])
    }
}

/// The part of the add-console screen the chosen mode shows: the PSN account's consoles, the local-network
/// scan and its consoles, or the manual address entry.
private struct AddConsoleModePane: View {
    /// The add-console feature.
    let store: StoreOf<AddConsoleFeature>

    /// The shared local-network scan.
    let discovery: DiscoveryFeature.State

    /// The scanned consoles the account has not paired yet.
    let availableConsoles: [DiscoveredConsole]

    /// The focus of the screen's buttons, fields and console rows.
    let focus: MenuFocusState<AddConsoleFocus?>.Binding

    /// The focused button, field or console row, read when the screen draws.
    let focused: AddConsoleFocus?

    /// The focus of the manual generation switch.
    let kindFocus: MenuFocusState<RegistrationFlow.ConsoleKind?>.Binding

    /// The focus of the PSN generation switch; `true` is PS5.
    let psnKindFocus: MenuFocusState<Bool?>.Binding

    /// The PSN picker's focusable rows, reported back so the screen's vertical walk can include them.
    @Binding var psnLayout: AccountConsolePickerFocus

    /// Starts the local-network scan again.
    let retry: () -> Void

    /// The chosen mode's controls, sliding as the mode changes.
    var body: some View {
        FlowTransition(selection: store.mode) {
            VStack(spacing: 18) {
                switch store.mode {
                case .playStation:
                    if let consoles = store.scope(
                        state: \.accountConsoles,
                        action: \.accountConsoles.presented
                    ) {
                        AccountConsolePickerView(
                            store: consoles,
                            kindFocus: psnKindFocus,
                            focus: focus,
                            focusLayout: $psnLayout
                        )
                    }
                case .automatic:
                    AddConsoleScanPanel(discovery: discovery, focus: focus, retry: retry)
                    DiscoveredConsoleList(consoles: availableConsoles, focus: focus, focused: focused) {
                        store.send(.view(.pickDiscovered($0)))
                    }
                    if availableConsoles.isEmpty, !discovery.snapshot.consoles.isEmpty {
                        Text("All discovered consoles are already paired with this account.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                case .manual:
                    AddConsoleManualEntry(
                        store: store,
                        focus: focus,
                        focused: focused,
                        kindFocus: kindFocus
                    )
                }
            }
        }
    }
}

/// The manual entry of the add-console screen: the console generation and its address, with Continue.
private struct AddConsoleManualEntry: View {
    /// The add-console feature; the address and generation fields are bound to it.
    @Bindable var store: StoreOf<AddConsoleFeature>

    /// The focus of the screen's buttons, fields and console rows.
    let focus: MenuFocusState<AddConsoleFocus?>.Binding

    /// The focused button, field or console row, read when the screen draws.
    let focused: AddConsoleFocus?

    /// The focus of the generation switch.
    let kindFocus: MenuFocusState<RegistrationFlow.ConsoleKind?>.Binding

    /// The generation switch, the address field and Continue.
    var body: some View {
        VStack(spacing: 14) {
            FocusableSegments(
                options: RegistrationFlow.ConsoleKind.allCases,
                title: { $0.rawValue },
                selection: $store.kind,
                focus: kindFocus
            )
            HStack(spacing: 10) {
                TextField("IP address or hostname", text: $store.address)
                    .textFieldStyle(.plain)
                    .streamerHiddenField(store.address)
                    .menuFocusBinding(focus, equals: .address)
                    .controllerKeyboard(
                        title: "Console address",
                        text: $store.address,
                        isFocused: focused == .address
                    )
                    .padding(12).glassPanel(.small)
                    .onSubmit {
                        store.send(.view(.submitAddress))
                    }
                FocusButton("Continue") {
                    store.send(.view(.submitAddress))
                }
                .glassControlStyle().controlSize(.large)
                .menuFocused(focus, equals: .continueManual)
                .disabled(store.validAddress == nil)
            }
        }
        .padding(18).glassPanel(.medium)
    }
}

/// The state of the local-network scan on the add-console screen: whether it runs, the ranges it covers, and a
/// Retry button when it failed.
private struct AddConsoleScanPanel: View {
    /// The shared local-network scan.
    let discovery: DiscoveryFeature.State

    /// The focus of the screen's buttons, fields and console rows.
    let focus: MenuFocusState<AddConsoleFocus?>.Binding

    /// Starts the scan again.
    let retry: () -> Void

    @Environment(\.screenLayout) private var layout

    /// The scan's status and ranges.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if discovery.isScanning {
                    ProgressView().controlSize(.small)
                }
                Text(status).font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if case .failed = discovery.phase {
                    FocusButton("Retry") {
                        retry()
                    }
                    .glassControlStyle()
                    .menuFocused(focus, equals: .retryScan)
                }
            }
            if !discovery.snapshot.broadcastRanges.isEmpty {
                ranges("Broadcast", values: discovery.snapshot.broadcastRanges)
            }
            if !discovery.snapshot.unicastRanges.isEmpty {
                ranges("Unicast", values: discovery.snapshot.unicastRanges)
                Text("\(discovery.snapshot.sweepTargets) addresses, scanned in batches of 64")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(.medium)
    }

    private func ranges(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(values.joined(separator: "\n")).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: String {
        switch discovery.phase {
        case .failed:
            "Couldn’t scan this network"
        case .idle:
            "Discovery paused"
        case .scanning, .listening, .searched:
            if !discovery.snapshot.networkAvailable {
                "Waiting for a network…"
            } else if !discovery.snapshot.consoles.isEmpty {
                "Scanning for consoles"
            } else if discovery.phase.hasSearched {
                "No console has answered yet, still looking…"
            } else {
                "Looking for consoles…"
            }
        }
    }
}

/// The scanned consoles the account can pair, one button each, scrolled so the focused console stays in view.
private struct DiscoveredConsoleList: View {
    /// The consoles to list.
    let consoles: [DiscoveredConsole]

    /// The focus of the screen's buttons, fields and console rows.
    let focus: MenuFocusState<AddConsoleFocus?>.Binding

    /// The focused button, field or console row, read when the screen draws.
    let focused: AddConsoleFocus?

    /// Pairs a console.
    let pick: (DiscoveredConsole) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.streamerMode) private var streamerMode
    @Environment(\.screenLayout) private var layout

    /// The tallest the list grows on a tall screen before it scrolls on its own.
    static let tallHeight: CGFloat = 420

    /// The list, scrolling on its own on a tall screen and with the rest of the screen on a short one, or
    /// nothing when no console is listed.
    @ViewBuilder var body: some View {
        if !consoles.isEmpty {
            if layout.isShort {
                rows
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        rows
                            .selfManagedFocusScrolling()
                    }
                    .appVerticalScrollStyle()
                    .frame(height: min(CGFloat(consoles.count) * 110, Self.tallHeight))
                    .onChange(of: focused) { _, value in
                        if case .discovered(let id) = value {
                            withAnimation(AppMotion.animation(reduced: reduceMotion)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 10) {
            ForEach(consoles) { console in
                row(console)
            }
        }
        .padding(4)
    }

    private func row(_ console: DiscoveredConsole) -> some View {
        FocusButton {
            pick(console)
        } label: {
            HStack(spacing: 16) {
                ConsoleArtwork(
                    height: 64,
                    kind: console.kind == .ps5
                        ? .ps5
                        : .ps4
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(console.name).font(.headline)
                        .foregroundStyle(.primary)
                    Text(
                        console.standby
                            ? "Rest mode"
                            : "Ready"
                    )
                    .font(.caption).foregroundStyle(
                        console.standby
                            ? .orange
                            : .green
                    )
                    Text(StreamerMode.identifier(console.address, enabled: streamerMode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .glassEffect(AppGlass.control.interactive(), in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .focusHighlightShape(.roundedRectangle(20))
        .menuFocused(focus, equals: .discovered(console.id))
        .id(console.id)
    }
}

/// The controls of the add-console screen that take controller focus.
public enum AddConsoleFocus: Hashable {
    /// Retry after the scan failed.
    case retryScan

    /// A console the scan found, by its hardware id.
    case discovered(String)

    /// The typed address field.
    case address

    /// The button that pairs the console at the typed address.
    case continueManual

    /// Retry after the PSN console list failed.
    case psnRetry

    /// A console on the PSN account, by its device id.
    case psnConsole(Data)

    /// The Back button.
    case back
}
