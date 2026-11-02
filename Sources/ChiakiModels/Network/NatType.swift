/// How reachable this Mac is from the internet, as type 1, 2 or 3.
public enum NatType: Int, Equatable, Sendable {
    /// Type 1: the Mac has a public address of its own.
    case type1 = 1
    /// Type 2: behind a router that keeps one public mapping for every destination.
    case type2 = 2
    /// Type 3: behind a router that gives each destination its own mapping, so peers can rarely reach the Mac.
    case type3 = 3
}

/// Why the NAT type could not be determined.
public enum NatTypeFailure: Error, Equatable, Sendable {
    /// The check was cancelled.
    case cancelled
    /// The Mac could not open a network socket.
    case network
    /// The STUN servers' names did not resolve.
    case unresolved
    /// No STUN server answered, so UDP may be blocked.
    case unanswered
    /// Only one server answered, which is not enough to tell type 2 from type 3.
    case incomplete
}
