import ChiakiModels
import Foundation
import Testing

private let first = UUID()
private let second = UUID()

@Test func microphoneConnectsAfterPermissionAndTogglesMute() {
    var machine = MicrophoneMachine()
    #expect(machine.handle(.toggle(first)) == [.requestPermission(first)])
    #expect(machine.phase == .requestingPermission(first))
    #expect(machine.handle(.permission(first, granted: true)) == [.startCapture(first)])
    #expect(machine.phase == .connecting(first))
    #expect(machine.handle(.connected(first)).isEmpty)
    #expect(machine.phase == .live(first, muted: false))
    #expect(machine.transmitting)
    #expect(machine.handle(.toggle(second)) == [.setMuted(first, true)])
    #expect(machine.phase == .live(first, muted: true))
    #expect(!machine.transmitting)
    #expect(machine.handle(.toggle(second)) == [.setMuted(first, false)])
    #expect(machine.phase == .live(first, muted: false))
}

@Test func microphoneIgnoresPermissionForACancelledRequest() {
    var machine = MicrophoneMachine()
    _ = machine.handle(.toggle(first))
    #expect(machine.handle(.toggle(second)).isEmpty)
    #expect(machine.phase == .off)
    #expect(machine.handle(.permission(first, granted: true)).isEmpty)
    #expect(machine.phase == .off)
    _ = machine.handle(.toggle(second))
    #expect(machine.handle(.permission(first, granted: false)).isEmpty)
    #expect(machine.phase == .requestingPermission(second))
    #expect(machine.handle(.permission(second, granted: false)).isEmpty)
    #expect(machine.phase == .denied)
    #expect(machine.handle(.toggle(first)) == [.requestPermission(first)])
}

@Test func microphoneIgnoresCaptureEventsFromAnAbandonedConnection() {
    var machine = MicrophoneMachine()
    _ = machine.handle(.toggle(first))
    _ = machine.handle(.permission(first, granted: true))
    #expect(machine.handle(.toggle(second)) == [.stopCapture(first)])
    #expect(machine.phase == .off)
    #expect(machine.handle(.connected(first)).isEmpty)
    #expect(machine.handle(.failed(first, .consoleRejected)).isEmpty)
    #expect(machine.phase == .off)
}

@Test func microphoneFailureStopsCaptureAndAllowsARetry() {
    var machine = MicrophoneMachine(phase: .live(first, muted: false))
    #expect(machine.handle(.failed(second, .consoleRejected)).isEmpty)
    #expect(machine.handle(.failed(first, .interrupted("gone"))) == [.stopCapture(first)])
    #expect(machine.phase == .failed(.interrupted("gone")))
    #expect(machine.handle(.toggle(second)) == [.requestPermission(second)])
}

@Test func microphoneOnlyFailsForTheMuteStateItStillShows() {
    var machine = MicrophoneMachine(phase: .live(first, muted: true))
    #expect(machine.handle(.muteApplied(first, muted: false, failure: .consoleRejected)).isEmpty)
    #expect(machine.handle(.muteApplied(first, muted: true, failure: nil)).isEmpty)
    #expect(machine.phase == .live(first, muted: true))
    #expect(machine
        .handle(.muteApplied(first, muted: true, failure: .consoleRejected)) == [.stopCapture(first)])
    #expect(machine.phase == .failed(.consoleRejected))
}

@Test func microphoneResetStopsAnyCapture() {
    var live = MicrophoneMachine(phase: .live(first, muted: true))
    #expect(live.handle(.reset) == [.stopCapture(first)])
    #expect(live.phase == .off)
    var asking = MicrophoneMachine(phase: .requestingPermission(first))
    #expect(asking.handle(.reset).isEmpty)
    #expect(asking.phase == .off)
    var failed = MicrophoneMachine(phase: .failed(.streamUnavailable))
    #expect(failed.handle(.reset).isEmpty)
    #expect(failed.phase == .off)
}
