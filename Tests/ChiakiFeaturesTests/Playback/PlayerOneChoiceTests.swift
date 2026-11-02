import ChiakiModels
import Testing
@testable import ChiakiFeatures

private func pad(_ id: UInt32, key: String) -> ControllerDevice {
    ControllerDevice(
        id: id, preferenceKey: key, name: "Pad \(id)", transport: "USB", individual: true,
        rumble: true, lights: false, motion: false, touchpad: false
    )
}

@Test func theSavedControllerIsPlayerOneWhenNothingElseIsPlaying() {
    let saved = pad(1, key: "saved")
    let other = pad(2, key: "other")
    #expect(PlayerOneChoice
        .choose(from: [other, saved], current: nil, primaryKey: "saved", adopting: nil) == saved)
}

@Test func aStandInKeepsPlayerOneWhenTheSavedControllerConnects() {
    let standIn = pad(2, key: "other")
    let saved = pad(3, key: "saved")
    let choice = PlayerOneChoice.choose(
        from: [saved, standIn],
        current: 2,
        primaryKey: "saved",
        adopting: nil
    )
    #expect(choice == standIn)
}

@Test func choosingPlayerOneHandsItToTheSavedController() {
    let standIn = pad(2, key: "other")
    let saved = pad(3, key: "saved")
    let choice = PlayerOneChoice.choose(from: [standIn, saved], current: 2, primaryKey: "saved", adopting: 3)
    #expect(choice == saved)
}

@Test func theSavedControllerTakesOverWhenTheStandInLeaves() {
    let saved = pad(3, key: "saved")
    #expect(PlayerOneChoice.choose(from: [saved], current: 2, primaryKey: "saved", adopting: nil) == saved)
}

@Test func theSameControllerSwitchingTransportStaysPlayerOne() {
    let bluetooth = pad(4, key: "saved")
    let usb = pad(5, key: "saved")
    let choice = PlayerOneChoice.choose(
        from: [usb, bluetooth],
        current: 4,
        primaryKey: "saved",
        adopting: nil
    )
    #expect(choice?.preferenceKey == "saved")
}

@Test func aStandInIsNotSwappedForAnotherStandIn() {
    let first = pad(6, key: "a")
    let current = pad(7, key: "b")
    #expect(PlayerOneChoice
        .choose(from: [first, current], current: 7, primaryKey: "saved", adopting: nil) == current)
}

@Test func keyboardOnlyPlayerOneUsesNoController() {
    let other = pad(8, key: "other")
    let choice = PlayerOneChoice.choose(
        from: [other], current: 8, primaryKey: ControlsConfiguration.keyboardOnlyKey, adopting: nil
    )
    #expect(choice == nil)
}
