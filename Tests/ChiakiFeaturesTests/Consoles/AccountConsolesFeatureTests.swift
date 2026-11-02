import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private func operation(_ value: Int) -> OperationID {
    OperationID(uuid: UUID(value))
}

private let synthetic = PSNConsole(
    deviceID: Data(repeating: 1, count: 32), name: "Synthetic console", ps5: true, remotePlayEnabled: true
)

@MainActor @Test func aNewerListingSupersedesTheOldAndLateResultsAreIgnored() async {
    let clock = TestClock()
    let store = TestStore(initialState: AccountConsolesFeature.State(accountID: UUID())) {
        AccountConsolesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.accountConsoles = { _, ps5 in
            try await clock.sleep(for: .seconds(ps5
                    ? 100
                    : 1))
            return []
        }
    }
    await store.send(.load) {
        $0.phase = .loading(operation(0))
    }
    await store.send(.view(.selectGeneration(ps5: false))) {
        $0.ps5 = false
        $0.phase = .loading(operation(1))
    }
    await store.send(.loaded(operation(0), [synthetic]))
    await clock.advance(by: .seconds(1))
    await store.receive(.loaded(operation(1), [])) {
        $0.phase = .ready
    }
    await clock.advance(by: .seconds(100))
    await store.finish()
}

@MainActor @Test func aFailedListingCanBeRetried() async {
    let store = TestStore(initialState: AccountConsolesFeature.State(accountID: UUID())) {
        AccountConsolesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.accountConsoles = { _, _ in
            throw RegistrationFailure.unavailable
        }
    }
    await store.send(.load) {
        $0.phase = .loading(operation(0))
    }
    await store.receive(.failed(operation(0))) {
        $0.phase = .failed
    }
    store.dependencies.consoles.accountConsoles = { _, _ in
        []
    }
    await store.send(.view(.retry)) {
        $0.phase = .loading(operation(1))
    }
    await store.receive(.loaded(operation(1), [])) {
        $0.phase = .ready
    }
}

@MainActor @Test func theListLeavesOutTheAccountsPairedConsolesAndPicksOnlyListedOnes() async {
    let pairedID = Data(repeating: 1, count: 32)
    let paired = PSNConsole(deviceID: pairedID, name: "Already paired", ps5: true, remotePlayEnabled: true)
    let available = PSNConsole(
        deviceID: Data(repeating: 2, count: 32), name: "New console", ps5: true, remotePlayEnabled: true
    )
    let store = TestStore(
        initialState: AccountConsolesFeature.State(accountID: UUID(), excludedDeviceIDs: [pairedID])
    ) {
        AccountConsolesFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.accountConsoles = { _, _ in
            [paired, available]
        }
    }
    await store.send(.load) {
        $0.phase = .loading(operation(0))
    }
    await store.receive(.loaded(operation(0), [paired, available])) {
        $0.phase = .ready
        $0.consoles = [available]
    }
    await store.send(.view(.select(paired)))
    await store.send(.view(.select(available)))
    await store.receive(.delegate(.selected(.init(
        address: "New console", kind: .ps5, remoteDeviceID: available.deviceID
    ))))
}
