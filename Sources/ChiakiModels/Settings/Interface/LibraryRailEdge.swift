/// The window edge the library rail is attached to.
public enum LibraryRailEdge: String, Codable, CaseIterable, Equatable, Sendable {
    /// Along the top edge.
    case top

    /// Along the left edge.
    case left

    /// Along the right edge.
    case right

    /// Along the bottom edge.
    case bottom

    /// Whether the rail runs vertically.
    public var isVertical: Bool {
        self == .left || self == .right
    }
}
