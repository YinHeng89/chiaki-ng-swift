import SwiftUI
import MenuFocus

/// Moves controller focus around the Players panel, where each seat's buttons form a column.
enum StreamPlayersNavigation {
    /// Where focus goes after a move.
    enum Destination: Equatable {
        /// Another control in the panel.
        case control(StreamMenuControl)
        /// Out of the panel to the stream menu's tabs.
        case tabs
        /// Focus stays where it is.
        case stay
    }

    /// The column a control belongs to.
    enum Column: Equatable {
        /// The column of the seat on this pad, where pad 0 is player 1.
        case seat(UInt8)
        /// The remote play section.
        case remote
    }

    /// The column of each control, or `nil` outside the columns.
    ///
    /// A remember control joins the next seat's column, or the remote section when no seat follows it.
    static func columns(of controls: [StreamMenuControl]) -> [Column?] {
        var result = [Column?](repeating: nil, count: controls.count)
        var pendingRemember = [Int]()
        for (index, control) in controls.enumerated() {
            switch control {
            case .playerControls(let pad), .playerRemove(let pad), .playerReassign(let pad),
                 .playerAdd(let pad):
                result[index] = .seat(pad)
                for remember in pendingRemember {
                    result[remember] = .seat(pad)
                }
                pendingRemember = []
            case .remote(.remember):
                pendingRemember.append(index)
            case .remote:
                result[index] = .remote
            default:
                result[index] = nil
            }
        }
        for remember in pendingRemember {
            result[remember] = .remote
        }
        return result
    }

    /// Where focus goes when the player moves from a control.
    ///
    /// Up and down stay within a column, left and right move between seats, and down from a seat reaches the
    /// remote section and then the tabs.
    ///
    /// - Parameters:
    ///   - control: The focused control.
    ///   - direction: The direction of the move.
    ///   - controls: The panel's controls in order.
    ///   - lastSeat: The seat focused last, which moving up out of the remote section returns to.
    static func destination(
        from control: StreamMenuControl,
        direction: MenuMoveDirection,
        controls: [StreamMenuControl],
        lastSeat: UInt8? = nil
    ) -> Destination {
        let columns = columns(of: controls)
        guard let index = controls.firstIndex(of: control), let column = columns[index] else {
            return linear(from: control, direction: direction, controls: controls)
        }
        let members = controls.indices.filter { columns[$0] == column }
        guard let position = members.firstIndex(of: index) else {
            return .stay
        }
        switch direction {
        case .up:
            return position > 0
                ? .control(controls[members[position - 1]])
                : upFromTop(of: column, columns: columns, controls: controls, lastSeat: lastSeat)
        case .down:
            if position + 1 < members.count {
                return .control(controls[members[position + 1]])
            }
            if case .seat = column, let remote = controls.indices.first(where: { columns[$0] == .remote }) {
                return .control(controls[remote])
            }
            return .tabs
        case .left, .right:
            guard case .seat(let pad) = column else {
                let next = position + (direction == .left
                    ? -1
                    : 1)
                return members.indices.contains(next)
                    ? .control(controls[members[next]])
                    : .stay
            }
            return sideways(from: pad, position: position, direction: direction, columns: columns,
                            controls: controls)
        @unknown default:
            return .stay
        }
    }

    private static func upFromTop(
        of column: Column,
        columns: [Column?],
        controls: [StreamMenuControl],
        lastSeat: UInt8?
    ) -> Destination {
        guard column == .remote else {
            return .stay
        }
        let seat = lastSeat.flatMap { pad in
            controls.indices.last { columns[$0] == .seat(pad) }
        } ?? controls.indices.last { index in
            if case .seat = columns[index] {
                return true
            }
            return false
        }
        return seat.map { .control(controls[$0]) } ?? .stay
    }

    private static func sideways(
        from pad: UInt8,
        position: Int,
        direction: MenuMoveDirection,
        columns: [Column?],
        controls: [StreamMenuControl]
    ) -> Destination {
        let pads = columns.compactMap { column -> UInt8? in
            if case .seat(let value) = column {
                return value
            }
            return nil
        }
        let ordered = pads.reduce(into: [UInt8]()) { result, value in
            if result.last != value {
                result.append(value)
            }
        }
        guard let current = ordered.firstIndex(of: pad) else {
            return .stay
        }
        let next = current + (direction == .left
            ? -1
            : 1)
        guard ordered.indices.contains(next) else {
            return .stay
        }
        let members = controls.indices.filter { columns[$0] == .seat(ordered[next]) }
        guard !members.isEmpty else {
            return .stay
        }
        return .control(controls[members[min(position, members.count - 1)]])
    }

    private static func linear(
        from control: StreamMenuControl,
        direction: MenuMoveDirection,
        controls: [StreamMenuControl]
    ) -> Destination {
        guard let index = controls.firstIndex(of: control) else {
            return .stay
        }
        switch direction {
        case .up:
            return index > 0
                ? .control(controls[index - 1])
                : .stay
        case .down:
            return index + 1 < controls.count
                ? .control(controls[index + 1])
                : .tabs
        default:
            return .stay
        }
    }
}
