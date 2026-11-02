import ChiakiClients
import ChiakiModels
import Dependencies
import Foundation

/// Routes guest commands to the player of the running guest session.
///
/// The guest stream opens the desk with its player when it starts and closes it when it ends; code entry and
/// remembering the host go to that player only while it runs.
@MainActor public final class KakusanGuestDesk {
    /// Where the desk is.
    enum Phase {
        /// No guest session runs.
        case idle
        /// A guest session runs on a player.
        case running(UUID, any KakusanGuestPlayer)
    }

    /// Where the desk is.
    private(set) var phase = Phase.idle

    /// Creates an idle desk.
    public nonisolated init() {}

    /// Routes commands to a starting guest session.
    ///
    /// - Parameters:
    ///   - session: The session's id.
    ///   - player: The player that runs it.
    public func open(_ session: UUID, player: any KakusanGuestPlayer) {
        phase = .running(session, player)
    }

    /// Stops routing to a player whose session ended.
    ///
    /// - Parameter player: The player.
    public func close(_ player: any KakusanGuestPlayer) {
        guard case .running(_, let current) = phase, current === player else {
            return
        }
        phase = .idle
    }

    /// Remembers the verified host's device on the running session.
    ///
    /// - Parameters:
    ///   - identity: The device's public key, as raw bytes.
    ///   - nickname: The name to save it under.
    ///   - replacing: Whether to take the name from another device.
    /// - Returns: The saved device or why it was not saved, or `nil` when no session runs.
    func remember(
        _ identity: Data,
        _ nickname: String,
        _ replacing: Bool
    ) -> Result<KakusanRememberResult, KakusanError>? {
        guard case .running(_, let player) = phase else {
            return nil
        }
        return player.rememberKakusan(identity, nickname, replacing)
    }

    /// Enters the host's code on the running session.
    ///
    /// - Parameter code: The code.
    /// - Returns: Whether the session accepted it.
    func enterCode(_ code: KakusanCode) -> KakusanCommandOutcome {
        guard case .running(_, let player) = phase else {
            return .rejected(.internal)
        }
        return player.enterKakusanHostCode(code.digits)
    }
}

extension KakusanGuestDesk: DependencyKey {
    /// The desk the live ``ChiakiClients/KakusanClient`` and the guest stream share.
    public nonisolated static let liveValue = KakusanGuestDesk()

    /// A fresh desk for each test.
    public nonisolated static var testValue: KakusanGuestDesk {
        KakusanGuestDesk()
    }
}

extension DependencyValues {
    /// Where guest commands meet the running guest session.
    public var kakusanGuestDesk: KakusanGuestDesk {
        get {
            self[KakusanGuestDesk.self]
        }
        set {
            self[KakusanGuestDesk.self] = newValue
        }
    }
}

/// The part of a stream player that joins a shared session as a guest.
@MainActor public protocol KakusanGuestPlayer: AnyObject {
    /// Enters the code the host reads out.
    ///
    /// - Parameter code: The code's digits.
    /// - Returns: Whether the session accepted it.
    func enterKakusanHostCode(_ code: String) -> KakusanCommandOutcome

    /// Remembers the verified host's device.
    ///
    /// - Parameters:
    ///   - identity: The device's public key, as raw bytes.
    ///   - nickname: The name to save it under.
    ///   - replacing: Whether to take the name from another device.
    /// - Returns: The saved device or the device already holding the name, or why it was not saved.
    func rememberKakusan(_ identity: Data, _ nickname: String, _ replacing: Bool)
        -> Result<KakusanRememberResult, KakusanError>
}
