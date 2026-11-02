@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing

private let reportedAt = Date(timeIntervalSince1970: 2000)

let streamRetryWait = OperationProgress(
    step: .launch(.reservingServer), attempt: 2,
    wait: .init(reason: .consoleWaking, nextTry: .milliseconds(2000))
)

let streamReconnectWait = OperationProgress(
    step: .launch(.reservingServer), attempt: 2,
    wait: .init(reason: .connectionRetry, nextTry: .milliseconds(2000)), reconnecting: true
)

private let lockWait = OperationProgress(
    step: .launch(.reservingServer), position: .init(number: 7, total: 10), attempt: 1,
    elapsedMilliseconds: 4000, wait: .init(reason: .previousSessionClosing, nextTry: .milliseconds(10000))
)

@Test func aTimedProgressCountsDownFromTheMomentItWasReported() {
    let timed = TimedProgress(lockWait, at: reportedAt)
    #expect(timed.text(at: reportedAt).lines == [
        "Reserving a server", "Step 7 of 10",
        "Waiting for your previous session to close, trying again in 10 s", "Tried once", "4 s elapsed"
    ])
    #expect(timed.text(at: reportedAt.addingTimeInterval(3)).details == [
        "Step 7 of 10", "Waiting for your previous session to close, trying again in 7 s", "Tried once",
        "7 s elapsed"
    ])
    #expect(timed.text(at: reportedAt.addingTimeInterval(-5)) == timed.text(at: reportedAt))
}
