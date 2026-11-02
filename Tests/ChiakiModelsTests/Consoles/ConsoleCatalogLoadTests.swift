import ChiakiModels
import Foundation
import Testing

@Suite struct ConsoleCatalogLoadTests {
    let first = OperationID(uuid: UUID())
    let second = OperationID(uuid: UUID())

    @Test func aCatalogReloadKeepsThePreviousOutcomeUntilItFinishes() {
        var load = ConsoleCatalogLoad.pending
        load.start(first)
        #expect(load == .loading(first))
        #expect(load.outcome == nil)
        let stale = load.finish(second, .loaded)
        #expect(!stale)
        load.finish(first, .failed)
        load.start(second)
        #expect(load == .reloading(second, after: .failed))
        #expect(load.outcome == .failed)
        load.finish(second, .loaded)
        #expect(load == .loaded)
        load.start(first)
        load.stop()
        #expect(load == .loaded)
    }
}
