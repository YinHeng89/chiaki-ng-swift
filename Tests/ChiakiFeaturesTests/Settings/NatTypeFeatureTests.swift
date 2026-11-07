import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func aNatTypeCheckReportsTheType() async {
    let store = TestStore(initialState: NatTypeFeature.State()) {
        NatTypeFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.network = NetworkClient(natType: { () throws(NatTypeFailure) in
            .type2
        })
    }
    await store.send(.checkTapped) {
        $0.check = .checking(UUID(0))
    }
    await store.receive(.checked(UUID(0), .success(.type2))) {
        $0.check = .found(.type2)
    }
    #expect(String(localized: NatTypeSettingsView.detail(store.state.check)).contains("usually connect"))
}

@MainActor @Test func aFailedNatTypeCheckSaysWhyAndALateAnswerIsDropped() async {
    let store = TestStore(initialState: NatTypeFeature.State()) {
        NatTypeFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.network = NetworkClient(natType: { () throws(NatTypeFailure) in
            throw .unanswered
        })
    }
    await store.send(.checkTapped) {
        $0.check = .checking(UUID(0))
    }
    await store.receive(.checked(UUID(0), .failure(.unanswered))) {
        $0.check = .failed(.unanswered)
    }
    await store.send(.checked(UUID(0), .success(.type1)))
    await store.send(.stopped)
}
