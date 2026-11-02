/// A cloud launch the catalog already cleared, carried opaquely to the session that starts it.
///
/// The cleared launch is owned by the core; models only keep it alive and compare it by identity. The live
/// cloud launcher reads it back with ``owner(as:)``.
public struct CloudLaunchClearanceToken: Equatable, @unchecked Sendable {
    private let owner: AnyObject

    /// Wraps a cleared launch.
    ///
    /// - Parameter owner: The object that owns the cleared launch.
    public init(_ owner: some AnyObject & Sendable) {
        self.owner = owner
    }

    /// The wrapped cleared launch, when it has the given type.
    ///
    /// - Parameter type: The expected owner type.
    /// - Returns: The owner, or `nil` when it has another type.
    public func owner<Owner: AnyObject>(as type: Owner.Type) -> Owner? {
        owner as? Owner
    }

    /// Whether two clearances wrap the same cleared launch.
    ///
    /// - Parameters:
    ///   - lhs: One clearance.
    ///   - rhs: The other clearance.
    /// - Returns: `true` when both wrap the same object.
    public static func == (lhs: CloudLaunchClearanceToken, rhs: CloudLaunchClearanceToken) -> Bool {
        lhs.owner === rhs.owner
    }
}
