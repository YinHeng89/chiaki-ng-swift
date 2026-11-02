@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing
import ComposableArchitecture

private let lightGuest = ControllerDevice(
    id: 9, preferenceKey: "unit:9", name: "DualShock 4", transport: "USB", individual: true,
    rumble: true, lights: true, motion: true, touchpad: true
)

@MainActor @Test func seatLightBarsFollowTheSameOverrideAsTheController() async {
    var initial = CouchReducer.State()
    initial.begin(.ps4, hostAccount: nil)
    _ = initial.seats.claim(lightGuest)
    _ = initial.seats.apply(.confirmed(pad: 1, color: 0xff5f57))
    let commands = LockIsolated<[CouchCommand]>([])
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
        $0.streamSession.runCouchCommand = { command in
            commands.withValue {
                $0.append(command)
            }
            return true
        }
    }
    store.exhaustivity = .off
    #expect(store.state.lightColor(for: 1) == 0xff5f57)
    #expect(store.state.lightColor(for: 0) == nil)
    await store.send(.lightsChanged(CouchLights(
        lightbars: ControllerLightbars(controllers: [lightGuest.preferenceKey: .fixed(rgb: 0x20d040)]),
        revision: 1
    )))
    #expect(store.state.lightColor(for: 1) == 0x20d040)
    #expect(store.state.lightColor(for: 2) == nil)
    await store.send(.lightsChanged(CouchLights(
        lightbars: ControllerLightbars(global: .fixed(rgb: 0x0050ff)),
        playerOne: 0x123456,
        revision: 2
    )))
    #expect(store.state.lightColor(for: 1) == 0x0050ff)
    #expect(store.state.lightColor(for: 0) == 0x123456)
    await store.send(.lightsChanged(CouchLights(revision: 1)))
    #expect(store.state.lightColor(for: 0) == 0x123456)
    await store.send(.lightsChanged(CouchLights(playerOne: 0, revision: 3)))
    #expect(store.state.lightColor(for: 1) == 0xff5f57)
    #expect(store.state.lightColor(for: 0) == 0)
    #expect(store.state.lightBar(for: 0) != nil)
    #expect(store.state.seats[1] == .ready(CouchPlayer(device: lightGuest), color: 0xff5f57))
    await store.finish()
    #expect(commands.value.isEmpty)
}

@MainActor @Test func lightEventsAreIgnoredOnceTheCouchHasEnded() async {
    var initial = CouchReducer.State()
    initial.begin(.ps5, hostAccount: nil)
    initial.end()
    let store = TestStore(initialState: initial) {
        CouchReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ImmediateClock()
    }
    await store.send(.lightsChanged(CouchLights(playerOne: 0x123456, revision: 1)))
    #expect(store.state.lightColor(for: 0) == nil)
}
