import ChiakiModels
import Testing
@testable import ChiakiNG

@Suite struct InputFeedbackChoiceTests {
    private let dualSense = ControllerDevice(
        id: 1, preferenceKey: "one", name: "DualSense Wireless Controller", transport: "USB",
        individual: true, rumble: true, lights: true, motion: true, touchpad: true,
        waveform: true, adaptiveTriggers: true
    )

    private let xbox = ControllerDevice(
        id: 2, preferenceKey: "two", name: "Xbox Wireless Controller", transport: "Wireless",
        individual: true, rumble: true, lights: false, motion: false, touchpad: false, family: .xbox
    )

    @Test func rumbleIsScaledByTheConsoleOnlyForControllersThatCannotApplyIt() {
        var preferences = ControllerPreferences()
        preferences.rumbleStrength = 0.8
        let half = ConsoleFeedbackIntensity(haptic: 2, trigger: 1)
        #expect(RumbleDriver.strength(for: preferences, device: dualSense, console: half) == 0.8)
        #expect(RumbleDriver.strength(for: preferences, device: xbox, console: half) == 0.4)
        let silent = ConsoleFeedbackIntensity(haptic: 0, trigger: 1)
        #expect(RumbleDriver.strength(for: preferences, device: xbox, console: silent) == 0)
    }

    @Test func theStreamLightsPlayerOneAndEverySeatUntilItStops() {
        let seat = SeatedController(
            device: xbox,
            preferences: ControllerPreferences(),
            physicalTouchpad: PhysicalTouchpad(surface: .ps5)
        )
        let live = LightbarController.devices(playerOne: dualSense, seats: [2: seat], live: true)
        #expect(live == [0: dualSense, 2: xbox])
        #expect(LightbarController.devices(playerOne: nil, seats: [2: seat], live: true) == [2: xbox])
        #expect(LightbarController.devices(playerOne: dualSense, seats: [2: seat], live: false).isEmpty)
    }

    @Test func theShownLightbarsWinOverTheSavedOnes() {
        let saved = ControllerLightbars()
        let shown = ControllerLightbars(controllers: ["one": .fixed(rgb: 0x00ff00)])
        #expect(LightbarController.chosen(shown: shown, configured: saved) == shown)
        #expect(LightbarController.chosen(shown: nil, configured: saved) == saved)
    }

    @Test func motionIsSensedOnlyOnControllersThatReachTheStream() {
        #expect(MotionInput.wanted(playerOne: 1, active: true, seats: [2, 3], seatsActive: false) == [1])
        #expect(MotionInput.wanted(playerOne: 1, active: false, seats: [2, 3], seatsActive: true) == [2, 3])
        #expect(MotionInput.wanted(playerOne: nil, active: true, seats: [], seatsActive: true).isEmpty)
    }
}
