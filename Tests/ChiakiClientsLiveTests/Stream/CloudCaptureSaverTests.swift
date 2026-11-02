import Testing
@testable import ChiakiClientsLive

@Test func cloudCaptureResavesWaitLongerEachTimeUpToFourMinutes() {
    let delays = (1...7).map {
        CloudCaptureSaver.resaveDelay(afterAttempts: $0)
    }
    #expect(delays == [.seconds(30), .seconds(60), .seconds(120), .seconds(240), .seconds(240),
                       .seconds(240), .seconds(240)])
    #expect(CloudCaptureSaver.resaveDelay(afterAttempts: 0) == .seconds(30))
    let waited = delays.reduce(Duration.zero, +)
    #expect(waited > .seconds(15 * 60) && waited < .seconds(25 * 60))
    #expect(CloudCaptureSaver.maximumAttempts == delays.count + 1)
}
