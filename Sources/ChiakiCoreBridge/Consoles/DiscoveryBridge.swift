import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// Searches the local network for consoles through the open core.
///
/// A search blocks a core thread until it is cancelled, so it runs on a dispatch queue; every view the core
/// reports is yielded as a `ChiakiModels/DiscoverySnapshot`.
public struct DiscoveryBridge: Sendable {
    private final class Watcher: @unchecked Sendable {
        let continuation: AsyncThrowingStream<DiscoverySnapshot, any Error>.Continuation

        init(_ continuation: AsyncThrowingStream<DiscoverySnapshot, any Error>.Continuation) {
            self.continuation = continuation
        }
    }

    /// Creates a bridge over the process's open core.
    public init() {}

    /// Normalises discovery settings and checks their subnets the way a search would.
    ///
    /// - Parameter settings: The settings to check.
    /// - Returns: The normalised settings.
    /// - Throws: The `ChiakiModels/DiscoveryFailure` that makes them unusable.
    public func validated(_ settings: DiscoverySettings) throws(DiscoveryFailure) -> DiscoverySettings {
        let normalized = try settings.normalized()
        if let failure = Self.failure(of: chiaki_bridge.DiscoveryBridge.ranges(
            Self.texts(normalized.subnets),
            true
        )) {
            throw failure
        }
        return normalized
    }

    /// Searches until the stream is cancelled.
    ///
    /// - Parameter settings: Which networks to search.
    /// - Returns: The views the search reports; it finishes with the `ChiakiModels/DiscoveryFailure` that
    ///   stopped it, or without error when it was cancelled.
    public func scan(_ settings: DiscoverySettings) -> AsyncThrowingStream<DiscoverySnapshot, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    let settings = try validated(settings)
                    let watcher = Watcher(continuation)
                    let subnets = settings.subnets
                    let unicast = settings.unicastEnabled
                    let failure = await CoreCancellation.run(qos: .utility) { request in
                        withExtendedLifetime(watcher) {
                            Self.failure(of: chiaki_bridge.DiscoveryBridge.search(
                                request, Self.texts(subnets), unicast,
                                { view, context in
                                    guard let view, let context else {
                                        return
                                    }
                                    Unmanaged<Watcher>.fromOpaque(context).takeUnretainedValue().continuation
                                        .yield(DiscoveryBridge.snapshot(of: view.pointee))
                                },
                                Unmanaged.passUnretained(watcher).toOpaque()
                            ))
                        }
                    }
                    if !Task.isCancelled, let failure {
                        throw failure
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// The model snapshot of a view the core reported.
    ///
    /// - Parameter view: The core's view.
    /// - Returns: The snapshot, consoles ordered by hardware id.
    static func snapshot(of view: chiaki_bridge.NetworkView) -> DiscoverySnapshot {
        DiscoverySnapshot(
            consoles: view.nearby.compactMap(console(of:)).sorted { $0.id < $1.id },
            sweepTargets: Int(view.targets),
            sweepVisited: Int(view.visited),
            networkAvailable: view.network_available,
            broadcastRanges: view.broadcast_ranges.map(String.init),
            unicastRanges: view.unicast_ranges.map(String.init)
        )
    }

    /// The discovered console of the facts the core reported.
    ///
    /// - Parameter facts: What the core reported.
    /// - Returns: The console, or `nil` when the hardware id is not six bytes.
    static func console(of facts: chiaki_bridge.ConsoleFacts) -> DiscoveredConsole? {
        guard let hardware = HardwareID(bytes: Array(facts.hardware_id)) else {
            return nil
        }
        return DiscoveredConsole(
            id: hardware.uppercaseHex,
            name: String(facts.name),
            address: facts.address.value.map(String.init) ?? "",
            kind: facts.generation == .ps5
                ? .ps5
                : .ps4,
            standby: facts.presence == .rest_mode
        )
    }

    /// The model failure of a search outcome.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The failure, or `nil` when the search ended normally.
    static func failure(of outcome: chiaki_bridge.SearchOutcome) -> DiscoveryFailure? {
        switch outcome.kind() {
        case .covered:
            return nil
        case .invalid:
            switch outcome.why_invalid() {
            case .subnet, .too_many_subnets:
                return .invalidSubnets
            case .too_many_targets:
                return .tooManyTargets
            }
        case .failed, .refused:
            return .network
        }
    }

    private static func texts(_ subnets: [String]) -> chiaki_bridge.Texts {
        var texts = chiaki_bridge.Texts()
        for subnet in subnets {
            texts.push_back(std.string(subnet))
        }
        return texts
    }
}
