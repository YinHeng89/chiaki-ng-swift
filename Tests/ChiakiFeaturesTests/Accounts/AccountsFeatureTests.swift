import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct AccountsFeatureTests {
    let now = Date(timeIntervalSince1970: 10_000)
    let first = AccountProfile(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "First", method: .npsso, accountID: AccountID(value: 1)
    )
    let second = AccountProfile(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        name: "Second", method: .accountID, accountID: AccountID(value: 2)
    )

    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: uuid(value))
    }

    func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
    }

    func store(
        _ state: AccountsFeature.State = AccountsFeature.State(),
        _ dependencies: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AccountsFeature> {
        let now = now
        return TestStore(initialState: state) {
            AccountsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = now
            dependencies(&$0)
        }
    }

    func receiveRefresh(
        of accounts: [AccountProfile],
        operation id: Int,
        in store: TestStoreOf<AccountsFeature>
    ) async {
        let result = AccountRefreshResult(accounts: accounts)
        await store.receive(.refreshFinished(operation(id), .success(result))) {
            $0.refresh = .idle
            $0.lastRefreshed = now
        }
        await store.receive(.delegate(.refreshed(before: accounts, result: result)))
    }

    @Test func loadingPublishesTheAccountsAndRefreshesThemOnce() async {
        let accounts = [first]
        let store = store {
            $0.accounts.load = {
                .success(accounts)
            }
            $0.accounts.refresh = {
                .success(AccountRefreshResult(accounts: accounts))
            }
        }
        await store.send(.load) {
            $0.operation = .loading(operation(0))
        }
        await store.receive(.loadFinished(operation(0), .success(accounts))) {
            $0.operation = .idle
            $0.accounts = accounts
            $0.availability = .settled
            $0.refresh = .refreshing(operation(1))
        }
        await store.receive(.delegate(.loaded(accounts)))
        await store.receive(.delegate(.refreshStarted(count: 1, reason: .firstSinceLoad)))
        await receiveRefresh(of: accounts, operation: 1, in: store)
        await store.send(.refresh(force: false))
    }

    @Test func cancellingDuringTheLoadNoLongerLeavesTheAccountsUnloaded() async {
        let gate = AsyncStream.makeStream(of: Void.self)
        let store = store {
            $0.accounts.load = {
                for await _ in gate.stream {
                    break
                }
                return .success([])
            }
        }
        await store.send(.load) {
            $0.operation = .loading(operation(0))
        }
        await store.send(.view(.cancelSaving))
        gate.continuation.yield()
        await store.receive(.loadFinished(operation(0), .success([]))) {
            $0.operation = .idle
            $0.availability = .settled
        }
        await store.receive(.delegate(.loaded([])))
        #expect(store.state.hasLoaded)
    }

    @Test func aStoppedLoadLoadsAgainOnTheNextRequest() async {
        let gate = AsyncStream.makeStream(of: Void.self)
        let store = store {
            $0.accounts.load = {
                for await _ in gate.stream {
                    break
                }
                return .success([])
            }
        }
        await store.send(.load) {
            $0.operation = .loading(operation(0))
        }
        await store.send(.stop) {
            $0.operation = .idle
        }
        await store.send(.loadFinished(operation(0), .success([])))
        await store.send(.load) {
            $0.operation = .loading(operation(1))
        }
        gate.continuation.yield()
        await store.receive(.loadFinished(operation(1), .success([]))) {
            $0.operation = .idle
            $0.availability = .settled
        }
        await store.receive(.delegate(.loaded([])))
    }

    @Test func aFailedLoadSettlesWithItsFailure() async {
        let store = store {
            $0.accounts.load = {
                .failure(.loadFailed)
            }
        }
        await store.send(.load) {
            $0.operation = .loading(operation(0))
        }
        await store.receive(.loadFinished(operation(0), .failure(.loadFailed))) {
            $0.operation = .failed(.loadFailed)
            $0.availability = .settled
        }
        await store.receive(.delegate(.loadFailed))
    }

    @Test func anAccountAddedByIDIsPublishedOnlyAfterItIsSaved() async {
        let second = second
        let store = store {
            $0.accounts.addAccountID = { _, name, account in
                #expect(name == "Second" && account == AccountID(value: 2))
                return .success(second)
            }
            $0.accounts.refresh = {
                .success(AccountRefreshResult(accounts: [second]))
            }
        }
        await store.send(.addAccountID(profile: second.id, name: "Second", account: AccountID(value: 2))) {
            $0.operation = .saving(operation(0))
        }
        await store.receive(.saveFinished(operation(0), .success(second))) {
            $0.operation = .idle
            $0.accounts = [second]
            $0.refresh = .refreshing(operation(1))
        }
        await store.receive(.delegate(.saved(second)))
        await store.receive(.delegate(.refreshStarted(count: 1, reason: .accountAdded)))
        await receiveRefresh(of: [second], operation: 1, in: store)
    }

    @Test func aFailedSaveShowsItsFailureAndPublishesNothing() async {
        let store = store {
            $0.accounts.addAccountID = { _, _, _ in
                .failure(.saveFailed)
            }
        }
        await store.send(.addAccountID(profile: second.id, name: "Second", account: AccountID(value: 2))) {
            $0.operation = .saving(operation(0))
        }
        await store.receive(.saveFinished(operation(0), .failure(.saveFailed))) {
            $0.operation = .failed(.saveFailed)
        }
        #expect(store.state.accounts.isEmpty)
    }

    @Test func deletingAsksForConfirmationAndRemovesTheAccount() async {
        var initial = AccountsFeature.State(loaded: [first, second])
        initial.refreshIssues = [first.id: .signInRequired]
        let first = first
        let store = store(initial) {
            $0.accounts.delete = { profile in
                #expect(profile == first.id)
                return nil
            }
        }
        await store.send(.view(.requestDeletion(UUID())))
        await store.send(.view(.requestDeletion(first.id))) {
            $0.operation = .confirmingDeletion(first.id)
        }
        await store.send(.view(.cancelDeletion)) {
            $0.operation = .idle
        }
        await store.send(.view(.requestDeletion(first.id))) {
            $0.operation = .confirmingDeletion(first.id)
        }
        await store.send(.view(.confirmDeletion)) {
            $0.operation = .deleting(operation(0), first.id)
        }
        await store.receive(.deleteFinished(operation(0), nil)) {
            $0.operation = .idle
            $0.accounts = [second]
            $0.refreshIssues = [:]
        }
        await store.receive(.delegate(.deleted(first.id)))
    }

    @Test func aFailedDeletionKeepsTheAccount() async {
        let store = store(AccountsFeature.State(loaded: [first])) {
            $0.accounts.delete = { _ in
                .deleteFailed
            }
        }
        await store.send(.view(.requestDeletion(first.id))) {
            $0.operation = .confirmingDeletion(first.id)
        }
        await store.send(.view(.confirmDeletion)) {
            $0.operation = .deleting(operation(0), first.id)
        }
        await store.receive(.deleteFinished(operation(0), .deleteFailed)) {
            $0.operation = .failed(.deleteFailed)
        }
        #expect(store.state.accounts == [first])
    }

    @Test func anUnforcedRefreshWaitsAMinuteAndAStaleResultIsIgnored() async {
        var initial = AccountsFeature.State(loaded: [first])
        initial.lastRefreshed = now.addingTimeInterval(-30)
        let store = store(initial) {
            $0.accounts.refresh = {
                .failure(.refreshFailed)
            }
        }
        await store.send(.refresh(force: false))
        await store.send(.refreshFinished(operation(9), .failure(.refreshFailed)))
        await store.send(.refresh(force: true)) {
            $0.refresh = .refreshing(operation(0))
        }
        await store.receive(.delegate(.refreshStarted(count: 1, reason: .accountAdded)))
        await store.receive(.refreshFinished(operation(0), .failure(.refreshFailed))) {
            $0.refresh = .failed
            $0.lastRefreshed = now
        }
        await store.receive(.delegate(.refreshFailed))
    }

    @Test func aSignedInAccountIsAdoptedAndRefreshed() async {
        let first = first
        let store = store {
            $0.accounts.refresh = {
                .success(AccountRefreshResult(accounts: [first]))
            }
        }
        await store.send(.adopt(first)) {
            $0.accounts = [first]
            $0.refresh = .refreshing(operation(0))
        }
        await store.receive(.delegate(.saved(first)))
        await store.receive(.delegate(.refreshStarted(count: 1, reason: .accountAdded)))
        await receiveRefresh(of: [first], operation: 0, in: store)
    }
}
