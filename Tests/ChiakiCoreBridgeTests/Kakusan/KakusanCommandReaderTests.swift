import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing

private typealias Command = chiaki_bridge.KakusanCommandOutcome

private func guestEnd(
    _ status: libchiaking.kakusan.VisitOutcome.Status,
    _ configure: (inout chiaki_bridge.GuestEndFacts) -> Void = { _ in
    }
) -> KakusanGuestEnd {
    var end = chiaki_bridge.GuestEndFacts()
    end.status = status
    configure(&end)
    return KakusanGuestEnd(chiaki_bridge.GuestOutcome.ended(end))
}

@Test func commandsWithoutARefusalAreAccepted() {
    #expect(KakusanCommandReader.outcome(of: Command.accepted(chiaki_bridge.Bytes())) == .accepted)
    #expect(KakusanCommandReader.outcome(of: Command.declined(.unreachable)) == .rejected(.noPath))
    #expect(KakusanCommandReader.outcome(of: Command.declined(.not_sharing)) == .rejected(.sourceEnded))
    #expect(KakusanCommandReader.outcome(of: Command.refused(.not_armed)) == .rejected(.internal))
    #expect(KakusanCommandReader.outcome(of: Command.refused(.core_closed)) == .rejected(.cryptoUnavailable))
}

@Test func streamRefusalsTreatABadArgumentAsInternal() {
    #expect(KakusanCommandReader
        .error(of: libchiaking.kakusan.Refusal.Kind.invalid_argument) == .internal)
    #expect(KakusanCommandReader
        .error(of: libchiaking.kakusan.Refusal.Kind.invalid_text) == .invalidBlock)
    #expect(KakusanCommandReader.error(of: libchiaking.kakusan.Refusal.Kind.busy) == .sourceJoinFailed)
    #expect(KakusanCommandReader
        .error(of: libchiaking.kakusan.Refusal.Kind.cannot_be_shared) == .sourceFormat)
}

@Test func guestIdentifiersNeedAnAcceptedAnswerAndSixteenBytes() {
    let bytes = Data(repeating: 6, count: KakusanGuestID.length)
    #expect(KakusanCommandReader.guest(of: Command.accepted(chiaki_bridge.Bytes(bytes)))
        == .success(KakusanFixture.guest(6)))
    #expect(KakusanCommandReader.guest(of: Command.accepted(chiaki_bridge.Bytes())) == .failure(.internal))
    #expect(KakusanCommandReader.guest(of: Command.accepted(chiaki_bridge.Bytes(bytes.prefix(8))))
        == .failure(.internal))
    #expect(KakusanCommandReader.guest(of: Command.declined(.not_sharing)) == .failure(.sourceEnded))
    #expect(KakusanCommandReader.guest(of: Command.declined(.invalid_text)) == .failure(.invalidBlock))
}

@Test func guestRunsEndAsTheCoreReports() {
    #expect(guestEnd(.completed) == .finished)
    #expect(guestEnd(.cancelled) == .cancelled)
    #expect(guestEnd(.media_failed) == .failed(.codec))
    #expect(guestEnd(.media_failed) {
        $0.media_failure.value = .decoder_submission
    } == .failed(.codec))
    #expect(guestEnd(.visit_failed) {
        $0.refused.value = .unreachable
    } == .failed(.noPath))
    #expect(guestEnd(.visit_failed) {
        $0.refused.value = .expired
    } == .failed(.expired))
    #expect(KakusanGuestEnd(chiaki_bridge.GuestOutcome.declined(.invalid_argument)) == .failed(.internal))
    #expect(KakusanGuestEnd(chiaki_bridge.GuestOutcome.refused(.core_closed)) == .failed(.cryptoUnavailable))
    #expect(KakusanGuestEnd(chiaki_bridge.GuestOutcome.refused(.no_decoder)) == .failed(.internal))
    #expect(guestEnd(.visit_failed) == .failed(.internal))
}

@Test func onlyFailedGuestRunsThrow() throws {
    try KakusanGuestEnd.finished.resolve()
    try KakusanGuestEnd.cancelled.resolve()
    #expect(throws: KakusanError.noPath) {
        try KakusanGuestEnd(chiaki_bridge.GuestOutcome.declined(.unreachable)).resolve()
    }
}
