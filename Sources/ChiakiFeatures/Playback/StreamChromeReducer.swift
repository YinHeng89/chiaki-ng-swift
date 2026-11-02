import ComposableArchitecture
import CoreGraphics
import Foundation
import MenuFocus

/// A screen corner that holds stream chrome controls, each with its own hover zone that can reveal the
/// chrome.
public enum StreamChromeCorner: Hashable, Sendable, CaseIterable {
    /// The back button corner, the top trailing controls corner, the bottom trailing corner and the stream
    /// menu dock across the bottom middle.
    case topLeading, topTrailing, bottomTrailing, bottom

    /// The rectangle in a view of the given size where pointer hover counts as hovering this corner.
    /// - Parameter size: The size of the stream view.
    /// - Returns: A fixed size zone pinned to this corner.
    public func zone(in size: CGSize) -> CGRect {
        switch self {
        case .topLeading:
            CGRect(x: 0, y: 0, width: 120, height: 120)
        case .topTrailing:
            CGRect(x: size.width - 220, y: 0, width: 220, height: 120)
        case .bottomTrailing:
            CGRect(x: size.width - 180, y: size.height - 120, width: 180, height: 120)
        case .bottom:
            CGRect(x: 180, y: size.height - 120, width: max(0, size.width - 360), height: 120)
        }
    }

    /// The corners whose hover zones contain a point.
    /// - Parameters:
    ///   - point: The pointer location, or `nil` when the pointer is outside the view.
    ///   - size: The size of the stream view.
    /// - Returns: Every corner whose zone contains the point, or an empty set when there is no point.
    public static func corners(at point: CGPoint?, in size: CGSize) -> Set<Self> {
        guard let point else {
            return []
        }
        return Set(allCases.filter { $0.zone(in: size).contains(point) })
    }
}

/// Decides when stream chrome and the pointer are shown, keeping the chrome up while a corner is hovered,
/// focused or pinned and fading it after a linger once a stream is live.
///
/// Where the pointer was left when the stream became live does not count as hovering until it moves, so the
/// chrome, the dock's hint and the pointer still hide on their own.
@Reducer
public struct StreamChromeReducer {
    /// Whether the chrome is always visible or auto hides while a stream is playing.
    public enum Mode: Equatable, Sendable {
        /// `attended` keeps the chrome shown before the stream is live; `streaming` lets it hide once the
        /// corners go idle.
        case attended, streaming
    }

    /// Why a corner is being held visible.
    public enum Reason: Hashable, Sendable {
        /// The pointer is over the corner, a control in it has focus, or a view has pinned it open.
        case hover, focus, pinned
    }

    /// The visibility lifecycle of one corner.
    public enum Phase: Equatable, Sendable {
        /// Nothing holds the corner.
        case idle
        /// At least one reason holds the corner visible.
        case held(Set<Reason>)
        /// The corner was released while streaming and stays visible until the linger with this identifier
        /// elapses.
        case lingering(UUID)
    }

    /// How much of the stream menu dock shows while the chrome is visible.
    ///
    /// ```
    /// collapsed --dockExpanded--> expanded
    /// collapsed, expanded --stream becomes live--> introduced
    /// introduced, expanded --chrome hides or the stream stops being live--> collapsed
    /// ```
    public enum Dock: Equatable, Sendable {
        /// Only the handle shows.
        case collapsed
        /// Only the hint that teaches how to reach the dock shows, as a stream starts.
        case introduced
        /// The dock shows because the handle was hovered or clicked.
        case expanded
    }

    /// The visibility lifecycle of the mouse pointer over the stream.
    public enum Pointer: Equatable, Sendable {
        /// The pointer is visible and not counting down to hide.
        case shown
        /// The pointer is visible and hides when the rest timer with this identifier elapses.
        case resting(UUID)
        /// The pointer is hidden until the mouse moves.
        case hidden
    }

    /// Whether the corners the pointer rests over hold the chrome.
    ///
    /// ```
    /// following --stream becomes live or the controller takes over--> suspended
    /// suspended --pointer moves or crosses into another corner--> following
    /// ```
    public enum Hover: Equatable, Sendable {
        /// The hovered corners hold the chrome.
        case following
        /// The pointer has not moved since the stream became live or the controller took over, so where it was
        /// left does not hold the chrome.
        case suspended
    }

    /// The chrome mode, pointer phase and per corner phases.
    @ObservableState
    public struct State: Equatable {
        /// Whether a stream is live, which decides if the chrome may auto hide.
        public var mode: Mode = .attended
        /// The current pointer visibility phase.
        public var pointer = Pointer.shown
        /// Whether the controller or the pointer drives the interface, which decides if a resting pointer hides
        /// over held chrome.
        public var input = InputMode.pointer
        /// How much of the stream menu dock shows.
        public var dock = Dock.collapsed
        /// Whether the hovered corners hold the chrome.
        public var hover = Hover.following
        /// The corners the pointer is over, as last reported.
        public var hovered = Set<StreamChromeCorner>()
        /// The phase of every corner, starting idle.
        public var phases = Dictionary(
            uniqueKeysWithValues: StreamChromeCorner.allCases.map { ($0, Phase.idle) }
        )

        /// Creates an attended state with the pointer shown and every corner idle.
        public init() {
        }

        /// The phase of a corner, reading a missing entry as idle.
        /// - Parameter corner: The corner to read or write.
        public subscript(corner: StreamChromeCorner) -> Phase {
            get {
                phases[corner] ?? .idle
            }
            set {
                phases[corner] = newValue
            }
        }

        /// The reasons currently holding a corner, or an empty set when it is not held.
        /// - Parameter corner: The corner to inspect.
        public func reasons(_ corner: StreamChromeCorner) -> Set<Reason> {
            if case .held(let reasons) = self[corner] {
                return reasons
            }
            return []
        }

        /// Whether the stream chrome is shown; every corner shows and hides together.
        public var isChromeVisible: Bool {
            mode == .attended || isAnyCornerActive
        }

        /// Whether any corner is held by hover, focus or a pin.
        public var isAnyCornerHeld: Bool {
            StreamChromeCorner.allCases.contains { !reasons($0).isEmpty }
        }

        /// Whether any corner is held or still lingering.
        public var isAnyCornerActive: Bool {
            StreamChromeCorner.allCases.contains { self[$0] != .idle }
        }

        /// Every corner while the chrome is visible, and none otherwise.
        public var visibleCorners: Set<StreamChromeCorner> {
            isChromeVisible
                ? Set(StreamChromeCorner.allCases)
                : []
        }
    }

    /// Events that change chrome and pointer visibility.
    public enum Action: Equatable, Sendable {
        /// The stream became live or stopped being live.
        case streaming(Bool)
        /// The pointer now hovers exactly these corners, which hold the chrome again if the stream became live
        /// while it rested.
        case hovered(Set<StreamChromeCorner>)
        /// Controls in exactly these corners now show focus.
        case focused(Set<StreamChromeCorner>)
        /// Exactly these corners are pinned open by a view.
        case pinned(Set<StreamChromeCorner>)
        /// The linger timer started for a corner has elapsed; ignored if the identifier is stale.
        case lingerElapsed(StreamChromeCorner, UUID)
        /// The pointer moved over the stream, which shows it, lets the corners it is over hold the chrome again
        /// if the stream became live while it rested, and restarts the rest timer while streaming.
        case pointerMoved
        /// The pointer left the stream view, which shows it and cancels the rest timer.
        case pointerLeft
        /// The pointer rest timer elapsed; ignored if the identifier is stale, otherwise hides the pointer
        /// unless a corner is held.
        case pointerRestElapsed(UUID)
        /// The dock's handle was hovered or clicked, which shows the dock while the chrome is visible.
        case dockExpanded
        /// The interface switched to this input mode; while a stream is live the controller taking over hides the
        /// pointer and stops where it rests from holding the chrome.
        case inputModeChanged(InputMode)
    }

    /// How long a released corner stays visible while streaming before it fades.
    public static let linger: Duration = .milliseconds(1500)
    /// How long the dock's hint stays up when a stream becomes live.
    public static let introduction: Duration = .seconds(4)
    /// How long the pointer must stay still while streaming before it hides.
    public static let pointerRest: Duration = .seconds(2)

    /// The clock that times corner lingers and pointer rests.
    @Dependency(\.continuousClock) var clock
    /// The generator for linger and rest timer identifiers.
    @Dependency(\.uuid) var uuid
    private enum CancelID: Hashable {
        case linger(StreamChromeCorner)
        case pointer
    }

    /// Creates the reducer.
    public init() {
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .streaming(let live):
                return setMode(
                    &state,
                    live
                        ? .streaming
                        : .attended
                )
            case .hovered(let corners):
                state.hovered = corners
                state.hover = .following
                return update(&state, .hover, corners)
            case .focused(let corners):
                return update(&state, .focus, corners)
            case .pinned(let corners):
                return update(&state, .pinned, corners)
            case .lingerElapsed(let corner, let id):
                guard state[corner] == .lingering(id) else {
                    return .none
                }
                state[corner] = .idle
                if !state.isChromeVisible {
                    state.dock = .collapsed
                }
                return .none
            case .pointerMoved:
                guard state.hover == .suspended else {
                    return restPointer(&state)
                }
                state.hover = .following
                return .merge(update(&state, .hover, state.hovered), restPointer(&state))
            case .pointerLeft:
                state.pointer = .shown
                return .cancel(id: CancelID.pointer)
            case .pointerRestElapsed(let id):
                guard state.pointer == .resting(id) else {
                    return .none
                }
                state.pointer = state.isAnyCornerHeld && state.input == .pointer
                    ? .shown
                    : .hidden
                return .none
            case .inputModeChanged(let mode):
                state.input = mode
                guard mode == .controller, state.mode == .streaming else {
                    return .none
                }
                state.hover = .suspended
                state.pointer = .hidden
                return .merge(.cancel(id: CancelID.pointer), update(&state, .hover, []))
            case .dockExpanded:
                guard state.isChromeVisible, state.dock == .collapsed else {
                    return .none
                }
                state.dock = .expanded
                return .none
            }
        }
    }

    private func restPointer(_ state: inout State) -> Effect<Action> {
        guard state.mode == .streaming else {
            state.pointer = .shown
            return .cancel(id: CancelID.pointer)
        }
        let id = uuid()
        state.pointer = .resting(id)
        return .run { [clock] send in
            try await clock.sleep(for: Self.pointerRest)
            await send(.pointerRestElapsed(id))
        }
        .cancellable(id: CancelID.pointer, cancelInFlight: true)
    }

    private func update(
        _ state: inout State,
        _ reason: Reason,
        _ corners: Set<StreamChromeCorner>
    ) -> Effect<Action> {
        var effects = [Effect<Action>]()
        for corner in StreamChromeCorner.allCases {
            var reasons = state.reasons(corner)
            if corners.contains(corner) {
                reasons.insert(reason)
            } else {
                reasons.remove(reason)
            }
            effects.append(apply(&state, corner, reasons))
        }
        return .merge(effects)
    }

    private func apply(
        _ state: inout State,
        _ corner: StreamChromeCorner,
        _ reasons: Set<Reason>
    ) -> Effect<Action> {
        let current = state[corner]
        if !reasons.isEmpty {
            state[corner] = .held(reasons)
            if case .lingering = current {
                return .cancel(id: CancelID.linger(corner))
            }
            return .none
        }
        guard case .held = current else {
            return .none
        }
        switch state.mode {
        case .attended:
            state[corner] = .idle
            return .none
        case .streaming:
            return linger(&state, corner)
        }
    }

    private func linger(
        _ state: inout State,
        _ corner: StreamChromeCorner,
        for duration: Duration = Self.linger
    ) -> Effect<Action> {
        let id = uuid()
        state[corner] = .lingering(id)
        return .run { [clock] send in
            try await clock.sleep(for: duration)
            await send(.lingerElapsed(corner, id))
        }
        .cancellable(id: CancelID.linger(corner), cancelInFlight: true)
    }
}

extension StreamChromeReducer {
    private func setMode(_ state: inout State, _ mode: Mode) -> Effect<Action> {
        guard state.mode != mode else {
            return .none
        }
        state.mode = mode
        state.dock = mode == .streaming
            ? .introduced
            : .collapsed
        var effects = [Effect<Action>]()
        switch mode {
        case .streaming:
            state.hover = .suspended
            for corner in StreamChromeCorner.allCases {
                var reasons = state.reasons(corner)
                reasons.remove(.hover)
                state[corner] = reasons.isEmpty
                    ? .idle
                    : .held(reasons)
            }
        case .attended:
            state.hover = .following
            effects.append(update(&state, .hover, state.hovered))
        }
        for corner in StreamChromeCorner.allCases {
            switch (mode, state[corner]) {
            case (.streaming, .idle):
                effects.append(linger(
                    &state,
                    corner,
                    for: corner == .bottom
                        ? Self.introduction
                        : Self.linger
                ))
            case (.attended, .lingering):
                state[corner] = .idle
                effects.append(.cancel(id: CancelID.linger(corner)))
            case (.streaming, _), (.attended, _):
                break
            }
        }
        if mode == .streaming, state.input == .controller {
            state.pointer = .hidden
            effects.append(.cancel(id: CancelID.pointer))
        } else {
            effects.append(restPointer(&state))
        }
        return .merge(effects)
    }
}
