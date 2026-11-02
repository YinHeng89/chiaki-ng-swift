import ChiakiModels
import ComposableArchitecture
import Foundation
import SwiftUI

/// The on-screen gamepad for touch play: which controls are held, whether the gamepad and its secondary
/// controls are visible, and whether the stream menu or an overlay takes touches instead.
///
/// The gamepad rests as a faint outline ``restDelay`` after its last use and the secondary controls fade
/// ``secondaryLinger`` after theirs, each timed by a cancellable clock effect that waits again while a control
/// still holds it. Every change to the pad is published into the ``VirtualGamepadLink`` as it is reduced, where
/// the stream's input takes it each frame.
///
/// ```
/// attention: awake --rest elapsed while idle--> resting --any use--> awake
/// secondary: hidden --reveal or a secondary control--> lit --linger elapsed while none is held--> hidden
/// ```
@Reducer
public struct VirtualGamepadFeature {
    /// Whether the secondary controls, such as shoulders, triggers, the D-pad and system buttons, are shown.
    public enum Secondary: Equatable, Sendable {
        /// The secondary controls are faded out.
        case hidden
        /// The secondary controls are visible after recent use.
        case lit
    }

    /// Whether the gamepad is drawn in full or rests as a faint outline after a spell without touches.
    public enum Attention: Equatable, Sendable {
        /// The gamepad is drawn in full.
        case awake
        /// The gamepad has faded to a faint outline and still takes touches, which wake it.
        case resting
    }

    /// How much of the stream menu is open, which decides whether the gamepad gives way to it.
    public enum StreamMenu: Equatable, Sendable {
        /// The stream menu is closed.
        case closed
        /// A full stream menu panel is open.
        case panel
    }

    /// The on-screen gamepad's state.
    @ObservableState
    public struct State: Equatable {
        /// The held buttons and stick positions.
        public var pad = VirtualGamepad()
        /// Whether the secondary controls are currently visible.
        public var secondary = Secondary.hidden
        /// Whether the gamepad is drawn in full or resting.
        public var attention = Attention.awake
        /// When the gamepad is shown now: the saved choice, or the stream's own toggle once used.
        public var presence = VirtualGamepadPresence.automatic
        /// The saved presence, which replaces ``presence`` only when it changes.
        public var preferred = VirtualGamepadPresence.automatic
        /// How much of the stream menu is open.
        public var streamMenu = StreamMenu.closed
        /// Whether a panel, sheet or other presentation holds the menu input gate.
        public var overlayBlocking = false
        /// Whether the stream's input has lent the gamepad a virtual touchpad.
        public var touchpadAttached = false
        /// Whether the gamepad was used within the last ``VirtualGamepadFeature/recentUse``.
        public var usedJustNow = false
        /// Whether a debug build shows the gamepad over a dimmed screen for previews and test scripts.
        public var previewing = false

        /// Creates a gamepad with nothing held, in the automatic presence and awake.
        public init() {
        }

        /// Whether the gamepad gives way to an open stream menu panel or a blocking overlay.
        public var yieldsToOverlay: Bool {
            switch streamMenu {
            case .closed:
                overlayBlocking
            case .panel:
                true
            }
        }
    }

    /// What touches, the stream's input and the clock do to the gamepad.
    public enum Action: Equatable, Sendable {
        /// A control was pressed or released.
        case pressed(PlayStationControl, down: Bool)
        /// A stick moved to a position from -1 to 1 on each axis.
        case moved(VirtualGamepad.Stick, x: Double, y: Double)
        /// A stick returned to centre.
        case released(VirtualGamepad.Stick)
        /// The gamepad was touched without pressing a control, which wakes it.
        case touched
        /// The secondary controls were asked for, which shows them and restarts their linger.
        case secondaryRevealed
        /// The stream's toggle flipped the gamepad's visibility.
        case presenceToggled(controllerConnected: Bool)
        /// The saved presence was loaded; it replaces the stream's toggle only when it changed.
        case preferred(VirtualGamepadPresence)
        /// Every held control and stick should be released.
        case releasedAll
        /// The stream's input lent the gamepad its virtual touchpad.
        case touchpadAttached
        /// The stream's input took its virtual touchpad back, which returns the gamepad to the saved presence.
        case touchpadDetached
        /// The stream menu opened a panel or closed.
        case streamMenuChanged(StreamMenu)
        /// The menu input gate started or stopped blocking.
        case overlayBlockingChanged(Bool)
        /// A debug build turned the preview on or off.
        case previewToggled
        /// The gamepad's layer appeared, which starts its rest timer.
        case appeared
        /// The gamepad's layer went away, which releases everything and stops its timers.
        case disappeared
        /// The rest timer elapsed.
        case restElapsed
        /// The secondary controls' linger elapsed.
        case lingerElapsed
        /// The recent use window elapsed.
        case recentUseElapsed
    }

    /// How long the gamepad stays fully drawn after its last use.
    public static let restDelay: Duration = .seconds(10)
    /// How long the secondary controls stay visible after their last use.
    public static let secondaryLinger: Duration = .seconds(4)
    /// How long a use counts as just now, so a touch on the gamepad does not also reveal the stream chrome.
    public static let recentUse: Duration = .milliseconds(400)
    /// The controls whose use reveals the secondary controls and keeps them visible while held.
    public static let secondaryControls: [PlayStationControl] = [
        .leftTrigger, .leftShoulder, .rightTrigger, .rightShoulder,
        .dpadUp, .down, .left, .right, .share, .options, .system, .touchpad
    ]

    private enum CancelID: Hashable {
        case rest
        case linger
        case recentUse
    }

    /// The clock that times the rest, the linger and the recent use window.
    @Dependency(\.continuousClock) var clock
    /// Where the pad state is published for the stream's input.
    @Dependency(\.virtualGamepadLink) var link

    /// Creates the reducer.
    public init() {
    }

    /// Reduces each action and publishes the pad state whenever it changed, before the next action can reduce.
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            let before = state.pad.state
            let effect = apply(action, to: &state)
            guard state.pad.state != before else {
                return effect
            }
            publish(state.pad.state)
            return effect
        }
    }

    private func apply(_ action: Action, to state: inout State) -> Effect<Action> {
        switch action {
        case .pressed(let control, let down):
            var effects = [use(&state)]
            if Self.secondaryControls.contains(control) {
                effects.append(reveal(&state))
            }
            if state.pad.holds(control) != down {
                state.pad.press(control, down: down)
            }
            return .merge(effects)
        case .moved(let stick, let x, let y):
            state.pad.move(stick, x: x, y: y)
            return use(&state)
        case .released(let stick):
            state.pad.release(stick)
            return use(&state)
        case .touched:
            return use(&state)
        case .secondaryRevealed:
            return reveal(&state)
        case .presenceToggled(let controllerConnected):
            state.presence = state.presence.toggled(controllerConnected: controllerConnected)
            if !state.presence.isVisible(controllerConnected: controllerConnected) {
                state.pad.releaseAll()
            }
            return use(&state)
        case .preferred(let saved):
            guard saved != state.preferred else {
                return .none
            }
            state.preferred = saved
            state.presence = saved
            if !saved.isVisible(controllerConnected: false) {
                state.pad.releaseAll()
            }
            return .none
        case .releasedAll:
            state.pad.releaseAll()
            return .none
        case .touchpadAttached:
            state.touchpadAttached = true
            return .none
        case .touchpadDetached:
            guard state.touchpadAttached else {
                return .none
            }
            state.touchpadAttached = false
            state.presence = state.preferred
            return .none
        case .streamMenuChanged(let menu):
            state.streamMenu = menu
            return yield(&state)
        case .overlayBlockingChanged(let blocking):
            state.overlayBlocking = blocking
            return yield(&state)
        case .previewToggled:
            state.previewing.toggle()
            return .none
        case .appeared:
            return .merge(rest(), state.secondary == .lit ? linger() : .none)
        case .disappeared:
            state.pad.releaseAll()
            return .merge(.cancel(id: CancelID.rest), .cancel(id: CancelID.linger))
        case .restElapsed:
            guard state.attention == .awake else {
                return .none
            }
            guard state.pad.isIdle else {
                return rest()
            }
            state.attention = .resting
            return .none
        case .lingerElapsed:
            guard state.secondary == .lit else {
                return .none
            }
            let pad = state.pad
            guard !Self.secondaryControls.contains(where: pad.holds) else {
                return linger()
            }
            state.secondary = .hidden
            return .none
        case .recentUseElapsed:
            state.usedJustNow = false
            return .none
        }
    }

    private func use(_ state: inout State) -> Effect<Action> {
        state.attention = .awake
        state.usedJustNow = true
        return .merge(rest(), recentUse())
    }

    private func reveal(_ state: inout State) -> Effect<Action> {
        state.secondary = .lit
        return linger()
    }

    private func yield(_ state: inout State) -> Effect<Action> {
        if state.yieldsToOverlay {
            state.pad.releaseAll()
        }
        return .none
    }

    private func rest() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.restDelay)
            await send(.restElapsed)
        }
        .cancellable(id: CancelID.rest, cancelInFlight: true)
    }

    private func linger() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.secondaryLinger)
            await send(.lingerElapsed)
        }
        .cancellable(id: CancelID.linger, cancelInFlight: true)
    }

    private func recentUse() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: Self.recentUse)
            await send(.recentUseElapsed)
        }
        .cancellable(id: CancelID.recentUse, cancelInFlight: true)
    }

    private func publish(_ pad: ControllerState) {
        let link = link
        MainActor.assumeIsolated {
            link.publish(pad)
        }
    }
}

extension EnvironmentValues {
    /// The on-screen gamepad's store, which the root view supplies to the stream's views.
    @Entry public var virtualGamepad: StoreOf<VirtualGamepadFeature>? = nil
}
