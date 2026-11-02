import ChiakiClients
import ChiakiClientsLive
import ChiakiDiagnostics
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiNG

@MainActor
@Suite struct DeveloperSettingsFeatureTests {
    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    @Test func appearingChecksTheLogAndReadsTheBuildVersions() async {
        let store = TestStore(initialState: DeveloperSettingsFeature.State()) {
            DeveloperSettingsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.settings = .inMemory()
            $0.logSettings.health = {
                false
            }
            $0.settings.buildTakionVersion = { target in
                target == .localPS5
                    ? 12
                    : 0
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        await store.send(.appeared) {
            $0.logHealth = .checking(operation(0))
        }
        await store.receive(.logHealthChecked(operation(0), healthy: false)) {
            $0.logHealth = .unwritable
        }
        #expect(store.state.buildTakionVersion(for: .localPS5) == 12)
        #expect(store.state.buildTakionVersion(for: .psCloud) == DeveloperSettings.automaticTakionVersion)
        await store.send(.logHealthChecked(operation(7), healthy: true))
        #expect(store.state.logHealth == .unwritable)
    }

    @Test func aBuiltReportIsHandedToTheParentAndAFailedOneIsShown() async {
        let fails = LockIsolated(false)
        let store = TestStore(initialState: DeveloperSettingsFeature.State()) {
            DeveloperSettingsFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.logSettings.exportReport = {
                guard !fails.value else {
                    throw CocoaError(.fileReadNoPermission)
                }
                return "report"
            }
        }
        await store.send(.exportReport) {
            $0.report = .building(operation(0))
        }
        await store.receive(.reportBuilt(operation(0), "report")) {
            $0.report = .idle
        }
        await store.receive(.delegate(.reportReady("report")))
        fails.setValue(true)
        await store.send(.exportReport) {
            $0.report = .building(operation(1))
        }
        await store.receive(.reportBuilt(operation(1), nil)) {
            $0.report = .failed
        }
    }

    @Test func takionVersionTitlesNameTheDefaultsAndTheBuildPin() {
        #expect(DeveloperSettings.versionTitle(for: 0, build: 0) == "Automatic")
        #expect(DeveloperSettings.versionTitle(for: 0, build: 12) == "Automatic (v12)")
        #expect(DeveloperSettings.versionTitle(for: 0, build: 20) == "Automatic (v20)")
        #expect(DeveloperSettings.versionTitle(for: 9, build: 0) == "v9")
        #expect(DeveloperSettings.versionTitle(for: 12, build: 0) == "v12")
        #expect(DeveloperSettings.versionTitle(for: 23, build: 23) == "v23")
        #expect(DeveloperSettings.versionTitle(for: 20, build: 0) == "v20")
        #expect(DeveloperSettings.versionTitle(for: 19, build: 0) == "v19")
        #expect(TakionTarget.allCases.map(\.title) == [
            "PS4, local and remote", "PS5, local and remote", "PS Now, PS3 and PS4 cloud",
            "PS Cloud, PS5 cloud"
        ])
    }
}
