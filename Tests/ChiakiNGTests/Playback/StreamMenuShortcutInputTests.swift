import ChiakiModels
import CInput
import Testing
@testable import ChiakiFeatures
@testable import ChiakiNG

@Test func aCustomStreamMenuShortcutOpensTheMenuAndBothStickClicksNoLongerDo() {
    var state = ControllerNavigationState()
    state.streamMenuChord = [9, 10]
    state.setRoute(.stream)
    _ = state.button(7, down: true, now: 0)
    #expect(state.button(8, down: true, now: 0).isEmpty)
    _ = state.button(7, down: false, now: 0)
    _ = state.button(8, down: false, now: 0)
    _ = state.button(9, down: true, now: 1)
    #expect(state.button(10, down: true, now: 1) == [.streamMenu])
    state.switchController()
    #expect(state.streamMenuChord == [9, 10])
}

@Test func playerOnesLaneHoldsBackTheCustomStreamMenuShortcut() {
    var lane = GameInputLane(GameInputLane.Assignment(
        device: 1, name: "Pad", preset: .standard, preferences: ControllerPreferences(), chord: nil,
        ownsMicrophone: false, blocksStreamMenuChord: true, streamMenuChord: [9, 10]
    ))
    _ = lane.setLive(true)
    let press = { (code: Int32) in
        nx_input_event(
            instance: 1, kind: ControllerInputEvent.button, control: code, value: 1, data: (0, 0, 0),
            timestamp_us: 0
        )
    }
    _ = lane.apply(press(9))
    _ = lane.apply(press(10))
    let shoulders = (PlayStationControl.leftShoulder.bit ?? 0) | (PlayStationControl.rightShoulder.bit ?? 0)
    #expect(lane.state().buttons & shoulders == 0)
    _ = lane.apply(press(7))
    _ = lane.apply(press(8))
    let sticks = (PlayStationControl.leftStickButton.bit ?? 0) |
        (PlayStationControl.rightStickButton.bit ?? 0)
    #expect(lane.state().buttons & sticks == sticks)
}

@Test func theStreamMenuCardFillsClearsAndSwapsSlots() {
    #expect(StreamMenuShortcutCard.choosing(9, slot: 2, in: [7, 8]) == [7, 8, 9])
    #expect(StreamMenuShortcutCard.choosing(StreamMenuShortcutCard.unused, slot: 2, in: [7, 8, 9]) == [7, 8])
    #expect(StreamMenuShortcutCard.choosing(8, slot: 0, in: [7, 8]) == [8, 7])
    #expect(StreamMenuShortcutCard.choosing(10, slot: 1, in: [7, 8]) == [7, 10])
    #expect(StreamMenuShortcutCard.choosing(7, slot: 3, in: [7, 8]) == [7, 8])
}

@Test func thePSButtonOpensTheStreamMenuOnlyWhenACloudStreamAsksForIt() {
    var state = ControllerNavigationState()
    state.setRoute(.stream)
    #expect(state.button(ControllerNavigationState.systemButton, down: true, now: 0).isEmpty)
    _ = state.button(ControllerNavigationState.systemButton, down: false, now: 0)
    state.systemButtonOpensStreamMenu = true
    #expect(state.button(ControllerNavigationState.systemButton, down: true, now: 1) == [.streamMenu])
    #expect(state.button(ControllerNavigationState.systemButton, down: true, now: 1).isEmpty)
    _ = state.button(ControllerNavigationState.systemButton, down: false, now: 1)
    state.setRoute(.menu)
    #expect(state.button(ControllerNavigationState.systemButton, down: true, now: 2) == [.streamMenu])
    state.switchController()
    #expect(state.systemButtonOpensStreamMenu)
}

@Test func playerOnesLaneKeepsThePSButtonFromTheConsoleWhileItOpensTheStreamMenu() {
    let press = { (code: Int32, down: Bool) in
        nx_input_event(
            instance: 1, kind: ControllerInputEvent.button, control: code, value: down
                ? 1
                : 0,
            data: (0, 0, 0), timestamp_us: 0
        )
    }
    let psBit = PlayStationControl.system.bit ?? 0
    var passing = GameInputLane(GameInputLane.Assignment(
        device: 1, name: "Pad", preset: .standard, preferences: ControllerPreferences(), chord: nil,
        ownsMicrophone: false, blocksStreamMenuChord: true
    ))
    _ = passing.setLive(true)
    _ = passing.apply(press(GameInputLane.systemButton, true))
    #expect(passing.state().buttons & psBit == psBit)
    var blocking = GameInputLane(GameInputLane.Assignment(
        device: 1, name: "Pad", preset: .standard, preferences: ControllerPreferences(), chord: nil,
        ownsMicrophone: false, blocksStreamMenuChord: true, blocksSystemButton: true
    ))
    _ = blocking.setLive(true)
    #expect(blocking.apply(press(GameInputLane.systemButton, true)) == GameInputLane.Outcome())
    #expect(blocking.state().buttons & psBit == 0)
    _ = blocking.apply(press(GameInputLane.systemButton, false))
    #expect(blocking.state().buttons & psBit == 0)
}
