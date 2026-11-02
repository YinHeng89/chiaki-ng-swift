/// The controls a Kakusan card shows, in rows as they are laid out, and the one that is selected.
///
/// The rows are the only list of a card's controls: the card renders a control only when its rows contain it,
/// and controller navigation moves only between them, so the selection can never land on a control the card
/// does not show.
public struct KakusanControlGrid: Equatable, Sendable {
    /// The controls, row by row in reading order.
    public private(set) var rows: [[KakusanControl]]

    /// The selected control, always one of ``rows`` when any control is shown.
    public private(set) var selection: KakusanControl?

    /// Creates a grid, selecting `preferred` when it is shown and the first control otherwise.
    ///
    /// - Parameters:
    ///   - rows: The controls, row by row.
    ///   - preferred: The control to start on.
    public init(_ rows: [[KakusanControl]] = [], preferred: KakusanControl? = nil) {
        self.rows = rows.filter { !$0.isEmpty }
        selection = nil
        settle(preferring: preferred)
    }

    /// Every shown control, in reading order.
    public var controls: [KakusanControl] {
        rows.flatMap(\.self)
    }

    /// Whether a control is shown.
    ///
    /// - Parameter control: The control.
    /// - Returns: `true` when the rows contain it.
    public func shows(_ control: KakusanControl) -> Bool {
        rows.contains { $0.contains(control) }
    }

    /// Replaces the rows, keeping the selection when it is still shown.
    ///
    /// - Parameters:
    ///   - rows: The new rows.
    ///   - preferred: The control to select when the current selection is gone.
    public mutating func show(_ rows: [[KakusanControl]], preferring preferred: KakusanControl? = nil) {
        self.rows = rows.filter { !$0.isEmpty }
        settle(preferring: preferred)
    }

    /// Selects a control, if it is shown.
    ///
    /// - Parameter control: The control.
    public mutating func select(_ control: KakusanControl) {
        if shows(control) {
            selection = control
        }
    }

    /// Moves the selection one step, staying put at an edge.
    ///
    /// Left and right move within the row. Up and down move to the neighbouring row, landing on the control at
    /// the same relative position.
    ///
    /// - Parameter step: The direction.
    public mutating func move(_ step: KakusanGridStep) {
        guard let first = rows.first?.first else {
            selection = nil
            return
        }
        guard let selection,
              let row = rows.firstIndex(where: { $0.contains(selection) }),
              let column = rows[row].firstIndex(of: selection) else {
            self.selection = first
            return
        }
        switch step {
        case .left where column > 0:
            self.selection = rows[row][column - 1]
        case .right where column + 1 < rows[row].count:
            self.selection = rows[row][column + 1]
        case .up where row > 0:
            self.selection = Self.aligned(column, of: rows[row].count, in: rows[row - 1])
        case .down where row + 1 < rows.count:
            self.selection = Self.aligned(column, of: rows[row].count, in: rows[row + 1])
        case .left, .right, .up, .down:
            break
        }
    }

    private mutating func settle(preferring preferred: KakusanControl?) {
        if let selection, shows(selection) {
            return
        }
        if let preferred, shows(preferred) {
            selection = preferred
            return
        }
        selection = rows.first?.first
    }

    private static func aligned(_ column: Int, of count: Int,
                                in target: [KakusanControl]) -> KakusanControl {
        let position = count > 1
            ? Double(column) / Double(count - 1)
            : 0.5
        let index = Int((position * Double(target.count - 1)).rounded())
        return target[min(max(index, 0), target.count - 1)]
    }
}

/// A control on a Kakusan card that controller navigation can select.
public enum KakusanControl: Hashable, Sendable {
    /// Copies the shown block.
    case copy
    /// Pastes a block from the clipboard.
    case paste
    /// Submits the pasted block.
    case connect
    /// Cancels the attempt.
    case cancel
    /// Closes the card.
    case close
    /// The code field.
    case code
    /// Submits the typed code.
    case verify
    /// Starts over with a new invitation.
    case create
    /// Says which remembered device the invitation is for; `nil` for a new device.
    case expect(String?)
    /// Accepts what joining discloses.
    case accept
    /// Steps back.
    case back
    /// Remembers the verified peer.
    case remember
    /// Takes a nickname from another device.
    case replace
    /// Saves the typed name.
    case save
    /// Leaves the session.
    case leave
    /// The name field.
    case name
    /// The block text field.
    case text
}

/// One step of controller navigation on a Kakusan card.
public enum KakusanGridStep: Equatable, Sendable {
    /// Towards the previous control in the row.
    case left
    /// Towards the next control in the row.
    case right
    /// Towards the previous row.
    case up
    /// Towards the next row.
    case down
}
