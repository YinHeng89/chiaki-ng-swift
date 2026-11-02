import Testing
import ChiakiModels

@Test func fullScreenEntersAndLeavesAroundAStream() {
    var machine = WindowFullScreenMachine()
    #expect(machine.handle(.present(windowIsFullScreen: false)) == [.observe, .toggle, .scheduleTimeout(1)])
    #expect(machine.phase == .entering(attempt: 1))
    #expect(machine.handle(.entered).isEmpty)
    #expect(machine.phase == .entered)
    #expect(machine.handle(.restore(windowIsFullScreen: true)) == [.toggle, .scheduleTimeout(2)])
    #expect(machine.handle(.exited) == [.stopObserving])
    #expect(machine.phase == .untouched)
}

@Test func aWindowTheUserMadeFullScreenIsLeftAlone() {
    var machine = WindowFullScreenMachine()
    #expect(machine.handle(.present(windowIsFullScreen: true)).isEmpty)
    #expect(machine.handle(.restore(windowIsFullScreen: true)).isEmpty)
    #expect(machine.phase == .untouched)
}

@Test func restoringDuringEntryLeavesOnceEntryFinishes() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    #expect(machine.handle(.restore(windowIsFullScreen: false)).isEmpty)
    #expect(machine.handle(.entered) == [.toggle, .scheduleTimeout(2)])
    #expect(machine.handle(.exited) == [.stopObserving])
}

@Test func presentingDuringExitEntersAgainOnceExitFinishes() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    _ = machine.handle(.entered)
    _ = machine.handle(.restore(windowIsFullScreen: true))
    #expect(machine.handle(.present(windowIsFullScreen: true)).isEmpty)
    #expect(machine.handle(.exited) == [.toggle, .scheduleTimeout(3)])
    #expect(machine.phase == .entering(attempt: 3))
}

@Test func aStaleTimeoutDoesNotEndANewerAttempt() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    _ = machine.handle(.entered)
    _ = machine.handle(.restore(windowIsFullScreen: true))
    _ = machine.handle(.exited)
    _ = machine.handle(.present(windowIsFullScreen: false))
    #expect(machine.handle(.timedOut(attempt: 1, windowIsFullScreen: false)).isEmpty)
    #expect(machine.phase == .entering(attempt: 3))
}

@Test func anEntryThatCompletesAfterTheTimeoutIsStillTracked() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    #expect(machine.handle(.timedOut(attempt: 1, windowIsFullScreen: false)).isEmpty)
    #expect(machine.phase == .lateEntry(exitOnArrival: false))
    #expect(machine.handle(.restore(windowIsFullScreen: false)).isEmpty)
    #expect(machine.handle(.entered) == [.toggle, .scheduleTimeout(2)])
    #expect(machine.handle(.exited) == [.stopObserving])
}

@Test func aSlowEntryAfterRestoreStillLeavesFullScreen() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    _ = machine.handle(.restore(windowIsFullScreen: false))
    #expect(machine.handle(.timedOut(attempt: 1, windowIsFullScreen: true)) == [.toggle, .scheduleTimeout(2)])
    #expect(machine.handle(.exited) == [.stopObserving])
}

@Test func leavingFullScreenByHandEndsTracking() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    _ = machine.handle(.entered)
    #expect(machine.handle(.exited) == [.stopObserving])
    #expect(machine.handle(.restore(windowIsFullScreen: false)).isEmpty)
}

@Test func anIgnoredExitIsRetried() {
    var machine = WindowFullScreenMachine()
    _ = machine.handle(.present(windowIsFullScreen: false))
    _ = machine.handle(.entered)
    _ = machine.handle(.restore(windowIsFullScreen: true))
    #expect(machine.handle(.timedOut(attempt: 2, windowIsFullScreen: true)) == [.toggle, .scheduleTimeout(3)])
    #expect(machine.phase == .exiting(attempt: 3))
    #expect(machine.handle(.exited) == [.stopObserving])
}
