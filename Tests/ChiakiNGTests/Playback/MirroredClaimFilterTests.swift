import CInput
import Testing
@testable import ChiakiNG

private func press(_ instance: UInt32, control: Int32 = 6, value: Int32 = 1, time: UInt64) -> nx_input_event {
    var event = nx_input_event()
    event.instance = instance
    event.kind = ControllerInputEvent.button
    event.control = control
    event.value = value
    event.timestamp_us = time
    return event
}

@Test func aClaimThatRepeatsPlayerOnesPressIsDropped() {
    var filter = MirroredClaimFilter()
    filter.notePlayerOne(press(1, time: 1_000_000))
    filter.hold(press(2, time: 1_004_000))
    #expect(filter.release(now: 1_100_000).isEmpty)
    #expect(filter.release(now: 1_200_000).isEmpty)
    #expect(filter.held.isEmpty)
}

@Test func playerOnesPressArrivingAfterTheClaimStillMarksItACopy() {
    var filter = MirroredClaimFilter()
    filter.hold(press(2, time: 2_000_000))
    filter.notePlayerOne(press(1, time: 2_010_000))
    #expect(filter.release(now: 2_200_000).isEmpty)
}

@Test func aSecondPlayersOwnPressClaimsOnceTheHoldPasses() {
    var filter = MirroredClaimFilter()
    filter.notePlayerOne(press(1, time: 1_000_000))
    filter.notePlayerOne(press(1, control: 0, time: 3_000_000))
    filter.hold(press(2, time: 3_000_000))
    #expect(filter.release(now: 3_100_000).isEmpty)
    #expect(filter.release(now: 3_150_000) == [2])
}

@Test func aReleaseOrADisconnectEndsAHeldClaim() {
    var filter = MirroredClaimFilter()
    filter.notePlayerOne(press(1, value: 0, time: 4_000_000))
    filter.hold(press(2, time: 4_000_000))
    filter.hold(press(2, time: 4_050_000))
    #expect(filter.held.count == 1)
    #expect(filter.release(now: 4_200_000) == [2])
    filter.hold(press(3, time: 5_000_000))
    filter.forget(3)
    #expect(filter.release(now: 6_000_000).isEmpty)
}
