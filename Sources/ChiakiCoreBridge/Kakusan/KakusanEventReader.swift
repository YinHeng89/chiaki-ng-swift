import ChiakiBridge
import ChiakiModels
import Foundation

/// Reads the Kakusan events a running stream reports into `KakusanStreamEvent`.
public enum KakusanEventReader {
    /// The model event of an event a stream reported.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - text: The secret text the stream lent with it: the invitation or reply for those events, the
    ///     verification code for a code event.
    /// - Returns: The model event.
    public static func event(of event: chiaki_bridge.KakusanEvent,
                             text: String?) -> KakusanStreamEvent {
        var read = KakusanStreamEvent(kind: kind(of: event.kind))
        if read.kind == .codeReady {
            read.code = text
        } else {
            read.text = text
        }
        read.guestID = Data(nonEmpty: event.guest)
        read.expiresAt = event.expires_at
        read.identity = Data(nonEmpty: event.identity)
        read.fingerprint = Data(nonEmpty: event.fingerprint)
        read.state = event.progress.value.map(state(of:))
        read.error = error(of: event)
        read.reason = event.ended.value.map(reason(of:))
        read.byPeer = event.by_peer
        if let grant = event.grant.value {
            read.seat = Int(grant.number)
            read.generation = grant.generation
        }
        read.pad = event.pad.value.map { Int($0) }
        read.reservedPad = event.reserved_pad.value.map { Int($0) }
        if let seats = event.seats.value {
            read.capacity = Int(seats.capacity)
            read.localSeats = Int(seats.local_seats)
            read.remoteSeats = Int(seats.remote_seats)
            read.reservedSeats = Int(seats.reserved_seats)
        }
        read.videoFPS = Int(event.video_fps)
        return read
    }

    private static func error(of event: chiaki_bridge.KakusanEvent) -> KakusanError? {
        if let refused = event.refused.value {
            return KakusanCommandReader.error(of: refused)
        }
        return event.refusal.value.map(KakusanCommandReader.error(of:))
    }

    private static func kind(of kind: chiaki_bridge.KakusanEvent.Kind) -> KakusanStreamEvent.Kind {
        switch kind {
        case .invitation_ready:
            .invitationReady
        case .reply_bound:
            .replyBound
        case .reply_ready:
            .replyReady
        case .code_ready:
            .codeReady
        case .state_changed:
            .stateChanged
        case .stream_shared:
            .streamShared
        case .sharing_ended:
            .sharingEnded
        case .player_seated:
            .playerSeated
        case .player_unseated:
            .playerUnseated
        case .seats_changed:
            .seatsChanged
        case .stream_stopped:
            .streamStopped
        case .stream_ready:
            .streamReady
        case .host_identified:
            .hostIdentified
        case .unavailable:
            .unavailable
        case .sharing_failed:
            .sharingFailed
        }
    }

    private static func state(of progress: libchiaking.kakusan.Progress) -> KakusanSessionState {
        switch progress {
        case .waiting:
            .waiting
        case .connecting:
            .connecting
        case .verifying:
            .verifying
        case .waiting_for_seat:
            .admitting
        case .getting_ready:
            .readyWait
        case .playing:
            .active
        case .leaving:
            .closing
        case .gone:
            .closed
        }
    }

    private static func reason(of ended: libchiaking.kakusan.EndReason.Kind) -> KakusanReason {
        switch ended {
        case .left:
            .user
        case .no_seat:
            .capacity
        case .session_ended:
            .source
        case .timed_out:
            .timeout
        case .connection_lost:
            .network
        case .protocol:
            .protocol
        }
    }
}
