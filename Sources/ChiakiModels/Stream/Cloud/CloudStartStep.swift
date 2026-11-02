/// The steps a cloud stream passes before its first frame, in the order the core reports them.
public enum CloudStartStep: Int, Hashable, Sendable, CaseIterable, Comparable {
    /// The account's cloud access is checked.
    case checking = 1

    /// The service prepares the title.
    case preparing

    /// The service looks for a streaming server.
    case findingServer

    /// The stream connects and waits for its first frame.
    case connecting

    /// How the step reads in the launch log.
    public var logDescription: String {
        switch self {
        case .checking:
            "Checking cloud access"
        case .preparing:
            "Preparing your game"
        case .findingServer:
            "Finding a streaming server"
        case .connecting:
            "Waiting for the first frame"
        }
    }

    /// Orders steps by when they happen.
    ///
    /// - Parameters:
    ///   - lhs: One step.
    ///   - rhs: The other step.
    /// - Returns: `true` when `lhs` comes before `rhs`.
    public static func < (lhs: CloudStartStep, rhs: CloudStartStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A wait inside a cloud start step that the user sees.
public enum CloudStartWait: Equatable, Sendable {
    /// The account is queued for a server at the given position.
    case queued(position: Int)

    /// Datacenters were offered and the choice is open, being sent, or settled.
    case datacenter(CloudDatacenterChoice)
}

/// The user's choice among the datacenters a cloud launch offered, as a finite state machine.
///
/// ```
/// offered --tick (more left)--> offered
/// offered --tick (last)--> expired
/// offered --choose(name)--> sending --sent(accepted)--> sent
///                                   --sent(refused)--> expired
/// ```
public enum CloudDatacenterChoice: Equatable, Sendable {
    /// The offer is shown with the seconds left to choose.
    case offered(CloudDatacenterLaunchOffer, remaining: Int)

    /// The named datacenter was chosen and is being sent to the core.
    case sending(CloudDatacenterLaunchOffer, name: String)

    /// The core took the named datacenter.
    case sent(name: String)

    /// The offer timed out or the choice was refused; the service picks the lowest ping.
    case expired

    /// Opens a choice for an offer.
    ///
    /// - Parameter offer: The datacenters offered.
    public init(offer: CloudDatacenterLaunchOffer) {
        self = .offered(offer, remaining: offer.timeoutSeconds)
    }

    /// The offer still shown, while it can be chosen from or the choice is being sent.
    public var offer: CloudDatacenterLaunchOffer? {
        switch self {
        case .offered(let offer, _), .sending(let offer, _):
            offer
        case .sent, .expired:
            nil
        }
    }

    /// Counts one second down.
    ///
    /// - Returns: `true` when the choice moved; an offer at its last second expires.
    @discardableResult
    public mutating func tick() -> Bool {
        guard case .offered(let offer, let remaining) = self else {
            return false
        }
        self = remaining > 1
            ? .offered(offer, remaining: remaining - 1)
            : .expired
        return true
    }

    /// Chooses an offered datacenter.
    ///
    /// - Parameter name: The datacenter's name.
    /// - Returns: `true` when the offer is open and lists `name`.
    @discardableResult
    public mutating func choose(_ name: String) -> Bool {
        guard case .offered(let offer, _) = self, offer.offers(name) else {
            return false
        }
        self = .sending(offer, name: name)
        return true
    }

    /// Records whether the core took the choice being sent.
    ///
    /// - Parameters:
    ///   - name: The datacenter that was sent.
    ///   - accepted: Whether the core took it.
    /// - Returns: `true` when `name` is the choice being sent.
    @discardableResult
    public mutating func sent(_ name: String, accepted: Bool) -> Bool {
        guard case .sending(_, let pending) = self, pending == name else {
            return false
        }
        self = accepted
            ? .sent(name: name)
            : .expired
        return true
    }
}
