import ChiakiModels
import Foundation
import Testing

@Suite struct ConsoleEditFlowTests {
    let first = OperationID(uuid: UUID())
    let second = OperationID(uuid: UUID())
    let draft = ConsoleDraft(
        id: UUID(), name: "Den", address: "192.0.2.4", generation: "PS5", remoteAvailable: false,
        hardwareID: nil
    )

    @Test func onlyTheRunningReadOpensTheEditor() {
        var flow = ConsoleEditFlow.closed
        flow.open(draft, id: first)
        let stale = flow.loaded(ConsoleLaunchOptions(), id: second)
        #expect(!stale)
        flow.loaded(ConsoleLaunchOptions(connectAtLaunch: true), id: first)
        #expect(flow.draft?.connectAtLaunch == true)
    }

    @Test func aDeletionKeepsTheEditorsDraftUntilItSucceeds() {
        var edited = draft
        edited.name = "Changed"
        var flow = ConsoleEditFlow.editing(edited)
        let other = flow.requestDeletion(of: UUID())
        #expect(!other)
        flow.requestDeletion(of: edited.id)
        flow.confirm(first)
        #expect(flow == .deleting(first, edited.id, returning: edited))
        flow.finish(first, failure: .deleteFailed)
        flow.cancel()
        #expect(flow == .editing(edited))
        flow.requestDeletion(of: edited.id)
        flow.confirm(second)
        flow.finish(second, failure: nil)
        #expect(flow == .closed)
    }

    @Test func aRunningSaveCannotBeCancelled() {
        var flow = ConsoleEditFlow.editing(draft)
        flow.confirm(first)
        let cancelled = flow.cancel()
        #expect(!cancelled)
        #expect(flow == .saving(first, draft))
    }

    @Test func aDraftValidatesItsNameAndAddress() {
        var draft = draft
        #expect(draft.isValid)
        draft.name = String(repeating: "x", count: ConsoleDraft.maximumNameLength + 1)
        #expect(!draft.isValid)
        draft.name = "Den"
        draft.address = "not an address"
        #expect(!draft.isValid)
    }
}
