import ChiakiModels
import Testing
@testable import ChiakiNG

@Suite struct PlayerOneControllerTests {
    private func pad(_ id: UInt32, key: String) -> ControllerDevice {
        ControllerDevice(
            id: id, preferenceKey: key, name: "Pad \(id)", transport: "USB",
            individual: true, rumble: true, lights: true, motion: true, touchpad: true,
            adaptiveTriggers: true
        )
    }

    @Test func theFirstControllerBecomesPlayerOneWhenNoneWasSaved() {
        var playerOne = PlayerOneController(primaryKey: nil)
        let alone = playerOne.choose(from: [])
        #expect(alone == .unchanged)
        #expect(playerOne.preferredKey == ControlsConfiguration.keyboardOnlyKey)
        let first = pad(1, key: "one")
        let connected = playerOne.choose(from: [first, pad(2, key: "two")])
        #expect(connected == .changed(first))
        playerOne.adopt(first, configuration: ControlsConfiguration())
        #expect(playerOne.preferredKey == "one")
        let reordered = playerOne.choose(from: [pad(2, key: "two"), first])
        #expect(reordered == .unchanged)
    }

    @Test func theKeyboardPreferenceLeavesPlayerOneWithoutAController() {
        var playerOne = PlayerOneController(primaryKey: nil)
        let preferred = playerOne.prefer(.keyboard, seated: false)
        #expect(preferred)
        let choice = playerOne.choose(from: [pad(1, key: "one")])
        #expect(choice == .unchanged)
        #expect(playerOne.device == nil)
    }

    @Test func aSeatedControllerCannotBecomePlayerOne() {
        var playerOne = PlayerOneController(primaryKey: "one")
        let refused = playerOne.prefer(pad(2, key: "two"), seated: true)
        #expect(!refused)
        let accepted = playerOne.prefer(pad(2, key: "two"), seated: false)
        #expect(accepted)
        let choice = playerOne.choose(from: [pad(1, key: "one"), pad(2, key: "two")])
        #expect(choice == .changed(pad(2, key: "two")))
    }

    @Test func reloadingKeepsThePreviousPreferencesForComparison() {
        var configuration = ControlsConfiguration()
        var saved = ControllerPreferences()
        saved.hapticStrength = 0.4
        configuration.controllers["one"] = saved
        var playerOne = PlayerOneController(primaryKey: "one")
        playerOne.adopt(pad(1, key: "one"), configuration: ControlsConfiguration())
        let previous = playerOne.reload(configuration)
        #expect(previous == ControllerPreferences())
        #expect(playerOne.preferences.hapticStrength == 0.4)
        playerOne.disconnect()
        #expect(playerOne.device == nil)
        #expect(playerOne.preferences.hapticStrength == 0.4)
    }

    @Test func theMicrophoneButtonBelongsToTheStreamUnlessABindingUsesIt() {
        var playerOne = PlayerOneController(primaryKey: "one")
        playerOne.adopt(pad(1, key: "one"), configuration: ControlsConfiguration())
        #expect(!playerOne.ownsMicrophoneButton(in: ControlsConfiguration(), microphone: false))
        #expect(playerOne.ownsMicrophoneButton(in: ControlsConfiguration(), microphone: true))
    }
}
