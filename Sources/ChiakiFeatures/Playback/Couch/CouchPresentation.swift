import ChiakiModels
import SwiftUI

/// The colour a seat status or notice is drawn in.
enum CouchTone {
    /// Ready, waiting, failed or idle.
    case ready, waiting, failed, idle

    /// The colour for the tone.
    var color: Color {
        switch self {
        case .ready:
            Color(red: 0.56, green: 0.88, blue: 0.66)
        case .waiting:
            Color(red: 0.96, green: 0.77, blue: 0.42)
        case .failed:
            Color(red: 1.0, green: 0.69, blue: 0.67)
        case .idle:
            .secondary
        }
    }
}

extension CouchSeat {
    /// The status text and tone shown for the seat.
    ///
    /// - Parameter console: What the stream plays from, which changes how a join is described.
    func status(on console: CouchConsole) -> (text: LocalizedStringResource, tone: CouchTone) {
        switch self {
        case .open:
            (.playbackCouchStatusOpen, .idle)
        case .choosingAccount:
            (.playbackCouchStatusChoosingAccount, .waiting)
        case .joining:
            switch console {
            case .ps4:
                (.playbackCouchStatusJoining, .waiting)
            case .ps5:
                (.playbackCouchStatusWaitingForConsole, .waiting)
            case .cloud:
                (.playbackCouchStatusJoining, .waiting)
            }
        case .pickingOnConsole:
            (.playbackCouchStatusChooseUserOnTv, .waiting)
        case .passcode:
            (.playbackCouchStatusEnteringPasscode, .waiting)
        case .ready:
            (.playbackCouchStatusReady, .ready)
        }
    }

    /// Whether the seat waits for the console to answer.
    var waitingForConsole: Bool {
        switch self {
        case .joining, .pickingOnConsole, .passcode:
            true
        case .open, .choosingAccount, .ready:
            false
        }
    }
}

extension CouchReducer.State {
    /// A pad player's light colour, ready to draw.
    func lightBar(for pad: UInt8) -> Color? {
        CouchLight.color(lightColor(for: pad))
    }
}

/// Turns light colours into colours to draw.
enum CouchLight {
    /// The colour for a 0xRRGGBB value, or `nil` when there is none.
    static func color(_ rgb: UInt32?) -> Color? {
        guard let rgb else {
            return nil
        }
        return Color(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }
}

extension CouchFailure {
    /// Why the join failed, as a sentence for the player.
    var explanation: LocalizedStringResource {
        switch self {
        case .notSent:
            .playbackCouchFailureNotSent
        case .refused(let status):
            .playbackCouchFailureRefused(status: String(status))
        case .timedOut:
            .playbackCouchFailureTimedOut
        case .passcodeAttempts:
            .playbackCouchFailurePasscodeAttempts
        case .accountUnresolvable:
            .playbackCouchFailureAccountUnresolvable
        }
    }
}

extension CouchNotice {
    /// The notice's headline.
    var title: LocalizedStringResource {
        switch self {
        case let .joined(pad, player, _):
            if let name = player.remote?.name ?? player.account?.name {
                return .playbackCouchNoticeJoinedNamed(name: name, number: Int(pad) + 1)
            }
            return .playbackCouchNoticeJoined(number: Int(pad) + 1)
        case .joinFailed(let pad, _):
            return .playbackCouchNoticeJoinFailed(number: Int(pad) + 1)
        case .released(let pad):
            return .playbackCouchNoticeLeft(number: Int(pad) + 1)
        case .disconnected(let pad):
            return .playbackCouchNoticeDisconnected(number: Int(pad) + 1)
        case .left(let pad):
            return .playbackCouchNoticeLeft(number: Int(pad) + 1)
        case let .switched(pad, device):
            guard !device.isKeyboard else {
                return .playbackCouchNoticeSwitchedToKeyboard(number: Int(pad) + 1)
            }
            return .playbackCouchNoticeSwitched(number: Int(pad) + 1, device: device.name)
        case .remote(let notice):
            return notice.title
        }
    }

    /// More about the notice, if there is more to say.
    var detail: LocalizedStringResource? {
        switch self {
        case let .joinFailed(_, failure):
            failure.explanation
        case .remote(let notice):
            notice.detail
        case .joined, .released, .disconnected, .left, .switched:
            nil
        }
    }

    /// The colour the notice is marked with.
    var tone: CouchTone {
        switch self {
        case .joined, .switched:
            .ready
        case .joinFailed:
            .waiting
        case .released, .disconnected, .left:
            .idle
        case .remote(let notice):
            notice.tone
        }
    }
}

extension CouchSeats {
    /// The question asked while choosing the account for a seat or a remote guest.
    func accountQuestion(for choice: CouchAccountChoice) -> LocalizedStringResource {
        switch choice {
        case .pad(let pad):
            return .playbackCouchQuestionPad(number: Int(pad) + 1)
        case .remote(let guest):
            guard let name = wait(for: guest)?.remote.name else {
                return .playbackCouchQuestionRemote
            }
            return .playbackCouchQuestionRemoteNamed(name: name)
        }
    }
}
