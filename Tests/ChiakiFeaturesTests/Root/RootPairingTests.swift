@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let profileID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
private let account = AccountID(value: 0x0101_0101_0101_0101)

private func addConsolePage(accountID: String? = account.base64) -> RootFeature.State {
    var state = RootFeature.State(route: .library)
    state.appData.restoreProfiles([.init(id: profileID, name: "Demo", kind: .npsso, accountID: accountID)])
    state.route = .addConsole(AddConsoleFeature.State(account: profileID, modes: AddConsoleMode.allCases))
    return state
}

private func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))!
}

private func pairedConsole() -> PairedConsole {
    PairedConsole(
        hardwareID: HardwareID(hex: "a1b2c3d4e5f6")!, name: "PS5-117", nameSource: .pairing, firmware: .ps5,
        address: "127.0.0.1"
    )
}

private let home = PairingTarget.atHome(address: "127.0.0.1", kind: .ps5)

@MainActor @Test func aHomeConsoleIsPairedOnThePairingRouteAndGoesStraightToTheLibrary() async {
    let paired = pairedConsole()
    let state = addConsolePage()
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.consoles.pair = { _, _, pin, _ in
            pin == "12345678"
                ? .success(paired)
                : .failure(.rejected)
        }
        $0.consoles.pairings = {
            .success([])
        }
        $0.logger = .disabled
    }
    store.exhaustivity = .off
    await store.send(.route(.addConsole(.delegate(.pair(.init(address: " 127.0.0.1 ", kind: .ps5)))))) {
        $0.route = .pairing(PairingFeature.State(account: account, target: home))
    }
    await store.receive(.discovery(.release(.addConsole)))
    await store.send(.route(.pairing(.binding(.set(\.pin, "12345678")))))
    await store.send(.route(.pairing(.view(.submitPIN))))
    await store.receive(\.route.pairing.delegate.attemptStarted)
    await store.receive(\.route.pairing.attemptFinished)
    await store.receive(\.route.pairing.delegate.attemptEnded)
    await store.receive(\.route.pairing.delegate.paired) {
        $0.route = .library
    }
    #expect(store.state.selectedConsole?.hardwareID == "a1b2c3d4e5f6")
    await store.receive(\.consoleCatalog.load)
    await store.receive(\.consoleCatalog.delegate.loaded) {
        $0.catalogStatus = .loaded
    }
}

@MainActor @Test func anInternetFailureReturnsToTheAddConsoleScreenOnPlayStationAndShowsWhy() async throws {
    let device = Data(repeating: 1, count: 32)
    let console = RegistrationFlow.ConsoleTarget(
        address: "Den",
        kind: .ps5,
        remoteDeviceID: device,
        name: "Den"
    )
    let uid = try #require(ConsoleDeviceUID(bytes: device))
    let target = PairingTarget.overInternet(AccountConsoleTarget(deviceUID: uid, name: "Den", kind: .ps5))
    let failure = PairingFailure.overInternet(.connecting, code: 403)
    let state = addConsolePage()
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.consoles.pair = { _, _, _, _ in
            .failure(failure)
        }
        $0.logger = .disabled
    }
    store.exhaustivity = .off
    await store.send(.route(.addConsole(.delegate(.pair(console))))) {
        $0.route = .pairing(PairingFeature.State(account: account, target: target))
    }
    await store.receive(\.route.pairing.start)
    await store.receive(\.route.pairing.delegate.attemptStarted)
    await store.receive(\.route.pairing.attemptFinished)
    await store.receive(\.route.pairing.delegate.left) {
        $0.route = .addConsole(AddConsoleFeature.State(
            account: profileID,
            modes: AddConsoleMode.allCases,
            preferred: .playStation
        ))
        $0.pairingFailure = failure
    }
    #expect(store.state.registrations.isEmpty)
}

@MainActor @Test func cancellingAPairingReturnsToAddConsoleWithTheTypedAddressAndMode() async {
    var state = addConsolePage()
    state.route = .addConsole(AddConsoleFeature.State(
        account: profileID,
        modes: AddConsoleMode.allCases,
        preferred: .manual
    ))
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.logger = .disabled
    }
    store.exhaustivity = .off
    await store.send(.route(.addConsole(.binding(.set(\.address, "127.0.0.1")))))
    await store.send(.route(.addConsole(.binding(.set(\.kind, .ps4)))))
    await store.send(.route(.addConsole(.view(.submitAddress))))
    await store.receive(\.route.addConsole.delegate.pair)
    #expect(store.state.route.is(\.pairing))
    await store.send(.route(.pairing(.view(.cancel))))
    await store.receive(\.route.pairing.delegate.left)
    let addConsole = store.state.route.addConsole
    #expect(addConsole?.mode == .manual)
    #expect(addConsole?.address == "127.0.0.1")
    #expect(addConsole?.kind == .ps4)
    #expect(store.state.addConsoleDraft == nil)
}

@MainActor @Test func leavingThePairingRouteCancelsARunningPairing() async {
    let waiting = TestClock()
    let state = addConsolePage()
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.consoles.pair = { _, _, _, _ in
            try? await waiting.sleep(for: .seconds(30))
            return .success(pairedConsole())
        }
        $0.logger = .disabled
    }
    store.exhaustivity = .off
    await store.send(.route(.addConsole(.delegate(.pair(.init(address: "127.0.0.1", kind: .ps5))))))
    await store.send(.route(.pairing(.binding(.set(\.pin, "12345678")))))
    await store.send(.route(.pairing(.view(.submitPIN))))
    await store.receive(\.route.pairing.delegate.attemptStarted)
    await store.send(.view(.disappeared)) {
        $0.route = .library
    }
    await waiting.advance(by: .seconds(30))
    await store.finish()
    #expect(store.state.registrations.isEmpty)
}

@MainActor @Test func aProfileWithoutAnAccountIDCannotStartPairing() async {
    let state = addConsolePage(accountID: nil)
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    store.exhaustivity = .off
    await store.send(.route(.addConsole(.delegate(.pair(.init(address: "127.0.0.1", kind: .ps5)))))) {
        $0.pairingFailure = .invalidInput
    }
    #expect(store.state.route.is(\.addConsole))
}

@MainActor @Test func aSignedInProfilePairsAConsoleOverTheInternet() async throws {
    let device = Data(repeating: 1, count: 32)
    let target = RegistrationFlow.ConsoleTarget(
        address: "Synthetic PS5", kind: .ps5, remoteDeviceID: device, name: "Synthetic PS5"
    )
    let uid = try #require(ConsoleDeviceUID(bytes: device))
    let state = addConsolePage()
    let store = TestStore(initialState: state) {
        RootFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.consoles.pair = { _, _, _, _ in
            .failure(.rejected)
        }
        $0.logger = .disabled
    }
    store.exhaustivity = .off
    await store.send(.route(.addConsole(.delegate(.pair(target))))) {
        $0.route = .pairing(PairingFeature.State(
            account: account,
            target: .overInternet(AccountConsoleTarget(deviceUID: uid, name: "Synthetic PS5", kind: .ps5))
        ))
    }
}

@MainActor @Test func aProfileAddedByAccountIDCannotPairOverTheInternet() async {
    let target = RegistrationFlow.ConsoleTarget(
        address: "Synthetic PS5", kind: .ps5, remoteDeviceID: Data(repeating: 1, count: 32)
    )
    var state = addConsolePage()
    state.appData.restoreProfiles([
        .init(id: profileID, name: "Manual", kind: .accountID, accountID: account.base64)
    ])
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    await store.send(.route(.addConsole(.delegate(.pair(target)))))
}

@MainActor @Test func aTruncatedDeviceIDIsNotPaired() async {
    let truncated = RegistrationFlow.ConsoleTarget(address: "Short", kind: .ps5, remoteDeviceID: Data([1]))
    let state = addConsolePage()
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    await store.send(.route(.addConsole(.delegate(.pair(truncated)))))
}

@MainActor @Test func anInvalidAddressIsNotPaired() async {
    let state = addConsolePage()
    let store = TestStore(initialState: state) {
        RootFeature()
    }
    await store.send(.route(.addConsole(.delegate(.pair(.init(address: " ", kind: .ps5))))))
}
