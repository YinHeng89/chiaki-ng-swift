import ChiakiModels
@testable import ChiakiFeatures
import Foundation
import Testing

@Test func consolesCountAsLoadingUntilAccountsAndRegistrationsArrive() {
    var state = RootFeature.State()
    #expect(!state.loadingConsoles)
    state.accounts.operation = .loading(OperationID(uuid: UUID()))
    #expect(state.loadingConsoles)
    state.accounts.operation = .idle
    state.consoleCatalog.load = .loading(OperationID(uuid: UUID()))
    #expect(state.loadingConsoles)
    state.consoleCatalog.load = .failed
    #expect(!state.loadingConsoles)
}
