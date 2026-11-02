import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor
@Suite struct ConsoleCatalogFeatureTests {
    let den = RegisteredConsole(
        hardwareID: "aabbccddeeff", id: UUID(), name: "Den", accountID: UUID(), address: "192.0.2.4",
        ps5: true,
        remoteDeviceID: nil
    )

    func operation(_ value: Int) -> OperationID {
        OperationID(uuid: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!)
    }

    @Test func aReadPublishesThePairingsAndAStaleReadIsIgnored() async {
        let den = den
        let clock = TestClock()
        let store = TestStore(initialState: ConsoleCatalogFeature.State()) {
            ConsoleCatalogFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.consoles.pairings = {
                try? await clock.sleep(for: .seconds(1))
                return .success([den])
            }
        }
        await store.send(.load) {
            $0.load = .loading(operation(0))
        }
        await store.send(.loadFinished(operation(7), .failure(.unavailable)))
        await clock.advance(by: .seconds(1))
        await store.receive(.loadFinished(operation(0), .success([den]))) {
            $0.load = .loaded
            $0.consoles = [den]
        }
        await store.receive(.delegate(.loaded([den])))
    }

    @Test func aFailedReloadKeepsTheConsolesItHad() async {
        var initial = ConsoleCatalogFeature.State()
        initial.load = .loaded
        initial.consoles = [den]
        let store = TestStore(initialState: initial) {
            ConsoleCatalogFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.consoles.pairings = {
                .failure(.unavailable)
            }
        }
        await store.send(.load) {
            $0.load = .reloading(operation(0), after: .loaded)
        }
        await store.receive(.loadFinished(operation(0), .failure(.unavailable))) {
            $0.load = .failed
        }
        await store.receive(.delegate(.failed))
        #expect(store.state.consoles == [den])
    }

    @Test func aChangeSavedByAnyScanReloadsThePairings() async {
        let den = den
        let changes = AsyncStream.makeStream(of: Void.self)
        let store = TestStore(initialState: ConsoleCatalogFeature.State()) {
            ConsoleCatalogFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.consoles.pairings = {
                .success([den])
            }
            $0.consoles.pairingChanges = {
                changes.stream
            }
        }
        let observing = await store.send(.observe)
        changes.continuation.yield()
        await store.receive(.load) {
            $0.load = .loading(operation(0))
        }
        await store.receive(.loadFinished(operation(0), .success([den]))) {
            $0.load = .loaded
            $0.consoles = [den]
        }
        await store.receive(.delegate(.loaded([den])))
        await observing.cancel()
    }
}
