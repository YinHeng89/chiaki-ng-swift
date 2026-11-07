import ChiakiDiagnostics
import PlatformUI
import SwiftUI
import ComposableArchitecture
import DesignSystem
import MenuFocus
import Foundation

/// A resizable developer log panel that streams recent log lines, with pause, copy, close and follow controls
/// reachable by controller, and redacts lines while streamer mode is on.
struct LiveLogPanel: View {
    /// The store that supplies log snapshots and the live or paused phase.
    let store: StoreOf<LiveLogReducer>
    /// An optional failure message shown above the log lines.
    var failure: String?
    /// The largest size the panel may grow to; the panel never shrinks below 320 by 180 points.
    var bounds = CGSize(width: 680, height: 340)
    /// The menu focus binding the panel controls register with, or `nil` when the panel is not focus
    /// navigable.
    var focus: MenuFocusState<LiveLogFocus?>.Binding?
    /// Called when an arrow key moves focus off the Follow toggle.
    var move: @MainActor @Sendable (MenuMoveDirection) -> Void = { _ in
    }
    @State private var follow = true
    @State private var size = CGSize(width: 680, height: 340)
    @State private var resizeOrigin: CGSize?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.streamerMode) private var streamerMode
    @State private var redactor = LogRedactor.random()
    private func shown(_ line: String) -> String {
        streamerMode
            ? redactor.redact(line)
            : line
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(.playbackLiveLogTitle).font(.headline)
                Spacer()
                iconButton(
                    pauseLabel,
                    target: .pauseResume,
                    symbol: store.phase == .paused
                        ? "play.fill"
                        : "pause.fill"
                ) {
                    store.send(.pauseResume)
                }
                iconButton(.playbackLiveLogCopy, target: .copy, symbol: "doc.on.doc", action: copy)
                iconButton(.playbackLiveLogClose, target: .close, symbol: "xmark") {
                    store.send(.close)
                }
            }
            HStack {
                Text(store.phase == .paused
                    ? .playbackLiveLogPaused
                    : .playbackLiveLogLive)
                Text(.playbackLiveLogLevel(level: store.snapshot.level.rawValue))
                Spacer()
                Toggle(.playbackLiveLogFollow, isOn: $follow)
                    .toggleStyle(AccentCheckboxToggleStyle(focusable: false))
                    .menuFocusable()
                    .focusEffectDisabled()
                    .modifier(LiveLogPanelFocus(focus: focus, target: .follow))
                    .interactiveGrowth()
                    .onMenuKeyPress(keys: [.return, .space], phases: .down) { _ in
                        follow.toggle()
                        return .handled
                    }
                    .onMenuKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow],
                                    phases: .down) { press in
                        move(direction(for: press.key))
                        return .handled
                    }
            }
            .font(.caption).foregroundStyle(.secondary)
            if store.snapshot.level == .off {
                Text(.playbackLiveLogLoggingOff).font(.caption)
            }
            if store.snapshot.writeFailed {
                Text(.playbackLiveLogWriteFailed).font(.caption)
            }
            if let failure {
                Text(failure).font(.caption).textSelection(.enabled)
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 5) {
                        if store.snapshot.entries.isEmpty {
                            Text(.playbackLiveLogWaiting).foregroundStyle(.secondary)
                        }
                        ForEach(store.snapshot.entries) { entry in
                            Text(shown(entry.line)).id(entry.id).textSelection(.enabled)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
                }
                .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: store.snapshot.entries.last?.id) { _, id in
                    if follow, let id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
                .onChange(of: follow) { _, enabled in
                    if enabled,
                       let id = store.snapshot.entries.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: clamped.width, height: clamped.height)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(
                reduceTransparency
                    ? AnyShapeStyle(opaqueBackground)
                    : AnyShapeStyle(.regularMaterial)
            )
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.12)))
        .overlay(alignment: .bottomLeading) {
            resizeGrip
        }
        .accessibilityIdentifier("developer-log-panel")
    }

    private var opaqueBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }

    private var clamped: CGSize {
        CGSize(
            width: min(max(320, size.width), max(320, bounds.width)),
            height: min(max(180, size.height), max(180, bounds.height))
        )
    }

    private var pauseLabel: LocalizedStringResource {
        if store.phase == .paused {
            return .playbackLiveLogResume
        }
        return .playbackLiveLogPause
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.down.left.and.arrow.up.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .padding(4)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let origin = resizeOrigin ?? clamped
                        resizeOrigin = origin
                        size = CGSize(
                            width: origin.width - value.translation.width,
                            height: origin.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        size = clamped
                        resizeOrigin = nil
                    }
            )
            .help(.playbackLiveLogResizeHelp)
            .accessibilityLabel(.playbackLiveLogResizeAccessibility)
    }

    private func copy() {
        let lines = store.snapshot.entries.map { shown($0.line) }.joined(separator: "\n")
        PlatformPasteboard.copy([failure, lines].compactMap { $0 }.joined(separator: "\n"))
    }

    private func iconButton(
        _ label: LocalizedStringResource,
        target: LiveLogFocus,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        FocusButton(action: action) {
            Image(systemName: symbol).frame(width: 20, height: 20)
        }
        .glassControlStyle()
        .focusBorderShape(.circle)
        .modifier(LiveLogPanelFocus(focus: focus, target: target))
        .environment(\.menuMove, move)
        .help(label)
        .accessibilityLabel(label)
    }

    private func direction(for key: KeyEquivalent) -> MenuMoveDirection {
        switch key {
        case .upArrow:
            .up
        case .downArrow:
            .down
        case .leftArrow:
            .left
        default:
            .right
        }
    }
}

private struct LiveLogPanelFocus: ViewModifier {
    let focus: MenuFocusState<LiveLogFocus?>.Binding?
    let target: LiveLogFocus

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content.menuFocused(focus, equals: target)
        } else {
            content
        }
    }
}

/// Drives the live log panel, polling log snapshots twice a second while live and ignoring snapshots from an
/// observation that has since been paused, closed or restarted.
@Reducer
public struct LiveLogReducer {
    /// Whether the panel is hidden, polling under an observation identifier, or frozen on its last snapshot.
    public enum Phase: Equatable {
        /// `hidden` closes the panel, `live` polls under the given observation identifier, and `paused` keeps
        /// the
        /// last snapshot without polling.
        case hidden, live(UUID), paused
    }
    /// The live log panel state.
    @ObservableState
    public struct State: Equatable {
        /// The current panel phase.
        public var phase: Phase = .hidden
        /// The most recent log snapshot shown in the panel.
        public var snapshot = LiveLogSnapshot()
        /// Whether the panel is on screen, which includes the paused phase.
        public var visible: Bool {
            phase != .hidden
        }
        /// Creates a hidden panel with an empty snapshot.
        public init() {
        }
    }
    /// Events the live log panel handles.
    public enum Action: Equatable {
        /// `toggle` shows or hides the panel, `close` hides it, and `pauseResume` freezes or resumes polling.
        case toggle, close, pauseResume
        /// Delivers a snapshot from the observation with the given identifier.
        case updated(UUID, LiveLogSnapshot)
    }
    /// The client that reads live log snapshots.
    @Dependency(\.liveLog) var client
    /// The clock that paces polling.
    @Dependency(\.continuousClock) var clock
    /// Generates observation identifiers.
    @Dependency(\.uuid) var uuid
    private enum CancelID { case observation }
    /// Creates the reducer.
    public init() {
    }
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .close:
                state.phase = .hidden
                return .cancel(id: CancelID.observation)
            case .toggle:
                if state.visible {
                    state.phase = .hidden
                    return .cancel(id: CancelID.observation)
                }
                return start(&state)
            case .pauseResume:
                switch state.phase {
                case .live:
                    state.phase = .paused
                    return .cancel(id: CancelID.observation)
                case .paused:
                    return start(&state)
                case .hidden:
                    return .none
                }
            case .updated(let id, let snapshot):
                guard state.phase == .live(id) else {
                    return .none
                }
                state.snapshot = snapshot
                return .none
            }
        }
    }
    private func start(_ state: inout State) -> Effect<Action> {
        let id = uuid()
        state.phase = .live(id)
        return .run { [client, clock] send in
            while !Task.isCancelled {
                await send(.updated(id, await client.snapshot()))
                try await clock.sleep(for: .milliseconds(500))
            }
        }.cancellable(id: CancelID.observation, cancelInFlight: true)
    }
}
