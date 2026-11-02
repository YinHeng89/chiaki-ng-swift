/// How a stream reaches a paired console.
public enum ConsoleRoute: Hashable, Sendable {
    /// Directly on the local network.
    case home

    /// Over the internet through PlayStation Network.
    case internet

    /// Directly on the local network without asking the core for a route, as a stream started again after the
    /// Mac woke takes the route it played on; right after wake the console can look away from home only because
    /// the network is not back yet.
    case homeOnly

    /// The route a launch asked for.
    ///
    /// - Parameter launch: The launch route.
    public init(_ launch: LaunchRoute) {
        switch launch {
        case .local:
            self = .home
        case .remote:
            self = .internet
        }
    }

    /// Whether the stream goes over the internet.
    public var overInternet: Bool {
        self == .internet
    }

    /// The route for a start: the internet when it was asked for, otherwise the route the core chooses, or
    /// home when the core has no preference.
    ///
    /// - Parameters:
    ///   - internetAsked: Whether the user asked for an internet stream.
    ///   - core: Asks the core which route it would take.
    /// - Returns: The route to start with.
    public static func resolve(
        internetAsked: Bool,
        core: @Sendable () async -> ConsoleRoute?
    ) async -> ConsoleRoute {
        if internetAsked {
            return .internet
        }
        return await core() ?? .home
    }
}
