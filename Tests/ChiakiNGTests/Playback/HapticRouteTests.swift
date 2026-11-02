import ChiakiModels
import Testing
import Video
@testable import ChiakiNG

private func dualSense(transport: String, waveform: Bool) -> ControllerDevice {
    ControllerDevice(
        id: 7, preferenceKey: "unit:7", name: "DualSense Wireless Controller", transport: transport,
        individual: true, rumble: true, lights: true, motion: true, touchpad: true,
        waveform: waveform, adaptiveTriggers: true
    )
}

@MainActor @Test func wiredDualSensePrefersUSBAudioAndWirelessPrefersBluetoothReports() {
    #expect(HapticRouter.preferredRoute(for: dualSense(transport: "USB", waveform: false)) == .usbAudio)
    #expect(HapticRouter.preferredRoute(for: dualSense(transport: "Wireless", waveform: true))
        == .bluetoothReports)
    #expect(HapticRouter.preferredRoute(for: dualSense(transport: "Wireless", waveform: false))
        == .coreHaptics)
}

@MainActor @Test func rumbleRouteIsNotNativeHaptics() {
    #expect(HapticRouter.isNative(.usbAudio))
    #expect(HapticRouter.isNative(.bluetoothReports))
    #expect(HapticRouter.isNative(.coreHaptics))
    #expect(!HapticRouter.isNative(.rumble))
    #expect(!HapticRouter.isNative(.none))
    #expect(HapticRouter.describe(.rumble) == "the rumble motors")
}

@Test func bluetoothHapticsHandOverToConsoleRumbleWhileItPlays() {
    #expect(WaveformHandoff.haptics.sending(RumbleLevel(low: 1, high: 0)) == .consoleRumble)
    #expect(WaveformHandoff.consoleRumble.sending(RumbleLevel(low: 0, high: 40000)) == .consoleRumble)
    #expect(WaveformHandoff.consoleRumble.sending(.off) == .haptics)
    #expect(WaveformHandoff.haptics.sending(.off) == .haptics)
}

@Test func onlyControllersWithoutTheIntensityByteAreScaledInSoftware() {
    let weak = ConsoleFeedbackIntensity(haptic: 3, trigger: 1)
    let xbox = ControllerDevice(
        id: 4, preferenceKey: "unit:4", name: "Xbox Wireless Controller", transport: "Wireless",
        individual: true, rumble: true, lights: false, motion: false, touchpad: false, family: .xbox
    )
    #expect(weak.softwareScale(for: dualSense(transport: "USB", waveform: false)) == 1)
    #expect(abs(weak.softwareScale(for: xbox) - 0.33) < 0.0001)
    #expect(ConsoleFeedbackIntensity(haptic: 0, trigger: 1).softwareScale(for: xbox) == 0)
    #expect(ConsoleFeedbackIntensity(haptic: 2, trigger: 1).softwareScale(for: xbox) == 0.5)
}
