@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private func profiles() -> [AccountProfile] {
    [
        AccountProfile(id: UUID(), name: "First", method: .accountID, accountID: AccountID(value: 1)),
        AccountProfile(id: UUID(), name: "Second", method: .accountID, accountID: AccountID(value: 2))
    ]
}

@MainActor private func launch(
    _ saved: [AccountProfile],
    active: UUID?,
    remembered: LockIsolated<[UUID]> = LockIsolated([])
) async -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: RootFeature.State()) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.accounts.load = {
            .success(saved)
        }
        $0.accounts.refresh = {
            .success(AccountRefreshResult(accounts: saved))
        }
        $0.accounts.selectedAccount = {
            active
        }
        $0.accounts.selectAccount = { id in
            remembered.withValue {
                $0.append(id)
            }
            return true
        }
        $0.consoles.pairings = {
            .success([])
        }
        $0.logger = .disabled
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off
    await store.send(.accounts(.load))
    await store.skipReceivedActions()
    return store
}

@MainActor @Test func launchRestoresTheSavedActiveAccount() async {
    let saved = profiles()
    let store = await launch(saved, active: saved[1].id)
    #expect(store.state.selectedAccount == saved[1].id)
    #expect(store.state.accounts.hasLoaded)
}

@MainActor @Test func launchFallsBackToTheFirstAccountWhenTheSavedOneIsGone() async {
    let saved = profiles()
    let unknown = await launch(saved, active: UUID())
    #expect(unknown.state.selectedAccount == saved[0].id)
    let missing = await launch(saved, active: nil)
    #expect(missing.state.selectedAccount == saved[0].id)
}

@MainActor @Test func switchingAccountsRemembersTheChoice() async {
    let saved = profiles()
    let remembered = LockIsolated<[UUID]>([])
    let store = await launch(saved, active: nil, remembered: remembered)
    await store.send(.view(.selectAccount(saved[1].id)))
    await store.skipReceivedActions()
    await store.send(.view(.selectAccount(UUID())))
    await store.skipReceivedActions()
    #expect(store.state.selectedAccount == saved[1].id)
    #expect(remembered.value == [saved[1].id])
}
