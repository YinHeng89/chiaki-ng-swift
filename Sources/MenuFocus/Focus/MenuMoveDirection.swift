import SwiftUI

/// A direction focus moves in: a D-pad press, a stick flick or an arrow key.
///
/// The focus engine uses its own type on every platform instead of SwiftUI's `MoveCommandDirection`, which
/// does not exist on iOS and has an open set of cases.
public enum MenuMoveDirection: Hashable, Sendable, CaseIterable {
    /// Towards the top of the screen.
    case up
    /// Towards the bottom of the screen.
    case down
    /// Towards the leading edge.
    case left
    /// Towards the trailing edge.
    case right

    /// Reads the direction of an arrow key.
    ///
    /// - Parameter key: A key equivalent.
    /// - Returns: `nil` unless `key` is one of the four arrow keys.
    public init?(_ key: KeyEquivalent) {
        switch key {
        case .upArrow:
            self = .up
        case .downArrow:
            self = .down
        case .leftArrow:
            self = .left
        case .rightArrow:
            self = .right
        default:
            return nil
        }
    }

    #if os(macOS)
        /// Reads the direction of a SwiftUI move command.
        ///
        /// - Parameter direction: The direction SwiftUI reported to `onMoveCommand`.
        /// - Returns: `nil` for a direction this engine does not know.
        public init?(_ direction: MoveCommandDirection) {
            switch direction {
            case .up:
                self = .up
            case .down:
                self = .down
            case .left:
                self = .left
            case .right:
                self = .right
            @unknown default:
                return nil
            }
        }
    #endif

    /// Whether the direction moves along the vertical axis.
    public var isVertical: Bool {
        self == .up || self == .down
    }

    /// Whether the direction moves backwards in reading order: up or left.
    public var isBackward: Bool {
        self == .up || self == .left
    }

    /// The arrow key that moves focus in this direction.
    public var key: KeyEquivalent {
        switch self {
        case .up:
            .upArrow
        case .down:
            .downArrow
        case .left:
            .leftArrow
        case .right:
            .rightArrow
        }
    }
}
