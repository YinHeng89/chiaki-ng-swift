import ChiakiBridge
import ChiakiModels
import Foundation

/// Finds this Mac's NAT type through the open core.
///
/// The check talks to STUN servers and blocks a core thread, so it runs on a dispatch queue while the calling task
/// waits; cancelling the task cancels the check.
public struct NatTypeBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// Runs the check.
    ///
    /// - Returns: The NAT type.
    /// - Throws: The `ChiakiModels/NatTypeFailure` that stopped it.
    public func natType() async throws(NatTypeFailure) -> NatType {
        let result = await CoreCancellation.run(qos: .utility) { request in
            Self.result(of: chiaki_bridge.NetworkBridge.nat_type(request))
        }
        return try result.get()
    }

    /// The model result of the bridge's outcome.
    ///
    /// - Parameter outcome: What the core reported.
    /// - Returns: The type, or why there is none.
    static func result(of outcome: chiaki_bridge.NatTypeOutcome) -> Result<NatType, NatTypeFailure> {
        switch outcome.kind() {
        case .found:
            .success(natType(of: outcome.type()))
        case .failed:
            .failure(failure(of: outcome.reason()))
        case .closed:
            .failure(.network)
        }
    }

    /// The model NAT type of the core's.
    ///
    /// - Parameter type: The core's NAT type.
    /// - Returns: The model NAT type.
    static func natType(of type: libchiaking.play.NatType) -> NatType {
        switch type {
        case .type1:
            .type1
        case .type2:
            .type2
        case .type3:
            .type3
        }
    }

    /// The model failure of the core's reason.
    ///
    /// - Parameter reason: Why the core's check failed.
    /// - Returns: The model failure.
    static func failure(of reason: libchiaking.play.NatTypeFailure.Reason) -> NatTypeFailure {
        switch reason {
        case .cancelled:
            .cancelled
        case .network:
            .network
        case .unresolved:
            .unresolved
        case .unanswered:
            .unanswered
        case .incomplete:
            .incomplete
        }
    }
}
