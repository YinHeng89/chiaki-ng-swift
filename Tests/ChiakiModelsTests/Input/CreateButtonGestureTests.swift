import Testing
import ChiakiModels

@Test func aShortPressIsASingleTapOnceTheSecondTapWindowPasses() {
    var gesture = CreateButtonGesture()
    #expect(gesture.button(down: true, now: 0) == nil)
    #expect(gesture.button(down: false, now: 0.1) == nil)
    #expect(gesture.expire(now: 0.3) == nil)
    #expect(gesture.expire(now: 0.4) == .singleTap)
    #expect(gesture.state == .idle)
}

@Test func twoShortPressesAreADoubleTapAtTheSecondPress() {
    var gesture = CreateButtonGesture()
    _ = gesture.button(down: true, now: 0)
    _ = gesture.button(down: false, now: 0.1)
    #expect(gesture.button(down: true, now: 0.25) == .doubleTap)
    #expect(gesture.expire(now: 2) == nil)
    #expect(gesture.button(down: false, now: 2) == nil)
    #expect(gesture.state == .idle)
}

@Test func holdingIsALongPressOnceAndTheReleaseIsQuiet() {
    var gesture = CreateButtonGesture()
    _ = gesture.button(down: true, now: 0)
    #expect(gesture.expire(now: 0.4) == nil)
    #expect(gesture.expire(now: 0.5) == .longPress)
    #expect(gesture.expire(now: 1) == nil)
    #expect(gesture.button(down: false, now: 1.2) == nil)
    #expect(gesture.expire(now: 2) == nil)
}
