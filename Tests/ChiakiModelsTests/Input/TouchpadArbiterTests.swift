import ChiakiModels
import Foundation
import Testing

private let none = TouchpadArbiter.Contacts.none
private let virtualOnly = TouchpadArbiter.Contacts(virtual: true, physical: false)
private let physicalOnly = TouchpadArbiter.Contacts(virtual: false, physical: true)
private let both = TouchpadArbiter.Contacts(virtual: true, physical: true)

@Test func firstTouchingSourceOwnsTheTouchpad() {
    var arbiter = TouchpadArbiter()
    #expect(arbiter.phase == .idle)
    arbiter.update(virtualOnly)
    #expect(arbiter.phase == .owned(.virtual))
    #expect(arbiter.admits(.virtual))
    #expect(!arbiter.admits(.physical))
    arbiter.update(none)
    #expect(arbiter.phase == .idle)
    arbiter.update(physicalOnly)
    #expect(arbiter.owner == .physical)
}

@Test func clicksFollowTheOwnerAndPassThroughWhenIdle() {
    var arbiter = TouchpadArbiter()
    #expect(!arbiter.suppresses(.physical))
    #expect(!arbiter.suppresses(.virtual))
    arbiter.update(virtualOnly)
    #expect(arbiter.suppresses(.physical))
    #expect(!arbiter.suppresses(.virtual))
    arbiter.update(both)
    arbiter.update(physicalOnly)
    #expect(arbiter.phase == .blocked(.physical))
    #expect(arbiter.suppresses(.physical))
    #expect(arbiter.suppresses(.virtual))
}

@Test func physicalWinsWhenBothStartTogether() {
    var arbiter = TouchpadArbiter()
    arbiter.update(both)
    #expect(arbiter.phase == .owned(.physical))
}

@Test func otherSourceCannotTakeOverWhileTheOwnerTouches() {
    var arbiter = TouchpadArbiter()
    arbiter.update(virtualOnly)
    arbiter.update(both)
    #expect(arbiter.phase == .owned(.virtual))
    #expect(!arbiter.admits(.physical))
}

@Test func contactThatStartedUnderAnotherOwnerStaysBlockedUntilLifted() {
    var arbiter = TouchpadArbiter()
    arbiter.update(physicalOnly)
    arbiter.update(both)
    arbiter.update(virtualOnly)
    #expect(arbiter.phase == .blocked(.virtual))
    #expect(arbiter.owner == nil)
    #expect(!arbiter.admits(.virtual))
    #expect(!arbiter.admits(.physical))
    arbiter.update(virtualOnly)
    #expect(arbiter.phase == .blocked(.virtual))
    arbiter.update(none)
    #expect(arbiter.phase == .idle)
    arbiter.update(virtualOnly)
    #expect(arbiter.phase == .owned(.virtual))
}

@Test func formerOwnerMayReclaimWhileTheOtherIsBlocked() {
    var arbiter = TouchpadArbiter()
    arbiter.update(physicalOnly)
    arbiter.update(both)
    arbiter.update(virtualOnly)
    arbiter.update(both)
    #expect(arbiter.phase == .owned(.physical))
    arbiter.update(virtualOnly)
    #expect(arbiter.phase == .blocked(.virtual))
    arbiter.update(physicalOnly)
    #expect(arbiter.phase == .owned(.physical))
}
