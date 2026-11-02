import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing

private func native(
    _ kind: KakusanStreamEvent.Kind,
    _ configure: (inout KakusanStreamEvent) -> Void = { _ in
    }
) -> KakusanStreamEvent {
    var event = KakusanStreamEvent(kind: kind)
    configure(&event)
    return event
}

private func hostEvent(
    _ kind: KakusanStreamEvent.Kind,
    guest: UInt8 = 1,
    _ configure: (inout KakusanStreamEvent) -> Void = { _ in
    }
) -> KakusanHostEvent? {
    native(kind) {
        $0.guestID = Data(repeating: guest, count: KakusanGuestID.length)
        configure(&$0)
    }.hostEvent
}

private func core(
    _ kind: chiaki_bridge.KakusanEvent.Kind,
    _ configure: (inout chiaki_bridge.KakusanEvent) -> Void = { _ in
    }
) -> chiaki_bridge.KakusanEvent {
    var event = chiaki_bridge.KakusanEvent()
    event.kind = kind
    configure(&event)
    return event
}

private let expiry: UInt64 = 1_800_000_600

@Test func coreProgressReadsAsTheSessionState() {
    let table: [(libchiaking.kakusan.Progress, KakusanSessionState)] = [
        (.waiting, .waiting),
        (.connecting, .connecting),
        (.verifying, .verifying),
        (.waiting_for_seat, .admitting),
        (.getting_ready, .readyWait),
        (.playing, .active),
        (.leaving, .closing),
        (.gone, .closed)
    ]
    for (progress, state) in table {
        let event = KakusanEventReader.event(of: core(.state_changed) {
            $0.progress.value = progress
        }, text: nil)
        #expect(event.state == state)
    }
    #expect(KakusanEventReader.event(of: core(.state_changed), text: nil).state == nil)
}

@Test func coreEndReasonsReadAsTheModelReasons() {
    let table: [(libchiaking.kakusan.EndReason.Kind, KakusanReason)] = [
        (.left, .user),
        (.no_seat, .capacity),
        (.session_ended, .source),
        (.timed_out, .timeout),
        (.connection_lost, .network),
        (.protocol, .protocol)
    ]
    for (ended, reason) in table {
        let event = KakusanEventReader.event(of: core(.state_changed) {
            $0.ended.value = ended
        }, text: nil)
        #expect(event.reason == reason)
    }
}

@Test func coreRefusalsInEventsReadAsErrors() {
    let refused = KakusanEventReader.event(of: core(.sharing_failed) {
        $0.refused.value = .not_sharing
    }, text: nil)
    #expect(refused.hostEvent == .unavailable(.sourceEnded))
    let argument = KakusanEventReader.event(of: core(.unavailable) {
        $0.refused.value = .invalid_argument
    }, text: nil)
    #expect(argument.error == .internal)
    let closed = KakusanEventReader.event(of: core(.unavailable) {
        $0.refusal.value = .core_closed
    }, text: nil)
    #expect(closed.hostEvent == .unavailable(.cryptoUnavailable))
    let unarmed = KakusanEventReader.event(of: core(.unavailable) {
        $0.refusal.value = .not_armed
    }, text: nil)
    #expect(unarmed.hostEvent == .unavailable(.internal))
}

@Test func coreCodeTextBecomesTheCodeAndOtherTextStaysText() {
    let code = KakusanEventReader.event(of: core(.code_ready), text: "0420")
    #expect(code.code == "0420")
    #expect(code.text == nil)
    #expect(code.guestEvent == .codeReady(KakusanFixture.code("0420")))
    let reply = KakusanEventReader.event(of: core(.reply_ready), text: KakusanFixture.reply.text)
    #expect(reply.text == KakusanFixture.reply.text)
    #expect(reply.code == nil)
    #expect(reply.guestEvent == .replyReady(KakusanFixture.reply))
}

@Test func coreGrantsPadsAndSeatsCarryAcross() {
    let changed = KakusanEventReader.event(of: core(.state_changed) {
        $0.guest = chiaki_bridge.Bytes(Data(repeating: 2, count: KakusanGuestID.length))
        $0.progress.value = .playing
        var grant = libchiaking.kakusan.SeatGrant()
        grant.number = 3
        grant.generation = 7
        $0.grant.value = grant
        $0.pad.value = 2
        $0.by_peer = true
    }, text: nil)
    #expect(changed.hostEvent == .stateChanged(
        KakusanFixture.guest(2),
        KakusanStateChange(state: .active, byPeer: true, seat: 3, generation: 7, consoleSeat: 2)
    ))
    let seats = KakusanEventReader.event(of: core(.seats_changed) {
        var summary = libchiaking.kakusan.SeatSummary()
        summary.capacity = 4
        summary.local_seats = 2
        summary.remote_seats = 1
        summary.reserved_seats = 1
        $0.seats.value = summary
    }, text: nil)
    #expect(seats.hostEvent == .seatsChanged(KakusanSeatSnapshot(
        capacity: 4,
        local: 2,
        remote: 1,
        reserved: 1
    )))
    let empty = KakusanEventReader.event(of: core(.stream_stopped), text: nil)
    #expect(empty.guestID == nil)
    #expect(empty.identity == nil)
    #expect(empty.guestEvent == .streamStopped)
}

@Test func hostInvitationReadyNeedsAGuestABlockAndAnExpiry() {
    let valid = hostEvent(.invitationReady) {
        $0.text = KakusanFixture.invitation.text
        $0.expiresAt = expiry
    }
    #expect(valid == .invitationReady(
        KakusanFixture.guest(1), KakusanFixture.invitation,
        expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
    ))
    let missingGuest = native(.invitationReady) {
        $0.text = KakusanFixture.invitation.text
        $0.expiresAt = expiry
    }
    #expect(missingGuest.hostEvent == nil)
    let shortGuest = native(.invitationReady) {
        $0.guestID = Data(repeating: 1, count: 15)
        $0.text = KakusanFixture.invitation.text
        $0.expiresAt = expiry
    }
    #expect(shortGuest.hostEvent == nil)
    #expect(hostEvent(.invitationReady) {
        $0.text = "not a block"
        $0.expiresAt = expiry
    } == nil)
    #expect(hostEvent(.invitationReady) {
        $0.text = KakusanFixture.invitation.text
    } == nil)
}

@Test func hostReplyBoundNeedsAFullKeyAndFingerprint() {
    let key = KakusanFixture.key(4)
    let print = KakusanFixture.fingerprint(4)
    #expect(hostEvent(.replyBound) {
        $0.identity = key.bytes
        $0.fingerprint = print.bytes
    } == .replyBound(KakusanFixture.guest(1), key, print))
    #expect(hostEvent(.replyBound) {
        $0.identity = key.bytes.prefix(31)
        $0.fingerprint = print.bytes
    } == nil)
    #expect(hostEvent(.replyBound) {
        $0.identity = key.bytes
    } == nil)
}

@Test func hostCodeReadyNeedsFourDigits() {
    #expect(hostEvent(.codeReady) {
        $0.code = "0420"
    } == .codeReady(KakusanFixture.guest(1), KakusanFixture.code("0420")))
    for code in [nil, "12a4", "12345", ""] {
        #expect(hostEvent(.codeReady) {
            $0.code = code
        } == nil)
    }
}

@Test func hostStateChangesCarryErrorReasonPeerAndSeat() {
    let closed = hostEvent(.stateChanged, guest: 2) {
        $0.state = .closed
        $0.error = .noPath
        $0.reason = .network
        $0.byPeer = true
        $0.seat = 2
    }
    #expect(closed == .stateChanged(
        KakusanFixture.guest(2),
        KakusanStateChange(state: .closed, error: .noPath, reason: .network, byPeer: true, seat: 2)
    ))
    let plain = hostEvent(.stateChanged) {
        $0.state = .verifying
        $0.seat = 0
    }
    #expect(plain == .stateChanged(KakusanFixture.guest(1), KakusanStateChange(state: .verifying)))
}

@Test func hostStateChangesCarryTheGrantAndConsoleSeatTheCoreReports() {
    let playing = hostEvent(.stateChanged) {
        $0.state = .active
        $0.seat = 3
        $0.generation = 7
        $0.pad = 2
    }
    let expected = KakusanStateChange(state: .active, seat: 3, generation: 7, consoleSeat: 2)
    #expect(playing == .stateChanged(KakusanFixture.guest(1), expected))
    #expect(expected.grant == KakusanSeatGrant(seat: 3, generation: 7))
    #expect(KakusanStateChange(state: .active, seat: 3).grant == nil)
    #expect(KakusanStateChange(state: .active, generation: 7).grant == nil)
    for pad in [0, 4, -1] {
        let outside = hostEvent(.stateChanged) {
            $0.state = .active
            $0.seat = 3
            $0.generation = 7
            $0.pad = pad
        }
        #expect(outside == .stateChanged(
            KakusanFixture.guest(1),
            KakusanStateChange(state: .active, seat: 3, generation: 7)
        ))
    }
}

@Test func hostStateChangesCarryTheSeatTheCoreReserved() {
    let held = hostEvent(.stateChanged) {
        $0.state = .admitting
        $0.seat = 3
        $0.generation = 7
        $0.reservedPad = 2
    }
    let expected = KakusanStateChange(state: .admitting, seat: 3, generation: 7, reservedSeat: 2)
    #expect(held == .stateChanged(KakusanFixture.guest(1), expected))
    #expect(expected.consoleSeat == nil)
    #expect(expected.grant == KakusanSeatGrant(seat: 3, generation: 7))
    for pad in [0, 4, -1] {
        let outside = hostEvent(.stateChanged) {
            $0.state = .admitting
            $0.seat = 3
            $0.generation = 7
            $0.reservedPad = pad
        }
        #expect(outside == .stateChanged(
            KakusanFixture.guest(1),
            KakusanStateChange(state: .admitting, seat: 3, generation: 7)
        ))
    }
}

@Test func hostHearsTheConsoleSeatingAndUnseatingAGuest() {
    #expect(hostEvent(.playerSeated, guest: 2) {
        $0.pad = 3
    } == .consoleSeated(KakusanFixture.guest(2), pad: 3))
    #expect(hostEvent(.playerUnseated, guest: 2) {
        $0.pad = 1
    } == .consoleUnseated(KakusanFixture.guest(2), pad: 1))
    for kind in [KakusanStreamEvent.Kind.playerSeated, .playerUnseated] {
        #expect(hostEvent(kind) == nil)
        #expect(hostEvent(kind) {
            $0.pad = 0
        } == nil)
        #expect(native(kind) {
            $0.pad = 2
        }.hostEvent == nil)
        #expect(native(kind) {
            $0.guestID = Data(repeating: 1, count: KakusanGuestID.length)
            $0.pad = 2
        }.guestEvent == nil)
    }
}

@Test func stateChangesWithoutAStageAreDropped() {
    #expect(hostEvent(.stateChanged) {
        $0.error = .noPath
    } == nil)
    #expect(native(.stateChanged) {
        $0.reason = .user
    }.guestEvent == nil)
}

@Test func hostSeatSnapshotsStayWithinTheConsolePads() {
    #expect(native(.seatsChanged) {
        $0.capacity = 4
        $0.localSeats = 2
        $0.remoteSeats = 1
        $0.reservedSeats = 1
    }.hostEvent == .seatsChanged(KakusanSeatSnapshot(capacity: 4, local: 2, remote: 1, reserved: 1)))
    let malformed = [[0, 1, 0, 0], [5, 1, 0, 0], [4, 1, 5, 0], [4, -1, 0, 0], [4, 1, 0, 9]]
    for counts in malformed {
        #expect(native(.seatsChanged) {
            $0.capacity = counts[0]
            $0.localSeats = counts[1]
            $0.remoteSeats = counts[2]
            $0.reservedSeats = counts[3]
        }.hostEvent == nil)
    }
}

@Test func hostUnavailableAndSharingFailuresBecomeUnavailable() {
    #expect(native(.unavailable) {
        $0.error = .cryptoUnavailable
    }.hostEvent == .unavailable(.cryptoUnavailable))
    #expect(native(.sharingFailed) {
        $0.error = .sourceFormat
    }.hostEvent == .unavailable(.sourceFormat))
    #expect(native(.sharingFailed).hostEvent == .unavailable(.internal))
}

@Test func hostIgnoresGuestOnlyEvents() {
    for kind in [KakusanStreamEvent.Kind.replyReady, .streamReady, .streamStopped, .hostIdentified] {
        #expect(hostEvent(kind) {
            $0.text = KakusanFixture.reply.text
            $0.videoFPS = 60
        } == nil)
    }
}

@Test func guestEventsTranslateWithoutAGuestID() {
    #expect(native(.replyReady) {
        $0.text = KakusanFixture.reply.text
    }.guestEvent == .replyReady(KakusanFixture.reply))
    #expect(native(.codeReady) {
        $0.code = "9876"
    }.guestEvent == .codeReady(KakusanFixture.code("9876")))
    #expect(native(.stateChanged) {
        $0.state = .readyWait
        $0.seat = 3
    }.guestEvent == .stateChanged(KakusanStateChange(state: .readyWait, seat: 3)))
    #expect(native(.stateChanged) {
        $0.state = .closed
        $0.reason = .user
        $0.byPeer = true
    }.guestEvent == .stateChanged(KakusanStateChange(state: .closed, reason: .user, byPeer: true)))
    #expect(native(.streamReady) {
        $0.videoFPS = 60
    }.guestEvent == .streamReady(fps: 60))
    #expect(native(.streamStopped).guestEvent == .streamStopped)
    #expect(native(.streamStopped) {
        $0.guestID = Data(repeating: 3, count: KakusanGuestID.length)
    }.guestEvent == .streamStopped)
}

@Test func guestDropsMalformedAndHostOnlyEvents() {
    #expect(native(.replyReady) {
        $0.text = "RCP1:"
    }.guestEvent == nil)
    #expect(native(.replyReady).guestEvent == nil)
    #expect(native(.codeReady) {
        $0.code = "98x6"
    }.guestEvent == nil)
    #expect(native(.streamReady).guestEvent == nil)
    #expect(native(.streamReady) {
        $0.videoFPS = -30
    }.guestEvent == nil)
    let hostOnly: [KakusanStreamEvent.Kind] = [
        .invitationReady, .replyBound, .streamShared, .sharingEnded, .seatsChanged, .unavailable,
        .sharingFailed
    ]
    for kind in hostOnly {
        #expect(native(kind) {
            $0.guestID = Data(repeating: 1, count: KakusanGuestID.length)
            $0.text = KakusanFixture.invitation.text
            $0.expiresAt = expiry
            $0.seat = 1
            $0.generation = 1
            $0.capacity = 4
            $0.localSeats = 1
            $0.error = .noPath
        }.guestEvent == nil)
    }
}
