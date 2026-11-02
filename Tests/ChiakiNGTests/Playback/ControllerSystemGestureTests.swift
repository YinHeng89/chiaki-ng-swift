import Foundation
import GameController
import Testing
@testable import ChiakiNG

@Test func gestureHoldsCaptureOnTheFirstHoldAndReleaseAfterTheLast() {
    var holds = ControllerSystemGestureHolds()
    let first = UUID(), second = UUID()
    #expect(holds.acquire(first) == .beginCapture)
    #expect(holds.acquire(second) == .none)
    #expect(holds.release(first) == .none)
    #expect(holds.state == .holding([second]))
    #expect(holds.release(second) == .endCapture)
    #expect(holds.state == .idle)
}

@Test func releasingAnUnknownOrRepeatedHoldDoesNothing() {
    var holds = ControllerSystemGestureHolds()
    let hold = UUID()
    #expect(holds.release(hold) == .none)
    #expect(holds.acquire(hold) == .beginCapture)
    #expect(holds.release(hold) == .endCapture)
    #expect(holds.release(hold) == .none)
    #expect(holds.state == .idle)
}

@MainActor @Test func droppingTheLastHoldRestoresBackgroundMonitoring() {
    let original = GCController.shouldMonitorBackgroundEvents
    defer {
        GCController.shouldMonitorBackgroundEvents = original
    }
    let owner = ControllerSystemGestureOwner()
    GCController.shouldMonitorBackgroundEvents = false
    var first: ControllerSystemGestureHold? = owner.acquire()
    var second: ControllerSystemGestureHold? = owner.acquire()
    #expect(GCController.shouldMonitorBackgroundEvents)
    first = nil
    #expect(GCController.shouldMonitorBackgroundEvents)
    second = nil
    #expect(!GCController.shouldMonitorBackgroundEvents)
    #expect(first == nil && second == nil)
}
