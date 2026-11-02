import ChiakiModels
import Foundation
import Testing

private func shownPad(_ surface: TouchpadSurface = .ps5) -> VirtualTouchpad {
    var pad = VirtualTouchpad(surface: surface)
    pad.toggle()
    return pad
}

@Test func shortcutPinsAndUnpinsTheTouchpad() {
    var pad = VirtualTouchpad()
    pad.toggle()
    #expect(pad.phase == .shown(.idle, .pinned))
    pad.tick(at: 1000)
    #expect(pad.phase == .shown(.idle, .pinned))
    pad.reveal(at: 1000)
    #expect(pad.phase == .shown(.idle, .pinned))
    pad.toggle()
    #expect(pad.phase == .hidden)
}

@Test func firstTouchOnAHiddenTouchpadOnlyRevealsIt() {
    var pad = VirtualTouchpad()
    pad.pointerDown(x: 0.5, y: 0.5, at: 0)
    #expect(pad.phase == .shown(.ignoring, .peeking(until: 5)))
    #expect(pad.output == .none)
    pad.pointerMoved(x: 0.9, y: 0.5, at: 0.1)
    pad.pointerUp(at: 0.2)
    #expect(pad.output == .none)
    #expect(pad.gesture == .idle)
}

@Test func peekingTouchpadHidesAfterFiveIdleSeconds() {
    var pad = VirtualTouchpad()
    pad.reveal(at: 0)
    pad.reveal(at: 3)
    pad.tick(at: 4.9)
    #expect(pad.isShown)
    pad.tick(at: 5)
    #expect(pad.phase == .hidden)
}

@Test func tappingKeepsAPeekingTouchpadUp() {
    var pad = VirtualTouchpad()
    pad.reveal(at: 0)
    pad.pointerDown(x: 0.25, y: 0.5, at: 4)
    pad.pointerUp(at: 4.1)
    pad.tick(at: 4.5)
    pad.tick(at: 9)
    #expect(pad.isShown)
    pad.tick(at: 9.1)
    #expect(pad.phase == .hidden)
}

@Test func peekingTouchpadNeverHidesMidGesture() {
    var pad = VirtualTouchpad()
    pad.reveal(at: 0)
    pad.pointerDown(x: 0.25, y: 0.5, at: 4)
    pad.tick(at: 20)
    #expect(pad.output.clicked)
    #expect(pad.isShown)
    pad.pointerUp(at: 20)
    pad.tick(at: 24.9)
    #expect(pad.isShown)
    pad.tick(at: 25)
    #expect(pad.phase == .hidden)
}

@Test func shortcutPinsAPeekingTouchpadWithoutLosingTheContact() {
    var pad = VirtualTouchpad()
    pad.reveal(at: 0)
    pad.pointerDown(x: 0.25, y: 0.5, at: 1)
    pad.toggle()
    #expect(pad.presence == .pinned)
    #expect(pad.output.touch?.id == 0)
    pad.pointerUp(at: 1.1)
    pad.tick(at: 100)
    #expect(pad.isShown)
}

@Test func tapClicksAtThePointedRegionForOnePulse() {
    var pad = shownPad()
    pad.pointerDown(x: 0.25, y: 0.5, at: 10)
    #expect(pad.output.touch == ControllerTouch(id: 0, x: 480, y: 540))
    #expect(pad.output.clicked == false)
    #expect(pad.region == .left)
    pad.pointerUp(at: 10.1)
    #expect(pad.output.clicked)
    #expect(pad.output.touch?.x == 480)
    pad.tick(at: 10.25)
    #expect(pad.output.clicked)
    pad.tick(at: 10.3)
    #expect(pad.gesture == .idle)
    #expect(pad.output == .none)
}

@Test func rightHalfReportsTheRightRegion() {
    var pad = shownPad()
    pad.pointerDown(x: 0.9, y: 0.1, at: 0)
    #expect(pad.region == .right)
}

@Test func dragPastSlopFollowsThePointerWithoutClicking() {
    var pad = shownPad()
    pad.pointerDown(x: 0.1, y: 0.5, at: 0)
    pad.pointerMoved(x: 0.11, y: 0.5, at: 0.05)
    guard case .pending = pad.gesture else {
        Issue.record("small movement left the pending state")
        return
    }
    pad.pointerMoved(x: 0.6, y: 0.5, at: 0.1)
    #expect(pad.gesture == .dragging(ControllerTouch(id: 0, x: 1151, y: 540)))
    pad.tick(at: 2)
    #expect(pad.output.clicked == false)
    #expect(pad.region == .right)
    pad.pointerUp(at: 2.1)
    #expect(pad.gesture == .idle)
}

@Test func longPressHoldsTheClickUntilRelease() {
    var pad = shownPad()
    pad.pointerDown(x: 0.5, y: 0.5, at: 0)
    pad.tick(at: 0.39)
    #expect(pad.output.clicked == false)
    pad.tick(at: 0.4)
    #expect(pad.output.clicked)
    pad.tick(at: 5)
    #expect(pad.output.clicked)
    pad.pointerUp(at: 5)
    #expect(pad.output == .none)
}

@Test func longDragKeepsTheClickWhileMoving() {
    var pad = shownPad()
    pad.pointerDown(x: 0.2, y: 0.2, at: 0)
    pad.tick(at: 0.5)
    pad.pointerMoved(x: 0.8, y: 0.8, at: 0.6)
    #expect(pad.gesture == .holdDragging(ControllerTouch(id: 0, x: 1535, y: 863)))
    #expect(pad.output.clicked)
    pad.pointerUp(at: 1)
    #expect(pad.gesture == .idle)
}

@Test func lateMovementAfterTheLongPressThresholdStillHolds() {
    var pad = shownPad()
    pad.pointerDown(x: 0.2, y: 0.2, at: 0)
    pad.pointerMoved(x: 0.8, y: 0.2, at: 0.5)
    guard case .holdDragging = pad.gesture else {
        Issue.record("expected a long drag, got \(String(describing: pad.gesture))")
        return
    }
}

@Test func eachContactGetsAFreshWrappingTouchID() {
    var pad = shownPad()
    var ids: [UInt8] = []
    for index in 0..<130 {
        let time = Double(index)
        pad.pointerDown(x: 0.5, y: 0.5, at: time)
        ids.append(pad.output.touch?.id ?? 255)
        pad.pointerMoved(x: 0.9, y: 0.5, at: time + 0.01)
        pad.pointerUp(at: time + 0.02)
    }
    #expect(ids[0] == 0)
    #expect(ids[127] == 127)
    #expect(ids[128] == 0)
    #expect(ids.allSatisfy { $0 <= 0x7f })
}

@Test func pressingDuringAClickPulseStartsANewContact() {
    var pad = shownPad()
    pad.pointerDown(x: 0.3, y: 0.5, at: 0)
    pad.pointerUp(at: 0.05)
    pad.pointerDown(x: 0.7, y: 0.5, at: 0.06)
    #expect(pad.output.clicked == false)
    #expect(pad.output.touch?.id == 1)
    #expect(pad.region == .right)
    #expect(pad.describe(from: .clicking(ControllerTouch(id: 0, x: 575, y: 540), until: 0.25))
        == "contact 0 tap click released and lifted at x=575 y=540 (left half); "
        + "contact 1 down at x=1343 y=540 (right half)")
}

@Test func hidingOrCancellingLiftsTheContact() {
    var pad = shownPad()
    pad.pointerDown(x: 0.5, y: 0.5, at: 0)
    pad.tick(at: 1)
    pad.cancel()
    #expect(pad.gesture == .idle)
    pad.pointerDown(x: 0.5, y: 0.5, at: 2)
    pad.hide()
    #expect(pad.output == .none)
    pad.cancel()
    #expect(pad.phase == .hidden)
}

@Test func ps4SurfaceUsesItsShorterHeightAndClampsOutside() {
    var pad = shownPad(.ps4)
    pad.pointerDown(x: 1.5, y: -0.2, at: 0)
    #expect(pad.output.touch == ControllerTouch(id: 0, x: 1920, y: 0))
    pad.pointerMoved(x: 0.5, y: 2, at: 0.1)
    #expect(pad.output.touch?.y == 942)
}

@Test func positionStaysFrozenUntilTheContactBecomesADrag() {
    var pad = shownPad()
    pad.pointerDown(x: 0.25, y: 0.5, at: 0)
    pad.pointerMoved(x: 0.26, y: 0.51, at: 0.05)
    #expect(pad.output.touch == ControllerTouch(id: 0, x: 480, y: 540))
    pad.tick(at: 0.5)
    pad.pointerMoved(x: 0.255, y: 0.505, at: 0.6)
    #expect(pad.output.touch == ControllerTouch(id: 0, x: 480, y: 540))
    #expect(pad.output.clicked)
}

@Test func gestureStepsDescribeWhereEachHappened() {
    var pad = VirtualTouchpad()
    var lines: [String] = []
    func step(_ change: (inout VirtualTouchpad) -> Void) {
        let previous = pad.gesture
        change(&pad)
        if let line = pad.describe(from: previous) {
            lines.append(line)
        }
    }
    step { $0.toggle() }
    step { $0.pointerDown(x: 0.25, y: 0.5, at: 0) }
    step { $0.pointerUp(at: 0.1) }
    step { $0.tick(at: 0.2) }
    step { $0.tick(at: 0.35) }
    step { $0.pointerDown(x: 0.75, y: 0.5, at: 1) }
    step { $0.pointerMoved(x: 0.9, y: 0.5, at: 1.1) }
    step { $0.pointerUp(at: 1.2) }
    step { $0.pointerDown(x: 0.1, y: 0.1, at: 2) }
    step { $0.tick(at: 2.5) }
    step { $0.pointerMoved(x: 0.6, y: 0.1, at: 2.6) }
    step { $0.pointerUp(at: 2.7) }
    step { $0.tick(at: 2.8) }
    step { $0.toggle() }
    #expect(lines == [
        "shown by the shortcut",
        "contact 0 down at x=480 y=540 (left half)",
        "contact 0 tap, click at x=480 y=540 (left half)",
        "contact 0 tap click released and lifted at x=480 y=540 (left half)",
        "contact 1 down at x=1439 y=540 (right half)",
        "contact 1 drag started, now at x=1727 y=540 (right half)",
        "contact 1 drag ended at x=1727 y=540 (right half)",
        "contact 2 down at x=192 y=108 (left half)",
        "contact 2 long press, click held at x=192 y=108 (left half)",
        "contact 2 long drag started, click held, now at x=1151 y=108 (right half)",
        "contact 2 click released and lifted at x=1151 y=108 (right half)",
        "hidden"
    ])
}
