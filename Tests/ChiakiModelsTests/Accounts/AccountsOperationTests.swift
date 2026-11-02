import ChiakiModels
import Foundation
import Testing

@Suite struct AccountsOperationTests {
    let first = OperationID(uuid: UUID())
    let second = OperationID(uuid: UUID())
    let profile = UUID()

    @Test func operationsExcludeEachOtherAndOnlyTheRunningOneFinishes() {
        var operation = AccountsOperation.idle
        let results = [
            operation.startLoading(first),
            !operation.startSaving(second),
            !operation.requestDeletion(of: profile),
            !operation.finish(second, failure: nil),
            operation.finish(first, failure: .loadFailed)
        ]
        #expect(results.allSatisfy { $0 })
        #expect(operation == .failed(.loadFailed))
        let saved = [operation.startSaving(second), operation.finish(second, failure: nil)]
        #expect(saved == [true, true])
        #expect(operation == .idle)
    }

    @Test func aDeletionIsConfirmedOrWithdrawn() {
        var operation = AccountsOperation.idle
        let unconfirmed = operation.confirmDeletion(first)
        #expect(unconfirmed == nil)
        let withdrawn = [operation.requestDeletion(of: profile), operation.cancelDeletion()]
        #expect(withdrawn == [true, true])
        #expect(operation == .idle)
        operation.requestDeletion(of: profile)
        let confirmed = operation.confirmDeletion(first)
        #expect(confirmed == profile)
        #expect(operation == .deleting(first, profile))
        operation.finish(first, failure: .deleteFailed)
        #expect(operation.failure == .deleteFailed)
    }

    @Test func stoppingAbandonsWorkButKeepsAShownFailure() {
        var operation = AccountsOperation.loading(first)
        operation.stop()
        #expect(operation == .idle)
        operation = .failed(.saveFailed)
        operation.stop()
        #expect(operation == .failed(.saveFailed))
    }

    @Test func theRefreshRunsOnceAndOnlyItsOwnResultEndsIt() {
        var refresh = AccountsRefresh.idle
        let results = [
            refresh.start(first),
            !refresh.start(second),
            !refresh.finish(second, clean: true),
            refresh.finish(first, clean: false)
        ]
        #expect(results.allSatisfy { $0 })
        #expect(refresh == .failed)
        refresh.start(second)
        refresh.stop()
        #expect(refresh == .idle)
    }
}
