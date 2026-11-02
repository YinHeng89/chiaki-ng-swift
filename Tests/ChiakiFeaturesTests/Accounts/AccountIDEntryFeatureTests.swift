@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Testing

@MainActor
@Suite struct AccountIDEntryFeatureTests {
    @Test func onlyAValidAccountIDIsSubmittedAndAnEmptyNameGetsADefault() async {
        let store = TestStore(initialState: AccountIDEntryFeature.State()) {
            AccountIDEntryFeature()
        }
        await store.send(.binding(.set(\.accountID, "invalid"))) {
            $0.accountID = "invalid"
        }
        await store.send(.view(.submit))
        await store.send(.binding(.set(\.accountID, " AQAAAAAAAAA= "))) {
            $0.accountID = " AQAAAAAAAAA= "
        }
        await store.send(.view(.submit))
        await store.receive(.delegate(.submitted(name: "PSN account", account: AccountID(value: 1))))
        await store.send(.binding(.set(\.name, "  Couch  "))) {
            $0.name = "  Couch  "
        }
        await store.send(.view(.submit))
        await store.receive(.delegate(.submitted(name: "Couch", account: AccountID(value: 1))))
    }

    @Test func goingBackClearsTheFields() async {
        var initial = AccountIDEntryFeature.State()
        initial.name = "Couch"
        initial.accountID = "AQAAAAAAAAA="
        let store = TestStore(initialState: initial) {
            AccountIDEntryFeature()
        }
        await store.send(.view(.back)) {
            $0.name = ""
            $0.accountID = ""
        }
        await store.receive(.delegate(.left))
    }
}
