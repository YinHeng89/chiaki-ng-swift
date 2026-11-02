import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiClients
import ChiakiCoreBridge
import ChiakiModels
import Foundation
import Video

extension CNLiveVideoPlayer: KakusanHostPlayer {
    /// Arms hosting with the configuration's seats.
    ///
    /// - Parameter configuration: The seats to offer.
    /// - Returns: Whether the player accepted the arming.
    public func armKakusan(_ configuration: KakusanHostConfiguration) -> KakusanCommandOutcome {
        KakusanCommandReader.outcome(
            of: armKakusanHost(withCapacity: configuration.capacity, localSeats: configuration.localSeats)
        )
    }

    /// Installs or removes the handler for the session's events.
    ///
    /// - Parameter handler: Receives each event on the main actor; `nil` removes the handler.
    public func receiveKakusanEvents(_ handler: (@MainActor (KakusanStreamEvent) -> Void)?) {
        guard let handler else {
            kakusanEventHandler = nil
            return
        }
        kakusanEventHandler = { event, text in
            let read = KakusanEventReader.event(of: event.pointee, text: text)
            MainActor.assumeIsolated {
                handler(read)
            }
        }
    }

    /// Creates an invitation.
    ///
    /// - Returns: The new guest, or why the session refused.
    public func makeKakusanInvitation() -> Result<KakusanGuestID, KakusanError> {
        KakusanCommandReader.guest(of: inviteKakusanGuest())
    }

    /// Imports a guest's reply.
    ///
    /// - Parameter text: The reply block's text.
    /// - Returns: The guest the reply belongs to, or why the session refused it.
    public func acceptKakusanReply(_ text: String) -> Result<KakusanGuestID, KakusanError> {
        KakusanCommandReader.guest(of: importKakusanReply(text))
    }

    /// Remembers a verified peer's device.
    ///
    /// - Parameters:
    ///   - identity: The device's public key, as raw bytes.
    ///   - nickname: The name to save it under.
    ///   - replacing: Whether to take the name from another device.
    /// - Returns: The saved device or the device already holding the name, or why it was not saved.
    public func rememberKakusan(_ identity: Data, _ nickname: String,
                                _ replacing: Bool) -> Result<KakusanRememberResult, KakusanError> {
        KakusanCommandReader.remembered(
            of: kakusanRememberDevice(identity, nickname: nickname, replace: replacing)
        )
    }

    /// Sends a command to the session.
    ///
    /// - Parameter command: The command.
    /// - Returns: Whether the session accepted it.
    public func sendKakusan(_ command: KakusanHostCommand) -> KakusanCommandOutcome {
        switch command {
        case let .enterCode(guest, code):
            KakusanCommandReader.outcome(of: kakusanEnterCode(code.digits, guestID: guest.bytes))
        case let .giveSeat(guest, preferred, controllerType, accountID):
            KakusanCommandReader.outcome(
                of: kakusanApproveGuestID(
                    guest.bytes,
                    pad: Int(preferred ?? 0),
                    controllerType: Int(controllerType),
                    accountID: accountID
                )
            )
        case .remove(let guest):
            KakusanCommandReader.outcome(of: kakusanRemoveGuestID(guest.bytes))
        case .setLocalSeats(let count):
            KakusanCommandReader.outcome(of: kakusanSetLocalSeats(count))
        case .setCapacity(let count):
            KakusanCommandReader.outcome(of: kakusanSetCapacity(count))
        case .setTuning(let tuning):
            KakusanCommandReader.outcome(
                of: kakusanSetMediaTuning(
                    KakusanMediaTuning.Field.allCases.map { NSNumber(value: tuning[$0]) }
                )
            )
        }
    }
}

extension CNLiveVideoPlayer: KakusanGuestPlayer {
    /// Enters the code the host reads out.
    ///
    /// - Parameter code: The code's digits.
    /// - Returns: Whether the session accepted it.
    public func enterKakusanHostCode(_ code: String) -> KakusanCommandOutcome {
        KakusanCommandReader.outcome(of: kakusanGuestEnterCode(code))
    }
}
