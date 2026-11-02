import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing
@testable import ChiakiFeatures

private let account = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

@MainActor @Test func theScanIsAskedForOnlyWhileTheAutomaticModeShows() async {
    let store = TestStore(initialState: AddConsoleFeature.State(
        account: account, modes: [.automatic, .manual]
    )) {
        AddConsoleFeature()
    }
    await store.send(.view(.appeared))
    await store.receive(.delegate(.startScanning))
    await store.send(.view(.selectMode(.manual))) {
        $0.mode = .manual
    }
    await store.receive(.delegate(.stopScanning))
    await store.send(.view(.selectMode(.playStation)))
    await store.send(.view(.disappeared))
    await store.receive(.delegate(.stopScanning))
}

@MainActor @Test func onlyAValidTypedAddressIsPaired() async {
    let store = TestStore(initialState: AddConsoleFeature.State(account: account, modes: [.manual])) {
        AddConsoleFeature()
    }
    await store.send(.binding(.set(\.address, "two words"))) {
        $0.address = "two words"
    }
    await store.send(.view(.submitAddress))
    await store.send(.binding(.set(\.address, "192.0.2.8"))) {
        $0.address = "192.0.2.8"
    }
    await store.send(.binding(.set(\.kind, .ps4))) {
        $0.kind = .ps4
    }
    await store.send(.view(.submitAddress))
    await store.receive(.delegate(.pair(.init(address: "192.0.2.8", kind: .ps4))))
}

@MainActor @Test func aConsolePickedFromThePlayStationListIsPaired() async {
    let remote = PSNConsole(
        deviceID: Data(repeating: 3, count: 32), name: "Den", ps5: true, remotePlayEnabled: true
    )
    let store = TestStore(initialState: AddConsoleFeature.State(
        account: account, modes: [.automatic, .playStation], preferred: .playStation
    )) {
        AddConsoleFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.consoles.accountConsoles = { _, _ in
            [remote]
        }
    }
    await store.send(.view(.appeared)) {
        $0.accountConsoles = AccountConsolesFeature.State(accountID: account)
    }
    await store.receive(\.accountConsoles.presented.load) {
        $0.accountConsoles?.phase = .loading(OperationID(uuid: UUID(0)))
    }
    await store.receive(\.accountConsoles.presented.loaded) {
        $0.accountConsoles?.phase = .ready
        $0.accountConsoles?.consoles = [remote]
    }
    await store.send(.accountConsoles(.presented(.view(.select(remote)))))
    let target = RegistrationFlow.ConsoleTarget(address: "Den", kind: .ps5, remoteDeviceID: remote.deviceID)
    await store.receive(\.accountConsoles.presented.delegate.selected)
    await store.receive(.delegate(.pair(target)))
}

@Test func discoveredConsolesAlreadyPairedAreLeftOut() {
    let paired = RegistrationFlow.ConsoleTarget(
        address: "192.0.2.4",
        kind: .ps5,
        hardwareID: "AA:BB:CC:DD:EE:FF"
    )
    let state = AddConsoleFeature.State(account: account, modes: [.automatic], registered: [paired])
    let known = DiscoveredConsole(
        id: "aabbccddeeff",
        name: "Den",
        address: "192.0.2.9",
        kind: .ps5,
        standby: false
    )
    let fresh = DiscoveredConsole(
        id: "112233445566",
        name: "Loft",
        address: "192.0.2.4",
        kind: .ps5,
        standby: true
    )
    let snapshot = DiscoverySnapshot(consoles: [known, fresh], networkAvailable: true)
    #expect(state.unpaired(in: snapshot) == [fresh])
}
