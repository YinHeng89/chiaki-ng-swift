import ChiakiBridge
import ChiakiModels
import CxxStdlib

/// Manages the consoles the open core knows: waking, unpairing, renaming, moving, forgetting and choosing how
/// a stream reaches them.
///
/// Consoles and accounts cross as `ChiakiModels/HardwareID` and `ChiakiModels/AccountID`, so the core is
/// never handed bytes of the wrong length.
public struct ConsoleBridge: Sendable {
    /// Creates a bridge over the process's open core.
    public init() {}

    /// Every console the core knows.
    ///
    /// - Returns: The consoles, empty when the core is closed.
    public func everything() -> [StoredConsole] {
        chiaki_bridge.ConsolesBridge.everything().compactMap(ConsoleFactsReader.console)
    }

    /// Whether an account holds a pairing with a console.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - account: The account.
    /// - Returns: `true` when both are known and paired.
    public func isPaired(_ console: HardwareID, with account: AccountID) -> Bool {
        chiaki_bridge.ConsolesBridge.paired_with(
            chiaki_bridge.Bytes(console.bytes), UsersBridge.vector(account)
        )
    }

    /// Sends a wake packet to a console without waiting for it.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - account: The paired account to wake it as.
    /// - Throws: The `ChiakiModels/WakeRefusal` when the console was not woken.
    public func wake(_ console: HardwareID, as account: AccountID) throws(WakeRefusal) {
        let outcome = chiaki_bridge.ConsolesBridge.wake(
            chiaki_bridge.Request(), UsersBridge.vector(account), chiaki_bridge.Bytes(console.bytes),
            false
        )
        if let refusal = Self.refusal(of: outcome) {
            throw refusal
        }
    }

    /// Forgets a console and every pairing with it.
    ///
    /// - Parameter console: The console.
    /// - Returns: `true` when the console was forgotten.
    @discardableResult
    public func forget(_ console: HardwareID) -> Bool {
        chiaki_bridge.ConsolesBridge.forget(chiaki_bridge.Bytes(console.bytes)).value == nil
    }

    /// Removes one account's pairing with a console.
    ///
    /// - Parameters:
    ///   - account: The account.
    ///   - console: The console.
    /// - Throws: The `ChiakiModels/UnpairRefusal` when the pairing was not removed.
    public func unpair(_ account: AccountID, from console: HardwareID) throws(UnpairRefusal) {
        if let refusal = chiaki_bridge.ConsolesBridge.unpair(
            UsersBridge.vector(account), chiaki_bridge.Bytes(console.bytes)
        ).value {
            throw Self.unpairRefusal(of: refusal)
        }
    }

    /// Renames a console.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - name: The new name.
    /// - Returns: `true` when the console was renamed.
    public func rename(_ console: HardwareID, to name: String) -> Bool {
        Self.changed(chiaki_bridge.ConsolesBridge.rename(
            chiaki_bridge.Bytes(console.bytes),
            std.string(name)
        ))
    }

    /// Records a console's new address.
    ///
    /// - Parameters:
    ///   - console: The console.
    ///   - address: The new address.
    /// - Returns: `true` when the address was taken.
    public func move(_ console: HardwareID, to address: String) -> Bool {
        Self.changed(
            chiaki_bridge.ConsolesBridge.moved_to(
                chiaki_bridge.Bytes(console.bytes),
                std.string(address)
            )
        )
    }

    /// The route the core would take to stream from a console.
    ///
    /// - Parameters:
    ///   - account: The account that streams.
    ///   - console: The console.
    /// - Returns: The route, or `nil` when the core has no preference.
    public func route(for account: AccountID, to console: HardwareID) async -> ConsoleRoute? {
        let route = await CoreCancellation.run { request in
            chiaki_bridge.ConsolesBridge.route(
                request, UsersBridge.vector(account), chiaki_bridge.Bytes(console.bytes)
            ).value
        }
        return route.flatMap(Self.route(of:))
    }

    /// The model route of a core route.
    ///
    /// - Parameter route: The core's route.
    /// - Returns: The route, or `nil` when the core left the choice open.
    static func route(of route: libchiaking.consoles.Route) -> ConsoleRoute? {
        switch route {
        case .automatic:
            nil
        case .home:
            .home
        case .internet:
            .internet
        }
    }

    /// The model refusal of a wake outcome.
    ///
    /// - Parameter outcome: What the core returned.
    /// - Returns: The refusal, or `nil` when the console was woken.
    static func refusal(of outcome: chiaki_bridge.WakeOutcome) -> WakeRefusal? {
        switch outcome.kind() {
        case .woken:
            nil
        case .declined:
            wakeRefusal(of: outcome.decline())
        case .refused:
            outcome.refusal() == .core_closed
                ? .notAvailable
                : .unknown
        }
    }

    /// The model refusal of a core wake refusal.
    ///
    /// - Parameter refusal: The core's refusal.
    /// - Returns: The model refusal.
    static func wakeRefusal(of refusal: libchiaking.consoles.WakeRefusal) -> WakeRefusal {
        switch refusal {
        case .not_paired:
            .notPaired
        case .no_address:
            .noAddress
        case .network:
            .network
        case .not_found:
            .notFound
        case .still_in_rest_mode:
            .stillInRestMode
        case .cancelled:
            .cancelled
        case .forgotten:
            .forgotten
        }
    }

    /// The model refusal of a bridge refusal to unpair.
    ///
    /// - Parameter refusal: The bridge's refusal.
    /// - Returns: The model refusal.
    static func unpairRefusal(of refusal: chiaki_bridge.ConsolesRefusal) -> UnpairRefusal {
        switch refusal {
        case .core_closed:
            .notAvailable
        case .store_unavailable:
            .storeUnavailable
        case .unknown_user, .unknown_console, .invalid_address, .address_not_for_generation, .invalid_title:
            .unknownConsole
        }
    }

    private static func changed(_ outcome: chiaki_bridge.ChangeOutcome) -> Bool {
        outcome.kind() == .changed
    }
}
