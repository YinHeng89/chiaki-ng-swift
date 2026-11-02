import ChiakiModels
import Foundation
import Testing
@testable import ChiakiNG

@MainActor @Test func sleepNoticesAreHeldUntilAllowedOnce() {
    var notices = [Int]()
    var wakes = 0
    let observer = SystemPowerObserver(longestHold: .seconds(30), willSleep: {
        notices.append($0)
    }, didWake: {
        wakes += 1
    })
    observer.receive(SystemPowerObserver.Message.canSystemSleep.rawValue, argument: 1)
    #expect(notices.isEmpty && observer.heldNotifications.isEmpty)
    observer.receive(SystemPowerObserver.Message.systemWillSleep.rawValue, argument: 2)
    observer.receive(SystemPowerObserver.Message.systemWillSleep.rawValue, argument: 2)
    #expect(notices == [2] && observer.heldNotifications == [2])
    observer.allowSleep(2)
    observer.allowSleep(2)
    #expect(observer.heldNotifications.isEmpty)
    observer.receive(0xE000_0320, argument: 3)
    #expect(notices == [2] && wakes == 0)
    observer.receive(0xE000_0300, argument: 4)
    #expect(notices == [2] && wakes == 0)
}

@MainActor @Test func sleepIsAllowedAnywayWhenStreamsTakeTooLong() async {
    var notices = [Int]()
    let observer = SystemPowerObserver(longestHold: .milliseconds(20), willSleep: {
        notices.append($0)
    })
    observer.receive(SystemPowerObserver.Message.systemWillSleep.rawValue, argument: 5)
    #expect(observer.heldNotifications == [5])
    for _ in 0..<50 where !observer.heldNotifications.isEmpty {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(observer.heldNotifications.isEmpty)
    #expect(notices == [5])
}
