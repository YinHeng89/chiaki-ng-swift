@testable import ChiakiFeatures
import ChiakiModels
import ChiakiTestSupport
import ComposableArchitecture
import Foundation
import Testing

@Reducer
struct ProfileFeatureProbe {
    @ObservableState
    struct State: Equatable {
        var profile: RegistrationFlow.Profile?
        var entered = 0
        var stopped = 0
        var other = 0
    }

    enum Action: Equatable {
        case enter, stop, other
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .enter:
                state.entered += 1
            case .stop:
                state.stopped += 1
            case .other:
                state.other += 1
            }
            return .none
        }
    }
}

private let psnProfile = RegistrationFlow.Profile(id: UUID(), name: "PSN", kind: .npsso, accountID: nil)
private let localProfile = RegistrationFlow.Profile(
    id: UUID(), name: "Local", kind: .accountID, accountID: "AAAAAAAAAAA="
)

@Test func onlyLocalPlayIsPermittedWithoutAPSNProfile() {
    #expect(RegistrationFlow.ProfileKind.npsso.permits(.localPlay))
    #expect(RegistrationFlow.ProfileKind.npsso.permits(.cloud))
    #expect(RegistrationFlow.ProfileKind.npsso.permits(.psnConsoles))
    #expect(RegistrationFlow.ProfileKind.accountID.permits(.localPlay))
    #expect(!RegistrationFlow.ProfileKind.accountID.permits(.cloud))
    #expect(!RegistrationFlow.ProfileKind.accountID.permits(.psnConsoles))
    let none: RegistrationFlow.Profile? = nil
    #expect(!none.permits(.localPlay))
    #expect(!none.permits(.cloud))
}

@MainActor @Test func gatePassesEntryActionsForAPSNProfile() async {
    let store = TestStore(initialState: ProfileFeatureProbe.State(profile: psnProfile)) {
        ProfileFeatureProbe().requires(.cloud, of: \.profile, entering: \.enter, otherwise: .stop)
    }
    await store.send(.enter) {
        $0.entered = 1
    }
}

@MainActor @Test func gateDropsEntryActionsAndSendsTheFallbackWithoutAPSNProfile() async {
    let store = TestStore(initialState: ProfileFeatureProbe.State(profile: localProfile)) {
        ProfileFeatureProbe().requires(.cloud, of: \.profile, entering: \.enter, otherwise: .stop)
    }
    await store.send(.enter)
    await store.receive(.stop) {
        $0.stopped = 1
    }
    await store.send(.other) {
        $0.other = 1
    }
}

@MainActor @Test func gateWithoutFallbackDropsEntryActionsSilently() async {
    let store = TestStore(initialState: ProfileFeatureProbe.State(profile: nil)) {
        ProfileFeatureProbe().requires(.psnConsoles, of: \.profile) { action in
            action == .enter
        }
    }
    await store.send(.enter)
}

@MainActor @Test func localProfileCannotStartCloudPlayback() async throws {
    let game = try CloudLibrarySnapshot.decode(Data("""
    {"schemaVersion":11,"nativeMode":true,"settledLocale":"en-GB","resolvedStoreLang":"en",
    "games":[{"productId":"catalog-id","name":"Example","platform":"ps5","category":"owned",
    "isOwned":true,"plusCatalog":false,"streamServiceType":"pscloud",
    "streamIdentifier":"launch-entitlement","entitlementId":"owned-entitlement"}]}
    """.utf8))
    var state = RootFeature.State()
    state.appData.restoreProfiles([localProfile], selected: localProfile.id)
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    let request = try CloudLaunchRequest(accountID: localProfile.id, game: game.games[0])
    await store.send(.stream(.start(try #require(StreamFeature.source(cloud: request)))))
    await store.send(.library(.cloudLibrary(.account(localProfile.id))))
    await store.send(.library(.cloudLibrary(.refresh)))
}

@MainActor @Test func localProfileStopsStaleCloudStatusInsteadOfSelectingIt() async {
    var state = RootFeature.State()
    state.appData.restoreProfiles([psnProfile, localProfile], selected: localProfile.id)
    state.library.cloudStatus.scope = CloudAccountScope(accountID: psnProfile.id, locale: "en-GB")
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    await store.send(.library(.cloudStatus(.select(localProfile.id))))
    await store.receive(.library(.cloudStatus(.stop))) {
        $0.library.cloudStatus = CloudStatusFeature.State()
    }
}

@MainActor @Test func localProfileCannotAddAPSNConsole() async {
    var state = RootFeature.State()
    state.appData.restoreProfiles([localProfile], selected: localProfile.id)
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    await store.send(.view(.play(.remote)))
}
