import ChiakiModels
import DesignSystem
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func onScreenTouchpadFollowsThePlatformDefaultForSavedSettingsWithoutIt() throws {
    let platformDefault = ControlsConfiguration.onScreenTouchpadDefault
    #expect(platformDefault == ScreenLayout.touchPlatform)
    #expect(ControlsConfiguration().onScreenTouchpad == platformDefault)
    var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ControlsConfiguration()))
        as? [String: Any] ?? [:]
    saved.removeValue(forKey: "onScreenTouchpad")
    let legacy = try JSONDecoder().decode(
        ControlsConfiguration.self,
        from: JSONSerialization.data(withJSONObject: saved)
    )
    #expect(legacy.onScreenTouchpad == platformDefault)
    var chosen = ControlsConfiguration()
    chosen.onScreenTouchpad = !platformDefault
    let decoded = try JSONDecoder().decode(ControlsConfiguration.self, from: JSONEncoder().encode(chosen))
    #expect(decoded.onScreenTouchpad == !platformDefault)
}

@MainActor @Test func aDisabledTouchpadIgnoresEveryWayOfShowingIt() {
    let touchpad = VirtualTouchpadModel(surface: .ps5, logger: .disabled, enabled: false)
    touchpad.toggle()
    touchpad.reveal()
    touchpad.pin()
    #expect(!touchpad.pad.isShown)
}

@MainActor @Test func disablingTheTouchpadHidesItAndEnablingItLetsItShowAgain() {
    let touchpad = VirtualTouchpadModel(surface: .ps5, logger: .disabled)
    touchpad.pin()
    #expect(touchpad.pad.isShown)
    touchpad.enable(false)
    #expect(!touchpad.pad.isShown)
    touchpad.toggle()
    #expect(!touchpad.pad.isShown)
    touchpad.enable(true)
    touchpad.toggle()
    #expect(touchpad.pad.isShown)
}
