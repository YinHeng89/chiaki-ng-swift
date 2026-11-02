import ChiakiClients
import ChiakiModels
import Dependencies
import Foundation

/// The Kakusan operations that reach a running stream through ``KakusanHostDesk`` and
/// ``KakusanGuestDesk``.
///
/// The live `KakusanClient` in `ChiakiClientsLive` pairs these with the core's device store. Each operation
/// reads the desks from the current dependencies and runs on the main actor, where the desks live.
public struct KakusanDesks: Sendable {
    /// Creates the operations over the desks in the current dependencies.
    public init() {}

    /// Arms hosting for the next console stream, unless the calling task was cancelled.
    ///
    /// - Parameters:
    ///   - configuration: The seats to offer.
    ///   - events: Receives the shared session's events in order.
    public func arm(
        _ configuration: KakusanHostConfiguration,
        _ events: @escaping @Sendable (KakusanHostEvent) async -> Void
    ) async {
        @Dependency(\.kakusanHostDesk) var desk
        await MainActor.run {
            guard !Task.isCancelled else {
                return
            }
            desk.arm(configuration, events)
        }
    }

    /// Withdraws hosting.
    public func disarm() async {
        @Dependency(\.kakusanHostDesk) var desk
        await MainActor.run {
            desk.disarm()
        }
    }

    /// Creates an invitation on the armed stream.
    ///
    /// - Returns: The new guest's id, or why no invitation was created.
    public func invite() async -> Result<KakusanGuestID, KakusanError> {
        @Dependency(\.kakusanHostDesk) var desk
        return await MainActor.run {
            desk.invite()
        }
    }

    /// Imports a guest's reply on the armed stream.
    ///
    /// - Parameter block: The reply.
    /// - Returns: The guest the reply belongs to, or why it was refused.
    public func importReply(_ block: KakusanBlock) async -> Result<KakusanGuestID, KakusanError> {
        @Dependency(\.kakusanHostDesk) var desk
        return await MainActor.run {
            desk.importReply(block)
        }
    }

    /// Sends a host command to the shared session.
    ///
    /// - Parameter command: The command.
    /// - Returns: What became of it.
    public func send(_ command: KakusanHostCommand) async -> KakusanCommandOutcome {
        @Dependency(\.kakusanHostDesk) var desk
        return await MainActor.run {
            desk.send(command)
        }
    }

    /// Enters the host's code in the running guest session.
    ///
    /// - Parameter code: The code.
    /// - Returns: What became of it.
    public func enterCode(_ code: KakusanCode) async -> KakusanCommandOutcome {
        @Dependency(\.kakusanGuestDesk) var desk
        return await MainActor.run {
            desk.enterCode(code)
        }
    }

    /// Remembers the peer of whichever session is running, host first.
    ///
    /// - Parameters:
    ///   - peer: The peer to remember.
    ///   - nickname: The name to save it under.
    ///   - replacing: Whether to take the name from the device that holds it.
    /// - Returns: The saved device, or the device that already holds the name.
    /// - Throws: `ChiakiModels/KakusanError/sourceEnded` when no session or device is left, otherwise
    ///   `ChiakiModels/KakusanError/internal`.
    public func remember(
        _ peer: KakusanIdentity,
        _ nickname: String,
        replacing: Bool
    ) async throws -> KakusanRememberResult {
        @Dependency(\.kakusanHostDesk) var host
        @Dependency(\.kakusanGuestDesk) var guest
        let remembered = await MainActor.run { () -> Result<KakusanRememberResult, KakusanError> in
            let identity = peer.publicKey.bytes
            return host.remember(identity, nickname, replacing)
                ?? guest.remember(identity, nickname, replacing)
                ?? .failure(.sourceEnded)
        }
        return try remembered.get()
    }
}
