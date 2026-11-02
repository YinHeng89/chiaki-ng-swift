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
    func status(on console: CouchConsole) -> (text: String, tone: CouchTone) {
        switch self {
        case .open:
            ("Open", .idle)
        case .choosingAccount:
            ("Choosing an account", .waiting)
        case .joining:
            switch console {
            case .ps4:
                ("Joining", .waiting)
            case .ps5:
                ("Waiting for the PS5", .waiting)
            case .cloud:
                ("Joining", .waiting)
            }
        case .pickingOnConsole:
            ("Choose a user on the TV", .waiting)
        case .passcode:
            ("Entering a passcode", .waiting)
        case .ready:
            ("Ready", .ready)
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
    var explanation: String {
        switch self {
        case .notSent:
            "The join couldn’t be sent to the console."
        case .refused(let status):
            "The console refused the join (status \(status))."
        case .timedOut:
            "The PS5 didn’t answer in time."
        case .passcodeAttempts:
            "Three passcodes weren’t accepted."
        case .accountUnresolvable:
            "This PS5 doesn’t recognise that account."
        }
    }
}

extension CouchNotice {
    /// The notice's headline.
    var title: String {
        switch self {
        case let .joined(pad, player, _):
            if let name = player.remote?.name ?? player.account?.name {
                return "\(name) joined as Player \(Int(pad) + 1)"
            }
            return "Player \(Int(pad) + 1) joined"
        case .joinFailed(let pad, _):
            return "Player \(Int(pad) + 1) couldn’t join"
        case .released(let pad):
            return "Player \(Int(pad) + 1) left"
        case .disconnected(let pad):
            return "Player \(Int(pad) + 1)’s controller disconnected"
        case .left(let pad):
            return "Player \(Int(pad) + 1) left"
        case let .switched(pad, device):
            let target = device.isKeyboard
                ? "the keyboard"
                : device.name
            return "Player \(Int(pad) + 1) switched to \(target)"
        case .remote(let notice):
            return notice.title
        }
    }

    /// More about the notice, if there is more to say.
    var detail: String? {
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
    func accountQuestion(for choice: CouchAccountChoice) -> String {
        switch choice {
        case .pad(let pad):
            return "Who’s playing as Player \(Int(pad) + 1)?"
        case .remote(let guest):
            guard let name = wait(for: guest)?.remote.name else {
                return "Which account is the remote player using?"
            }
            return "Which account is \(name) using?"
        }
    }
}
