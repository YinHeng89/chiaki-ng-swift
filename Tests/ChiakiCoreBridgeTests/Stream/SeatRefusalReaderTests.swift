import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import Testing

private typealias Refusal = libchiaking.play.SeatRefusal

private let seat = libchiaking.controllers.SeatNumber.masked(2)

private let timedOutStatus: UInt8 = 0xff

private let passcodeAttemptsStatus: UInt8 = 0xfe

@Test func joinFailuresNameTheirCause() {
    #expect(SeatRefusalReader.failure(of: Refusal.by_console(seat, timedOutStatus)) == .timedOut)
    #expect(SeatRefusalReader.failure(of: Refusal.by_console(seat, passcodeAttemptsStatus))
        == .passcodeAttempts)
    #expect(SeatRefusalReader
        .failure(of: Refusal.not_sent(seat, .control_failed)) == .notSent(.controlFailed))
    #expect(SeatRefusalReader.failure(of: Refusal.by_console(seat, 2)) == .refused(2))
    #expect(SeatRefusalReader.failure(of: Refusal.account_not_on_console(seat)) == .accountUnresolvable)
    #expect(SeatRefusalReader.failure(of: Refusal.no_free_seat()) == nil)
}

@Test func refusalsNameThePadTheyConcern() {
    #expect(SeatRefusalReader.pad(of: Refusal.account_not_on_console(seat)) == 2)
    #expect(SeatRefusalReader.pad(of: Refusal.no_free_seat()) == nil)
}
