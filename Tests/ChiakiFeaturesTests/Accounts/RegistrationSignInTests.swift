import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let signedIn = AccountProfile(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
    name: "Player", method: .npsso, accountID: AccountID(value: 7)
)

@MainActor private func welcomeStore(
    signedInAs profile: AccountProfile = signedIn,
    signInRequests: LockIsolated<[UUID]> = LockIsolated([])
) -> TestStoreOf<RootFeature> {
    let store = TestStore(initialState: RootFeature.State(route: .welcome)) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.accounts.captureSignIn = { _ throws(SignInFailure) in
            guard let npsso = NPSSO("synthetic-npsso") else {
                throw .unreadableResponse
            }
            return SignInCapture(npsso: npsso, expiresAt: nil, expirySource: .unknown)
        }
        $0.accounts.signIn = { requested, _ in
            signInRequests.withValue {
                $0.append(requested)
            }
            return .success(profile)
        }
        $0.accounts.signInWithQR = { requested, progress in
            signInRequests.withValue {
                $0.append(requested)
            }
            progress(.awaitingApproval(QRSignInCode(
                attempt: 1, approvalURL: "https://example.invalid/approve", userCode: "012345", expiresAt: nil
            )))
            progress(.signingIn)
            return .success(profile)
        }
        $0.accounts.addAccountID = { requested, name, account in
            .success(AccountProfile(id: requested, name: name, method: .accountID, accountID: account))
        }
        $0.accounts.refresh = {
            .failure(.refreshFailed)
        }
        $0.accounts.selectAccount = { _ in
            true
        }
        $0.logger = .disabled
        $0.date.now = Date(timeIntervalSince1970: 1000)
    }
    store.exhaustivity = .off
    return store
}

@MainActor @Test func aNewAccountSignsInWithAQRCodeAndShowsTheLibrary() async {
    let requests = LockIsolated<[UUID]>([])
    let store = welcomeStore(signInRequests: requests)
    await store.send(.view(.chooseSignIn))
    #expect(store.state.route.signIn?.method == .qrCode)
    await store.send(.route(.signIn(.view(.appeared))))
    await store.skipReceivedActions()
    #expect(store.state.route == .library)
    #expect(store.state.selectedAccount == signedIn.id)
    #expect(requests.value.count == 1)
}

@MainActor @Test func signingInThroughTheStubbedBrowserAddsTheAccountAndShowsTheLibrary() async {
    let store = welcomeStore()
    await store.send(.view(.chooseSignIn))
    #expect(store.state.route == .signIn(SignInFeature.State()))
    await store.send(.route(.signIn(.view(.choose(.browser)))))
    await store.send(.route(.signIn(.view(.start))))
    await store.skipReceivedActions()
    #expect(store.state.route == .library)
    #expect(store.state.selectedAccount == signedIn.id)
    #expect(store.state.accounts.accounts == [signedIn])
}

@MainActor @Test func leavingTheSignInReturnsToTheWelcomeScreen() async {
    let store = welcomeStore()
    await store.send(.view(.chooseSignIn))
    await store.send(.route(.signIn(.view(.back))))
    await store.skipReceivedActions()
    #expect(store.state.route == .welcome)
    #expect(store.state.accounts.accounts.isEmpty)
}

@MainActor @Test func reconnectingAnAccountSignsTheSameProfileInAgain() async {
    let requests = LockIsolated<[UUID]>([])
    let store = welcomeStore(signInRequests: requests)
    await store.send(.accounts(.adopt(signedIn)))
    await store.skipReceivedActions()
    #expect(store.state.route == .library)
    await store.send(.view(.reconnectAccount(signedIn.id)))
    #expect(store.state.route == .signIn(SignInFeature.State(reconnecting: signedIn.id)))
    await store.send(.route(.signIn(.view(.start))))
    await store.skipReceivedActions()
    #expect(requests.value == [signedIn.id])
    #expect(store.state.route == .library)
}

@MainActor @Test func anAccountAddedByIDIsSavedAndSelected() async {
    let store = welcomeStore()
    await store.send(.view(.chooseAccountID))
    #expect(store.state.route == .accountIDEntry(AccountIDEntryFeature.State()))
    await store.send(.route(.accountIDEntry(.binding(.set(\.accountID, "AQAAAAAAAAA=")))))
    await store.send(.route(.accountIDEntry(.view(.submit))))
    await store.skipReceivedActions()
    #expect(store.state.route == .library)
    #expect(store.state.accounts.accounts.map(\.accountID) == [AccountID(value: 1)])
}
