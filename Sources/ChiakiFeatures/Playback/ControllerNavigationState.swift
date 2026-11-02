import ChiakiModels
import Foundation
import MenuFocus

/// Turns raw controller buttons and axes into menu commands, with key repeat for held directions and blocking
/// of inputs that were already held when the route changed.
public struct ControllerNavigationState {
    /// Where controller input is currently directed.
    public enum Route: Equatable {
        /// `inactive` ignores input, `menu` turns it into menu commands, and `stream` forwards it to the
        /// remote console apart from the stream menu chord.
        case inactive, menu, stream
    }
    /// The menu command type this state machine emits.
    public typealias Command = MenuCommand
    /// Where controller input is currently directed; change it with `setRoute(_:)`.
    public private(set) var route = Route.inactive
    /// The button codes that, held together, open the stream menu from either the menu or the stream route.
    public var streamMenuChord: Set<Int> = StreamMenuShortcut.standard.chord
    /// Whether the PS button opens the stream menu from the stream route, as in PS5 cloud streams.
    public var systemButtonOpensStreamMenu = false
    /// Whether a PS button press on the menu route hands the controller back to the console, press included, as
    /// while the hidden-screen notice's Home button holds it.
    public var systemButtonReachesStream = false
    /// The button code of the PS button.
    public static let systemButton = 5
    private var buttons = Set<Int>()
    private var blockedButtons = Set<Int>()
    /// The latest value of each controller axis, indexed by axis code.
    public private(set) var axes = [Int](repeating: 0, count: 6)
    private var latchedAxes = [Int](repeating: 0, count: 6)
    private var blockedAxes = Set<Int>()
    private var repeatState: RepeatState = .idle

    /// Creates a controller navigation state.
    ///
    /// - Parameter streamMenuChord: The button codes that, held together, open the stream menu from either the menu
    ///   or the stream route.
    public init(streamMenuChord: Set<Int> = StreamMenuShortcut.standard.chord) {
        self.streamMenuChord = streamMenuChord
    }

    private static let triggerCommands: [Int: Command] = [4: .shift, 5: .commit]
    private static let menuCommands: [Int: Command] = [
        0: .confirm,
        1: .back,
        2: .alternate,
        3: .focusToolbar,
        9: .previous,
        10: .next,
        11: .up,
        12: .down,
        13: .left,
        14: .right
    ]
    private enum Source: Equatable {
        case button(Int), axis(Int)
    }
    private enum RepeatState {
        case idle
        case held(Command, Source, deadline: TimeInterval)
    }

    /// Switches input to a new route, blocking every button and deflected axis that is still held so it
    /// cannot leak into the new route, and stopping any key repeat.
    public mutating func setRoute(_ next: Route) {
        guard next != route else {
            return
        }
        route = next
        blockedButtons.formUnion(buttons)
        blockedAxes.formUnion(axes.indices.filter { abs(axes[$0]) > 8000 })
        repeatState = .idle
    }

    /// Clears all held, blocked and repeating input and returns to the inactive route, keeping the configured
    /// stream menu chord.
    public mutating func reset() {
        let chord = streamMenuChord
        let opensMenu = systemButtonOpensStreamMenu
        let reachesStream = systemButtonReachesStream
        self = Self()
        streamMenuChord = chord
        systemButtonOpensStreamMenu = opensMenu
        systemButtonReachesStream = reachesStream
    }

    /// Clears all input state after the active controller changes, keeping the current route and stream menu
    /// chord.
    public mutating func switchController() {
        let current = route
        reset()
        route = current
    }

    /// Feeds a button press or release and returns the commands it produces.
    ///
    /// Options opens settings in menus, the stream menu chord opens the stream menu, and in menus the face,
    /// shoulder and directional buttons map to menu commands. Directional and shoulder buttons start key
    /// repeat while held.
    /// - Parameters:
    ///   - code: The controller button code.
    ///   - down: Whether the button went down rather than up.
    ///   - now: The current time in seconds, used to schedule key repeat.
    /// - Returns: The commands to perform, usually empty or a single command.
    public mutating func button(_ code: Int, down: Bool, now: TimeInterval) -> [Command] {
        let wasDown = buttons.contains(code)
        if down {
            buttons.insert(code)
        } else {
            buttons.remove(code)
            blockedButtons.remove(code)
        }
        guard down != wasDown else {
            return []
        }
        if code == 6, down, route == .menu, !blockedButtons.contains(code) {
            blockedButtons.insert(code)
            repeatState = .idle
            return [.settings]
        }
        if systemButtonOpensStreamMenu, route != .inactive, down, code == Self.systemButton,
           !blockedButtons.contains(code) {
            blockedButtons.insert(code)
            repeatState = .idle
            return [.streamMenu]
        }
        if route != .inactive, down, streamMenuChord.contains(code),
           buttons.isSuperset(of: streamMenuChord), blockedButtons.isDisjoint(with: streamMenuChord) {
            blockedButtons.formUnion(streamMenuChord)
            repeatState = .idle
            return [.streamMenu]
        }
        guard route == .menu, !blockedButtons.contains(code) else {
            return []
        }
        guard let command = Self.menuCommands[code] else {
            return []
        }
        if down {
            if [.up, .down, .left, .right, .previous, .next].contains(command) {
                repeatState = .held(command, .button(code), deadline: now + 0.3)
            } else {
                repeatState = .idle
            }
            return [command]
        }
        if case .held(_, .button(code), _) = repeatState {
            repeatState = .idle
        }
        return []
    }

    /// Feeds an axis value and returns the commands it produces.
    ///
    /// In menus the left stick moves focus once per deflection past the threshold and starts key repeat,
    /// while the left and right triggers send `shift` and `commit`. Returning an axis to rest releases its
    /// latch and block.
    /// - Parameters:
    ///   - code: The axis index.
    ///   - value: The signed axis value.
    ///   - now: The current time in seconds, used to schedule key repeat.
    /// - Returns: The commands to perform, usually empty or a single command.
    public mutating func axis(_ code: Int, value: Int, now: TimeInterval) -> [Command] {
        guard axes.indices.contains(code) else {
            return []
        }
        axes[code] = value
        if abs(value) < 8000 {
            latchedAxes[code] = 0
            blockedAxes.remove(code)
            if case .held(_, .axis(code), _) = repeatState {
                repeatState = .idle
            }
            return []
        }
        if let command = Self.triggerCommands[code] {
            return trigger(code, value: value, command: command)
        }
        let direction = value < 0
            ? -1
            : 1
        guard code < 2, route == .menu, !blockedAxes.contains(code), abs(value) > 20000,
              latchedAxes[code] != direction else {
            return []
        }
        latchedAxes[code] = direction
        let command: Command
        if code == 0 {
            command = value < 0
                ? .left
                : .right
        } else {
            command = value < 0
                ? .up
                : .down
        }
        repeatState = .held(command, .axis(code), deadline: now + 0.3)
        return [command]
    }

    private mutating func trigger(_ code: Int, value: Int, command: Command) -> [Command] {
        guard route == .menu, !blockedAxes.contains(code), value > 20000, latchedAxes[code] != 1 else {
            return []
        }
        latchedAxes[code] = 1
        return [command]
    }

    /// Returns the held direction again once its repeat deadline has passed, then schedules the next repeat.
    /// - Parameter now: The current time in seconds.
    /// - Returns: The repeated command, or `nil` when nothing is due.
    public mutating func repeatCommand(now: TimeInterval) -> Command? {
        guard route == .menu, case .held(let command, let source, let deadline) = repeatState,
              now >= deadline else {
            return nil
        }
        repeatState = .held(command, source, deadline: now + 0.09)
        return command
    }

    /// Whether a button should reach the remote console: only while streaming and only if it was not already
    /// held when the route changed.
    public func permitsStreamButton(_ code: Int) -> Bool {
        route == .stream && !blockedButtons.contains(code)
    }

    /// Whether a button edge hands the controller back to the stream with the press included: a PS button press
    /// on the menu route while ``systemButtonReachesStream`` is on, unless the PS button opens the stream menu.
    /// - Parameters:
    ///   - code: The controller button code.
    ///   - down: Whether the button went down rather than up.
    /// - Returns: `true` when the press should go to the console.
    public func handsControllerToStream(_ code: Int, down: Bool) -> Bool {
        down && route == .menu && systemButtonReachesStream && !systemButtonOpensStreamMenu
            && code == Self.systemButton && !blockedButtons.contains(code)
    }

    /// Whether an axis should reach the remote console: only while streaming and only if it was not already
    /// deflected when the route changed.
    public func permitsStreamAxis(_ code: Int) -> Bool {
        route == .stream && !blockedAxes.contains(code)
    }
}
