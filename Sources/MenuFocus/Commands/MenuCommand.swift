import PlatformUI
import SwiftUI

/// One command from the controller that drives menu navigation.
///
/// The input layer turns button presses into commands; a ``MenuNavigator`` performs them. Directions,
/// confirm and back move and activate focus inside the engine; the remaining commands are delivered to
/// the views that asked for them through ``MenuCommandRouter``.
public enum MenuCommand: CaseIterable, Hashable, Sendable {
    /// Moves focus up.
    case up
    /// Moves focus down.
    case down
    /// Moves focus left.
    case left
    /// Moves focus right.
    case right
    /// Activates the focused control: Cross, A, or Return.
    case confirm
    /// Leaves the current level or cancels a modal: Circle, B, or Escape.
    case back
    /// The secondary action of the focused surface: Square or X.
    case alternate
    /// Selects the previous tab: L1 or LB.
    case previous
    /// Selects the next tab: R1 or RB.
    case next
    /// Opens or closes the stream menu: the configured stream menu shortcut.
    case streamMenu
    /// Moves focus to the toolbar of the current screen: Triangle or Y.
    case focusToolbar
    /// Opens or closes Settings: Options or Menu.
    case settings
    /// Commits the current entry, such as Done on the on-screen keyboard: the right trigger.
    case commit
    /// Toggles shift on the on-screen keyboard: the left trigger.
    case shift

    /// The direction a navigation command moves focus in.
    public var direction: MenuMoveDirection? {
        switch self {
        case .up:
            .up
        case .down:
            .down
        case .left:
            .left
        case .right:
            .right
        case .confirm, .back, .alternate, .previous, .next, .streamMenu, .focusToolbar, .settings, .commit,
             .shift:
            nil
        }
    }

    /// Whether the engine handles the command itself rather than routing it to views.
    ///
    /// Directions, confirm and back move or activate focus; every other command is routed.
    public var isNavigation: Bool {
        switch self {
        case .up, .down, .left, .right, .confirm, .back:
            true
        case .alternate, .previous, .next, .streamMenu, .focusToolbar, .settings, .commit, .shift:
            false
        }
    }
}

/// A secret sequence of controller commands and how much of it has been entered.
///
/// Feed every performed command to ``advance(_:)``. A command that breaks the sequence falls back to the
/// longest run of recent commands that still begins the code, so pressing Up three times before the rest of
/// ``konami`` still completes it.
public struct MenuCommandCode: Equatable, Sendable {
    /// The Konami code's directions: Up, Up, Down, Down, Left, Right, Left, Right.
    public static let konami = MenuCommandCode([.up, .up, .down, .down, .left, .right, .left, .right])

    /// The commands that make up the code.
    public let sequence: [MenuCommand]

    /// How many commands of ``sequence`` have been entered in a row.
    public private(set) var entered = 0

    /// Creates a code with nothing entered.
    ///
    /// - Parameter sequence: The commands that make up the code; it must not be empty.
    public init(_ sequence: [MenuCommand]) {
        precondition(!sequence.isEmpty, "A command code needs at least one command")
        self.sequence = sequence
    }

    /// Records one performed command.
    ///
    /// - Parameter command: The command that was performed.
    /// - Returns: `true` when the command completes the code, which then starts over.
    public mutating func advance(_ command: MenuCommand) -> Bool {
        let recent = Array(sequence.prefix(entered)) + [command]
        entered = (0...recent.count).reversed().first { length in
            length <= sequence.count && Array(recent.suffix(length)) == Array(sequence.prefix(length))
        } ?? 0
        guard entered == sequence.count else {
            return false
        }
        entered = 0
        return true
    }
}

/// A routed controller command and the window it was performed in.
@MainActor
public struct MenuCommandEvent {
    /// The command.
    public let command: MenuCommand

    /// The window the command belongs to, or `nil` when it is meant for whichever window is key.
    public let window: PlatformWindow?

    /// Creates an event.
    ///
    /// - Parameters:
    ///   - command: The command.
    ///   - window: The window it belongs to, or `nil` for the key window.
    public init(command: MenuCommand, window: PlatformWindow?) {
        self.command = command
        self.window = window
    }

    /// Whether the event names a window.
    ///
    /// - Parameter candidate: A window, usually the one hosting the receiving view.
    /// - Returns: `true` when the event names `candidate`.
    public func targets(_ candidate: PlatformWindow?) -> Bool {
        guard let window, let candidate else {
            return false
        }
        return window === candidate
    }

    /// Whether the event belongs to a window, counting an event that names no window as belonging to the
    /// key window.
    ///
    /// - Parameters:
    ///   - candidate: A window, usually the one hosting the receiving view.
    ///   - keyWindow: The window that is key now.
    /// - Returns: `true` when the event names `candidate`, or names no window and `candidate` is key.
    public func targets(_ candidate: PlatformWindow?, keyWindow: PlatformWindow?) -> Bool {
        guard window != nil else {
            return candidate != nil && candidate === keyWindow
        }
        return targets(candidate)
    }
}

/// The one mapping between focus directions and the arrow keys of the hardware keyboard.
///
/// The focus engine synthesises arrow key events for directions no handler took, and reads hardware arrow
/// keys back as directions. Both use this table.
public struct MenuArrowKey: Hashable, Sendable {
    /// The direction the key moves focus in.
    public let direction: MenuMoveDirection

    /// The macOS virtual key code of the arrow key.
    public let keyCode: UInt16

    /// The characters an event for the key carries.
    public let characters: String

    /// Creates the arrow key for a direction.
    ///
    /// - Parameter direction: The direction to move focus in.
    public init(_ direction: MenuMoveDirection) {
        self.direction = direction
        switch direction {
        case .up:
            keyCode = 126
            characters = "\u{F700}"
        case .down:
            keyCode = 125
            characters = "\u{F701}"
        case .left:
            keyCode = 123
            characters = "\u{F702}"
        case .right:
            keyCode = 124
            characters = "\u{F703}"
        }
    }

    /// Reads an arrow key from a macOS virtual key code.
    ///
    /// - Parameter keyCode: The key code of a key event.
    /// - Returns: `nil` unless the code belongs to an arrow key.
    public init?(keyCode: UInt16) {
        guard let direction = MenuMoveDirection.allCases
            .first(where: { MenuArrowKey($0).keyCode == keyCode }) else {
            return nil
        }
        self.init(direction)
    }

    /// Reads the arrow key a navigation command stands for.
    ///
    /// - Parameter command: A controller command.
    /// - Returns: `nil` unless the command is a direction.
    public init?(command: MenuCommand) {
        guard let direction = command.direction else {
            return nil
        }
        self.init(direction)
    }

    /// The SwiftUI key equivalent of the arrow key.
    public var key: KeyEquivalent {
        direction.key
    }

    /// The virtual key codes of the four arrow keys.
    public static let keyCodes: Set<UInt16> = Set(MenuMoveDirection.allCases.map { MenuArrowKey($0).keyCode })
}
