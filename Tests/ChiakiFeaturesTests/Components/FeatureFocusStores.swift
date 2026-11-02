import ChiakiClients
import ChiakiDiagnostics
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation

@MainActor
enum FeatureFocusStores {
    static func rootStore(tab: SettingsRoute? = nil) -> StoreOf<RootFeature> {
        var state = RootFeature.State(route: .library)
        if let tab {
            state.settings.route = tab
        }
        return Store(initialState: state) {
            RootFeature()
        } withDependencies: {
            $0.logSettings = .testValue
            $0.controllers = .testValue
            $0.uuid = .incrementing
        }
    }

    static func libraryStore(
        consoles: [RegistrationFlow.ConsoleTarget],
        section: LibrarySection = .consoles,
        requests: LockIsolated<[LibraryRequest]> = LockIsolated([]),
        configure: (inout LibraryFeature.State) -> Void = { _ in
        }
    ) -> StoreOf<LibraryFeature> {
        let profileID = UUID()
        @Shared(.accounts) var accounts
        @Shared(.selectedAccount) var selected
        @Shared(.consoleCatalog) var catalog
        $accounts.withLock {
            $0 = [.init(id: profileID, name: "Player", kind: .npsso, accountID: nil)]
        }
        $selected.withLock {
            $0 = profileID
        }
        $catalog.withLock {
            $0 = consoles.map {
                .init(profileID: profileID, console: $0)
            }
        }
        var state = LibraryFeature.State(section: section)
        configure(&state)
        return Store(initialState: state) {
            LibraryFeature()
            Reduce { _, action in
                if case .requested(let request) = action {
                    requests.withValue {
                        $0.append(request)
                    }
                }
                return .none
            }
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        }
    }

    static func console(
        _ index: Int,
        kind: RegistrationFlow.ConsoleKind = .ps5,
        remote: Bool = true
    ) -> RegistrationFlow.ConsoleTarget {
        RegistrationFlow.ConsoleTarget(
            address: "console-\(index)",
            kind: kind,
            remoteDeviceID: remote
                ? Data([UInt8(index)])
                : nil,
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))
        )
    }

    static func settingsStore(
        tab: SettingsRoute? = nil,
        reach: PSNReach = .signedIn,
        network: NetworkSettingsFeature.State? = nil,
        settings: SettingsClient = .inMemory()
    ) -> StoreOf<SettingsFeature> {
        var state = SettingsFeature.State()
        state.psnReach = reach
        if let network {
            state.network = network
        }
        if let tab {
            state.route = tab
        }
        return Store(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.logSettings = .testValue
            $0.controllers = .testValue
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()
            $0.kakusan.identity = {
                throw KakusanError.internal
            }
            $0.kakusan.peers = {
                []
            }
            $0.kakusan.loadSettings = {
                KakusanSettings()
            }
            $0.continuousClock = TestClock()
            $0.settings = settings
        }
    }
}
