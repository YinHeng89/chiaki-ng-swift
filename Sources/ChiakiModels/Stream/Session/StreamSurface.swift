/// The video view a playing session renders into, carried opaquely to the view that embeds it.
///
/// Models cannot name a platform view type; the stream view reads it back with ``view(as:)``. Two surfaces are
/// equal when they wrap the same view.
public struct StreamSurface: Equatable, @unchecked Sendable {
    private let view: AnyObject

    /// Wraps a video view.
    ///
    /// - Parameter view: The platform view the player renders into.
    public init(_ view: AnyObject) {
        self.view = view
    }

    /// The wrapped view, when it has the given type.
    ///
    /// - Parameter type: The expected view type.
    /// - Returns: The view, or `nil` when it has another type.
    public func view<View: AnyObject>(as type: View.Type) -> View? {
        view as? View
    }

    /// Whether two surfaces wrap the same view.
    ///
    /// - Parameters:
    ///   - lhs: One surface.
    ///   - rhs: The other surface.
    /// - Returns: `true` when both wrap the same view.
    public static func == (lhs: StreamSurface, rhs: StreamSurface) -> Bool {
        lhs.view === rhs.view
    }
}
