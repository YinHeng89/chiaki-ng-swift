import ChiakiModels
import Foundation
import Testing

private func controller(rumble: Bool, dualSense: Bool) -> ControllerDevice {
    ControllerDevice(
        id: 3, preferenceKey: "unit:3", name: "Controller", transport: "USB", individual: true,
        rumble: rumble, lights: false, motion: false, touchpad: false, adaptiveTriggers: dualSense,
        family: dualSense
            ? .playStation
            : .xbox
    )
}

@Test func automaticHapticsUseNativeOutputOnlyOnTheDualSense() {
    var preferences = ControllerPreferences()
    #expect(preferences.hapticOutput(for: controller(rumble: true, dualSense: true)) == .native)
    #expect(preferences.hapticOutput(for: controller(rumble: true, dualSense: false)) == .rumble)
    #expect(preferences.hapticOutput(for: controller(rumble: false, dualSense: false)) == .none)
    preferences.hapticFeedback = .rumble
    #expect(preferences.hapticOutput(for: controller(rumble: true, dualSense: true)) == .rumble)
    #expect(preferences.hapticOutput(for: controller(rumble: false, dualSense: false)) == .none)
    preferences.hapticFeedback = .off
    #expect(preferences.hapticOutput(for: controller(rumble: true, dualSense: true)) == .none)
    #expect(preferences.hapticOutput(for: controller(rumble: true, dualSense: false)) == .none)
}

@Test func rumbleLevelsScaleConsoleBytesAndHapticLevels() {
    #expect(RumbleLevel(left: 255, right: 128, strength: 1) == RumbleLevel(low: 65535, high: 32896))
    #expect(RumbleLevel(left: 200, right: 100, strength: 0.5) == RumbleLevel(low: 25700, high: 12850))
    #expect(RumbleLevel(left: 200, right: 100, strength: 3) == RumbleLevel(
        left: 200,
        right: 100,
        strength: 1
    ))
    #expect(RumbleLevel(left: 200, right: 100, strength: .nan) == .off)
    #expect(RumbleLevel(hapticLow: 1, hapticHigh: 0.5) == RumbleLevel(low: 65535, high: 32768))
    #expect(RumbleLevel(hapticLow: 4, hapticHigh: -1) == RumbleLevel(low: 65535, high: 0))
    #expect(RumbleLevel(hapticLow: .nan, hapticHigh: .infinity) == .off)
}

@Test func rumbleMixPlaysTheStrongerSourceOnEachMotor() {
    var mix = RumbleMix()
    #expect(mix.next(at: 0, strength: 1) == nil)
    mix.setConsole(left: 160, right: 4, at: 1)
    mix.setHaptics(RumbleLevel(low: 10000, high: 30000))
    #expect(mix.next(at: 1, strength: 1) == RumbleLevel(low: 41120, high: 30000))
    #expect(mix.output == .playing(RumbleLevel(low: 41120, high: 30000), sentAt: 1))
    mix.setHaptics(.off)
    #expect(mix.next(at: 1.01, strength: 1) == nil)
    #expect(mix.next(at: 1.04, strength: 1) == RumbleLevel(low: 41120, high: 1028))
    mix.setConsole(left: 0, right: 0, at: 1.05)
    #expect(mix.next(at: 1.05, strength: 1) == nil)
    #expect(mix.next(at: 1.08, strength: 1) == .off)
    #expect(mix.output == .idle)
    #expect(mix.next(at: 1.09, strength: 1) == nil)
}

@Test func rumbleMixAppliesStrengthChangesToHeldConsoleRumble() {
    var mix = RumbleMix()
    mix.setConsole(left: 200, right: 200, at: 0)
    #expect(mix.next(at: 0, strength: 1) == RumbleLevel(low: 51400, high: 51400))
    #expect(mix.next(at: 0.05, strength: 0.5) == RumbleLevel(low: 25700, high: 25700))
    #expect(mix.next(at: 0.09, strength: 0) == .off)
    #expect(mix.console(at: 1, strength: 0.5) == RumbleLevel(low: 25700, high: 25700))
}

@Test func heldConsoleRumbleStopsWhenTheConsoleGoesQuietTooLong() {
    var mix = RumbleMix()
    mix.setConsole(left: 255, right: 255, at: 100)
    #expect(mix.next(at: 100, strength: 1) == RumbleLevel(low: 65535, high: 65535))
    #expect(mix.next(at: 104.9, strength: 1) == RumbleLevel(low: 65535, high: 65535))
    #expect(mix.next(at: 105.2, strength: 1) == .off)
    #expect(mix.console(at: 99, strength: 1) == .off)
}

@Test func rumbleMixLimitsSendsAndKeepsTheMotorsAlive() {
    var mix = RumbleMix()
    mix.setHaptics(RumbleLevel(low: 20000, high: 20000))
    #expect(mix.next(at: 10, strength: 1) == RumbleLevel(low: 20000, high: 20000))
    mix.setHaptics(.off)
    #expect(mix.next(at: 10.004, strength: 1) == nil)
    mix.setHaptics(RumbleLevel(low: 30000, high: 20000))
    #expect(mix.next(at: 10.031, strength: 1) == RumbleLevel(low: 30000, high: 20000))
    mix.setHaptics(RumbleLevel(low: 30500, high: 20000))
    #expect(mix.next(at: 10.2, strength: 1) == nil)
    #expect(mix.next(at: 10.5, strength: 1) == RumbleLevel(low: 30500, high: 20000))
    #expect(mix.next(at: 5, strength: 1) == RumbleLevel(low: 30500, high: 20000))
    #expect(RumbleMix.refreshInterval * 1000 < Double(RumbleMix.durationMilliseconds))
}

@Test func silencingKeepsConsoleRumbleForWhenTheStreamResumes() {
    var mix = RumbleMix()
    mix.setConsole(left: 100, right: 0, at: 2)
    mix.setHaptics(RumbleLevel(low: 0, high: 30000))
    _ = mix.next(at: 2, strength: 1)
    mix.silence()
    #expect(mix.output == .idle)
    #expect(mix.haptics == .off)
    #expect(mix.next(at: 3, strength: 1) == RumbleLevel(low: 25700, high: 0))
    mix.setConsole(left: 0, right: 0, at: 4)
    #expect(mix.next(at: 4, strength: 1) == .off)
    #expect(mix.next(at: 5, strength: 1) == nil)
}

@Test func hdRumbleToneScalesEachSide() {
    let tone = HDRumbleTone(left: 0.8, right: 0.4)
    #expect(tone.scaled(by: 0.5) == HDRumbleTone(left: 0.4, right: 0.2))
    #expect(tone.scaled(by: .nan).isSilent)
    #expect(tone.scaled(by: 4) == tone)
    #expect(HDRumbleTone.silent.isSilent)
    #expect(!HDRumbleTone(left: 0, right: 0.1).isSilent)
}

@Test func hdRumblePacerLimitsWritesAndSendsSilenceOnce() {
    var pacer = HDRumblePacer()
    let tone = HDRumbleTone(left: 0.5, right: 0)
    #expect(pacer.next(.silent, at: 0, over: .usb) == nil)
    #expect(pacer.next(tone, at: 1, over: .usb) == tone)
    #expect(pacer.next(HDRumbleTone(left: 0.9, right: 0), at: 1.02, over: .usb) == nil)
    #expect(pacer.next(HDRumbleTone(left: 0.9, right: 0), at: 1.03, over: .usb) == HDRumbleTone(
        left: 0.9,
        right: 0
    ))
    #expect(pacer.next(.silent, at: 1.04, over: .usb) == nil)
    #expect(pacer.next(.silent, at: 1.07, over: .usb) == .silent)
    #expect(pacer.next(.silent, at: 1.2, over: .usb) == nil)
    #expect(!pacer.isPlaying)
}

@Test func hdRumblePacerSkipsUnchangedTonesUntilTheRefresh() {
    var pacer = HDRumblePacer()
    let tone = HDRumbleTone(left: 0.5, right: 0.2)
    #expect(pacer.next(tone, at: 0, over: .usb) == tone)
    #expect(pacer.next(HDRumbleTone(left: 0.51, right: 0.2), at: 0.031, over: .usb) == nil)
    #expect(pacer.next(HDRumbleTone(left: 0.51, right: 0.2), at: 0.045, over: .usb) != nil)
}

@Test func hdRumblePacerWaitsLongerBetweenBluetoothWrites() {
    var pacer = HDRumblePacer()
    #expect(pacer.next(HDRumbleTone(left: 0.2, right: 0), at: 0, over: .bluetooth) != nil)
    #expect(pacer.next(HDRumbleTone(left: 0.9, right: 0), at: 0.031, over: .bluetooth) == nil)
    #expect(pacer.next(HDRumbleTone(left: 0.9, right: 0), at: 0.045, over: .bluetooth) != nil)
}

@Test func hdRumblePacerStopSilencesOnlyWhilePlaying() {
    var pacer = HDRumblePacer()
    #expect(pacer.stop() == nil)
    let tone = HDRumbleTone(left: 1, right: 1)
    _ = pacer.next(tone, at: 0, over: .usb)
    #expect(pacer.stop() == .silent)
    #expect(pacer.stop() == nil)
}

@Test func triggerStrengthNeverRaisesTheConsoleIntensity() {
    #expect(TriggerStrength.strong.applied(toConsoleLevel: 1) == 1)
    #expect(TriggerStrength.medium.applied(toConsoleLevel: 1) == 2)
    #expect(TriggerStrength.weak.applied(toConsoleLevel: 2) == 3)
    #expect(TriggerStrength.strong.applied(toConsoleLevel: 3) == 3)
    #expect(TriggerStrength.medium.applied(toConsoleLevel: 3) == 3)
    for strength in TriggerStrength.allCases {
        #expect(strength.applied(toConsoleLevel: 0) == 0)
    }
}

@Test func savedControllerPreferencesWithoutTriggerStrengthStayStrong() throws {
    let json = Data("""
    {"nickname":"Original","deadZone":0.15,"invertRightY":false,"swapSticks":false,"rumbleStrength":0.8}
    """.utf8)
    var preferences = try JSONDecoder().decode(ControllerPreferences.self, from: json)
    #expect(preferences.triggerStrength == .strong)
    preferences.triggerStrength = .weak
    let decoded = try JSONDecoder().decode(
        ControllerPreferences.self,
        from: JSONEncoder().encode(preferences)
    )
    #expect(decoded.triggerStrength == .weak)
}
