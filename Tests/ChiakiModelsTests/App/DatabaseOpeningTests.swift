import ChiakiModels
import Testing

@Suite struct DatabaseOpeningTests {
    @Test func opensOnceAndIgnoresAStaleCompletion() {
        var opening = DatabaseOpening.closed
        let first = OperationID()
        let began = opening.begin(first)
        let beganTwice = opening.begin(OperationID())
        let staleFinished = opening.finish(OperationID(), failure: nil)
        let finished = opening.finish(first, failure: nil)
        let reopened = opening.begin(OperationID())
        #expect(began && !beganTwice && !staleFinished && finished && !reopened)
        #expect(opening == .open)
    }

    @Test func aFailedOpenCanBeRetried() {
        var opening = DatabaseOpening.closed
        let first = OperationID(), retry = OperationID()
        opening.begin(first)
        let failed = opening.finish(first, failure: .keyUnavailable)
        #expect(failed)
        #expect(opening == .failed(.keyUnavailable))
        let retried = opening.begin(retry)
        let staleFinished = opening.finish(first, failure: nil)
        let finished = opening.finish(retry, failure: nil)
        #expect(retried && !staleFinished && finished)
        #expect(opening == .open)
    }
}
