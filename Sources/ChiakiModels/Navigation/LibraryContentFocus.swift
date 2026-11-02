/// A request that focus enter the library's content, carried in state until the content applies it.
public struct LibraryContentFocus: Equatable, Sendable {
    /// Which control takes focus.
    public let entry: LibraryFocusEntry
    /// The horizontal centre, in window coordinates, of the control focus left, so the content can focus the
    /// control nearest below it; `nil` to use ``entry``.
    public let horizontalPosition: Double?

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - entry: Which control takes focus.
    ///   - horizontalPosition: The horizontal centre of the control focus left, if known.
    public init(_ entry: LibraryFocusEntry, horizontalPosition: Double? = nil) {
        self.entry = entry
        self.horizontalPosition = horizontalPosition
    }
}

/// Which control of the library's content takes focus when focus enters it from the rail or the header.
public enum LibraryFocusEntry: Equatable, Sendable {
    /// The selected filter chip, or the first console.
    case selectedFilter
    /// The first filter chip.
    case firstFilter
    /// The Browse filter chip.
    case browse
    /// The selected platform chip.
    case platform
    /// The control that held focus last.
    case resume
}
