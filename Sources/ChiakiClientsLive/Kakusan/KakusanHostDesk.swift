import ChiakiClients
import ChiakiModels
import Dependencies
import Foundation

/// Meets the host's arming with the console stream player that carries it.
///
/// The host feature arms and disarms through ``ChiakiClients/KakusanClient``; the console stream attaches its player when
/// it presents and detaches it when it tears down. Whichever comes second binds the two, so the arming does
/// not depend on which side starts first. Detaching ends the arming: its event pipe finishes and the next
/// stream needs a new arming.
@MainActor public final class KakusanHostDesk {
    /// Where the desk is.
    enum Phase {
        /// Nothing armed and no player.
        case idle
        /// Armed, waiting for a player.
        case armed(KakusanHostBinding)
        /// A player is attached, nothing armed.
        case playing(any KakusanHostPlayer, accepts: @MainActor () -> Bool)
        /// Armed and attached.
        case hosting(KakusanHostBinding, any KakusanHostPlayer, accepts: @MainActor () -> Bool)
    }

    /// Where the desk is.
    private(set) var phase = Phase.idle

    /// Creates an idle desk.
    public nonisolated init() {}

    /// Arms hosting, replacing any earlier arming.
    ///
    /// - Parameters:
    ///   - configuration: The seats to offer.
    ///   - handler: Receives the arming's events.
    func arm(
        _ configuration: KakusanHostConfiguration,
        _ handler: @escaping @Sendable (KakusanHostEvent) async -> Void
    ) {
        let binding = KakusanHostBinding(configuration: configuration, handler: handler)
        switch phase {
        case .idle:
            phase = .armed(binding)
        case .armed(let previous):
            previous.events.finish()
            phase = .armed(binding)
        case let .playing(player, accepts):
            binding.attach(player, accepts: accepts)
            phase = .hosting(binding, player, accepts: accepts)
        case let .hosting(previous, player, accepts):
            player.disarmKakusanHost()
            previous.detach(player)
            previous.events.finish()
            binding.attach(player, accepts: accepts)
            phase = .hosting(binding, player, accepts: accepts)
        }
    }

    /// Withdraws the arming, if any.
    func disarm() {
        switch phase {
        case .idle, .playing:
            break
        case .armed(let binding):
            binding.events.finish()
            phase = .idle
        case let .hosting(binding, player, _):
            player.disarmKakusanHost()
            binding.detach(player)
            binding.events.finish()
            phase = .idle
        }
    }

    /// Attaches the console stream player, arming it when an arming is waiting.
    ///
    /// - Parameters:
    ///   - player: The player that is about to start.
    ///   - accepts: Whether the player's run still owns the stream.
    public func attach(_ player: any KakusanHostPlayer, accepts: @escaping @MainActor () -> Bool) {
        switch phase {
        case .idle, .playing:
            phase = .playing(player, accepts: accepts)
        case .armed(let binding):
            binding.attach(player, accepts: accepts)
            phase = .hosting(binding, player, accepts: accepts)
        case let .hosting(binding, previous, _):
            binding.detach(previous)
            binding.attach(player, accepts: accepts)
            phase = .hosting(binding, player, accepts: accepts)
        }
    }

    /// Detaches a player and ends the arming it carried.
    ///
    /// - Parameter player: The player that stopped.
    public func detach(_ player: any KakusanHostPlayer) {
        switch phase {
        case .idle, .armed:
            break
        case .playing(let current, _):
            if current === player {
                phase = .idle
            }
        case let .hosting(binding, current, _):
            guard current === player else {
                return
            }
            binding.detach(player)
            binding.events.finish()
            phase = .idle
        }
    }

    /// Creates an invitation on the armed player.
    ///
    /// - Returns: The new guest, or `ChiakiModels/KakusanError/internal` when nothing is armed.
    func invite() -> Result<KakusanGuestID, KakusanError> {
        armedPlayer?.makeKakusanInvitation() ?? .failure(.internal)
    }

    /// Imports a guest's reply on the armed player.
    ///
    /// - Parameter block: The reply.
    /// - Returns: The guest the reply belongs to, or why it was refused.
    func importReply(_ block: KakusanBlock) -> Result<KakusanGuestID, KakusanError> {
        armedPlayer?.acceptKakusanReply(block.text) ?? .failure(.internal)
    }

    /// Sends a command to the armed player.
    ///
    /// - Parameter command: The command.
    /// - Returns: Whether the session accepted it.
    func send(_ command: KakusanHostCommand) -> KakusanCommandOutcome {
        armedPlayer?.sendKakusan(command) ?? .rejected(.internal)
    }

    /// Remembers a verified guest's device on the armed player.
    ///
    /// - Parameters:
    ///   - identity: The device's public key, as raw bytes.
    ///   - nickname: The name to save it under.
    ///   - replacing: Whether to take the name from another device.
    /// - Returns: The saved device or why it was not saved, or `nil` when nothing is hosting.
    func remember(
        _ identity: Data,
        _ nickname: String,
        _ replacing: Bool
    ) -> Result<KakusanRememberResult, KakusanError>? {
        armedPlayer?.rememberKakusan(identity, nickname, replacing)
    }

    private var armedPlayer: (any KakusanHostPlayer)? {
        guard case .hosting(let binding, _, _) = phase else {
            return nil
        }
        return binding.player
    }
}

extension KakusanHostDesk: DependencyKey {
    /// The desk the live ``ChiakiClients/KakusanClient`` and the console stream share.
    public nonisolated static let liveValue = KakusanHostDesk()

    /// A fresh desk for each test.
    public nonisolated static var testValue: KakusanHostDesk {
        KakusanHostDesk()
    }
}

extension DependencyValues {
    /// Where the host's arming meets the console stream player.
    public var kakusanHostDesk: KakusanHostDesk {
        get {
            self[KakusanHostDesk.self]
        }
        set {
            self[KakusanHostDesk.self] = newValue
        }
    }
}

/// One arming of the host: its configuration and the pipe its events go out through.
///
/// A binding is attached to at most one player at a time. An arming the player refuses is reported once as
/// `ChiakiModels/KakusanHostEvent/unavailable(_:)`.
@MainActor final class KakusanHostBinding {
    /// The seats the arming offers.
    let configuration: KakusanHostConfiguration
    /// Where the arming's events go.
    let events: KakusanEventPipe<KakusanHostEvent>
    /// The player the arming is attached to.
    private(set) weak var player: (any KakusanHostPlayer)?
    private var armFailureReported = false

    /// Creates an arming that is not attached to a player yet.
    ///
    /// - Parameters:
    ///   - configuration: The seats to offer.
    ///   - handler: Receives the arming's events.
    init(
        configuration: KakusanHostConfiguration,
        handler: @escaping @Sendable (KakusanHostEvent) async -> Void
    ) {
        self.configuration = configuration
        events = KakusanEventPipe(handler)
    }

    /// Arms a player and forwards its events while `accepts` allows.
    ///
    /// - Parameters:
    ///   - player: The console stream player.
    ///   - accepts: Whether the player's run still owns the stream.
    func attach(_ player: any KakusanHostPlayer, accepts: @escaping @MainActor () -> Bool) {
        if case .rejected(let error) = player.armKakusan(configuration) {
            reportArmFailure(error)
            return
        }
        self.player = player
        player.receiveKakusanEvents { [weak self] native in
            guard let self, accepts(), let event = native.hostEvent else {
                return
            }
            self.events.deliver(event)
        }
    }

    /// Stops forwarding a player's events.
    ///
    /// - Parameter player: The player.
    func detach(_ player: any KakusanHostPlayer) {
        player.receiveKakusanEvents(nil)
        if self.player === player {
            self.player = nil
        }
    }

    private func reportArmFailure(_ error: KakusanError) {
        guard !armFailureReported else {
            return
        }
        armFailureReported = true
        events.deliver(.unavailable(error))
    }
}

/// Delivers native events to an async handler in order, one at a time, from the main actor.
@MainActor public final class KakusanEventPipe<Event: Sendable> {
    private let continuation: AsyncStream<Event>.Continuation
    private let consumer: Task<Void, Never>

    /// Starts delivering to a handler.
    ///
    /// - Parameter handler: Receives each event after the previous one was handled.
    public init(_ handler: @escaping @Sendable (Event) async -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.continuation = continuation
        consumer = Task {
            for await event in stream {
                await handler(event)
            }
        }
    }

    /// Queues an event.
    ///
    /// - Parameter event: The event.
    public func deliver(_ event: Event) {
        continuation.yield(event)
    }

    /// Stops accepting events; queued ones are still delivered.
    public func finish() {
        continuation.finish()
    }

    /// Stops accepting events and waits until every queued one was handled.
    public func drain() async {
        continuation.finish()
        await consumer.value
    }
}

/// The part of a console stream player that hosts a shared session.
@MainActor public protocol KakusanHostPlayer: AnyObject {
    /// Arms hosting before the stream starts.
    ///
    /// - Parameter configuration: The seats to offer.
    /// - Returns: Whether the player accepted the arming.
    func armKakusan(_ configuration: KakusanHostConfiguration) -> KakusanCommandOutcome

    /// Withdraws hosting armed before the stream started.
    func disarmKakusanHost()

    /// Installs or removes the handler for the session's events.
    ///
    /// - Parameter handler: Receives each event on the main actor; `nil` removes the handler.
    func receiveKakusanEvents(_ handler: (@MainActor (KakusanStreamEvent) -> Void)?)

    /// Creates an invitation.
    ///
    /// - Returns: The new guest, or why the session refused.
    func makeKakusanInvitation() -> Result<KakusanGuestID, KakusanError>

    /// Imports a guest's reply.
    ///
    /// - Parameter text: The reply block's text.
    /// - Returns: The guest the reply belongs to, or why the session refused it.
    func acceptKakusanReply(_ text: String) -> Result<KakusanGuestID, KakusanError>

    /// Sends a command to the session.
    ///
    /// - Parameter command: The command.
    /// - Returns: Whether the session accepted it.
    func sendKakusan(_ command: KakusanHostCommand) -> KakusanCommandOutcome

    /// Remembers a verified guest's device.
    ///
    /// - Parameters:
    ///   - identity: The device's public key, as raw bytes.
    ///   - nickname: The name to save it under.
    ///   - replacing: Whether to take the name from another device.
    /// - Returns: The saved device or the device already holding the name, or why it was not saved.
    func rememberKakusan(_ identity: Data, _ nickname: String, _ replacing: Bool)
        -> Result<KakusanRememberResult, KakusanError>
}
