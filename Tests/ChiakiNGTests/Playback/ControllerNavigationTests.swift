import ChiakiModels
import PlatformUI
import Testing
@testable import ChiakiFeatures
@testable import ChiakiNG
import DesignSystem
import Foundation
#if canImport(AppKit)
    import AppKit
#else
    import UIKit
#endif

@Test func controllerNavigationRepeatsDirectionsButNeverConfirmation() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(state.button(12, down: true, now: 0) == [.down])
    #expect(state.button(12, down: true, now: 0.1).isEmpty)
    #expect(state.repeatCommand(now: 0.29) == nil)
    #expect(state.repeatCommand(now: 0.3) == .down)
    #expect(state.repeatCommand(now: 0.31) == nil)
    #expect(state.repeatCommand(now: 0.4) == .down)
    _ = state.button(12, down: false, now: 0.5)
    #expect(state.repeatCommand(now: 1) == nil)
    #expect(state.button(0, down: true, now: 1) == [.confirm])
    #expect(state.repeatCommand(now: 5) == nil)
}

@Test func controllerNavigationQuarantinesHeldInputAcrossRoutes() {
    var state = ControllerNavigationState()
    state.setRoute(.stream)
    _ = state.button(0, down: true, now: 0)
    _ = state.axis(0, value: 30000, now: 0)
    _ = state.axis(4, value: 30000, now: 0)
    state.setRoute(.menu)
    #expect(state.button(0, down: true, now: 1).isEmpty)
    #expect(state.axis(0, value: 31000, now: 1).isEmpty)
    state.setRoute(.stream)
    #expect(!state.permitsStreamButton(0))
    #expect(!state.permitsStreamAxis(0))
    #expect(!state.permitsStreamAxis(4))
    _ = state.button(0, down: false, now: 2)
    _ = state.axis(0, value: 0, now: 2)
    _ = state.axis(4, value: 0, now: 2)
    #expect(state.permitsStreamButton(0))
    #expect(state.permitsStreamAxis(0))
    #expect(state.permitsStreamAxis(4))
}

@Test func controllerNavigationChordFiresOnceAndDoesNotLeakOnResume() {
    var state = ControllerNavigationState()
    state.setRoute(.stream)
    #expect(state.button(7, down: true, now: 0).isEmpty)
    #expect(state.button(8, down: true, now: 0) == [.streamMenu])
    state.setRoute(.menu)
    _ = state.button(7, down: false, now: 0.5)
    _ = state.button(8, down: false, now: 0.5)
    #expect(state.button(7, down: true, now: 1).isEmpty)
    #expect(state.button(8, down: true, now: 1) == [.streamMenu])
    #expect(state.button(8, down: true, now: 1).isEmpty)
    #expect(state.repeatCommand(now: 1) == nil)
    state.setRoute(.stream)
    #expect(!state.permitsStreamButton(7))
    #expect(!state.permitsStreamButton(8))
    _ = state.button(7, down: false, now: 2)
    _ = state.button(8, down: false, now: 2)
    #expect(state.permitsStreamButton(7))
    #expect(state.permitsStreamButton(8))
}

@Test func controllerNavigationRequiresStickNeutralAndHandlesReversal() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(state.axis(1, value: 21000, now: 0) == [.down])
    #expect(state.axis(1, value: 22000, now: 0.1).isEmpty)
    #expect(state.axis(1, value: -25000, now: 0.2) == [.up])
    _ = state.axis(1, value: 7000, now: 0.3)
    #expect(state.repeatCommand(now: 1) == nil)
    #expect(state.axis(9, value: 30000, now: 1).isEmpty)
    #expect(state.axis(3, value: 30000, now: 1).isEmpty)
}

@Test func controllerNavigationFocusLossCancelsRepeatAndHeldActions() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    _ = state.button(14, down: true, now: 0)
    state.setRoute(.inactive)
    #expect(state.repeatCommand(now: 2) == nil)
    #expect(state.button(0, down: true, now: 2).isEmpty)
    state.setRoute(.menu)
    #expect(state.button(0, down: true, now: 3).isEmpty)
    #expect(state.repeatCommand(now: 4) == nil)
    _ = state.button(0, down: false, now: 4)
    #expect(state.button(0, down: true, now: 5) == [.confirm])
}

@Test func controllerNavigationResetDropsDisconnectedDeviceState() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    _ = state.button(11, down: true, now: 0)
    state.reset()
    #expect(state.route == .inactive)
    #expect(state.repeatCommand(now: 2) == nil)
    state.setRoute(.menu)
    #expect(state.button(11, down: true, now: 3) == [.up])
}

@Test func controllerNavigationStickHysteresisRejectsThresholdJitter() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(state.axis(0, value: 21000, now: 0) == [.right])
    #expect(state.axis(0, value: 19000, now: 0.1).isEmpty)
    #expect(state.axis(0, value: 21000, now: 0.2).isEmpty)
    #expect(state.repeatCommand(now: 0.3) == .right)
    _ = state.axis(1, value: 0, now: 0.35)
    #expect(state.repeatCommand(now: 0.4) == .right)
    _ = state.axis(0, value: 0, now: 0.5)
    #expect(state.repeatCommand(now: 1) == nil)
    #expect(state.axis(0, value: -21000, now: 2) == [.left])
}

@Test func controllerShouldersChangeTabsInsteadOfStickHorizontalMovement() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(state.button(9, down: true, now: 0) == [.previous])
    _ = state.button(9, down: false, now: 0.1)
    #expect(state.button(10, down: true, now: 0.2) == [.next])
    #expect(state.axis(0, value: -30000, now: 0.3) == [.left])
}

@Test func controllerDpadUsesSDL3RightAndLeftButtonCodes() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(state.button(14, down: true, now: 0) == [.right])
    _ = state.button(14, down: false, now: 0.1)
    #expect(state.button(13, down: true, now: 0.2) == [.left])
}

@Test func controllerToolbarShortcutDoesNotRepeatOrInterceptStreaming() {
    var state = ControllerNavigationState()
    state.setRoute(.stream)
    #expect(state.button(3, down: true, now: 0).isEmpty)
    #expect(state.permitsStreamButton(3))
    state.setRoute(.menu)
    #expect(state.button(3, down: true, now: 1).isEmpty)
    _ = state.button(3, down: false, now: 2)
    #expect(state.button(3, down: true, now: 3) == [.focusToolbar])
    #expect(state.repeatCommand(now: 4) == nil)
}

@Test func controllerOptionsRemainsStreamInputAndOpensSettingsInMenus() {
    var state = ControllerNavigationState()
    state.setRoute(.stream)
    #expect(state.button(4, down: true, now: 0).isEmpty)
    #expect(state.permitsStreamButton(4))
    #expect(state.button(6, down: true, now: 0).isEmpty)
    #expect(state.permitsStreamButton(6))
    _ = state.button(6, down: false, now: 0.5)
    state.setRoute(.menu)
    #expect(state.button(6, down: true, now: 1) == [.settings])
    #expect(state.repeatCommand(now: 2) == nil)
}

@MainActor @Test func keyboardBindingsForShouldersChangeTabs() {
    let configuration = ControlsConfiguration()
    #expect(SDLInputCoordinator.keyboardTabCommand(for: 19, configuration: configuration) == .previous)
    #expect(SDLInputCoordinator.keyboardTabCommand(for: 20, configuration: configuration) == .next)
    #expect(SDLInputCoordinator.keyboardTabCommand(for: 18, configuration: configuration) == nil)
}

@Test func controllerNavigationUnrelatedReleaseDoesNotCancelRepeat() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    _ = state.button(11, down: true, now: 0)
    _ = state.button(12, down: true, now: 0.1)
    _ = state.button(11, down: false, now: 0.2)
    #expect(state.repeatCommand(now: 0.5) == .down)
    _ = state.button(0, down: true, now: 0.6)
    #expect(state.repeatCommand(now: 1) == nil)
}

@Test func controllerSquareIsAnAlternateMenuCommandAndStaysStreamInput() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(state.button(2, down: true, now: 0) == [.alternate])
    #expect(state.repeatCommand(now: 1) == nil)
    _ = state.button(2, down: false, now: 1)
    state.setRoute(.stream)
    #expect(state.button(2, down: true, now: 2).isEmpty)
    #expect(state.permitsStreamButton(2))
}

@Test func buttonCaptureAssignsOnQuickReleaseAndCancelsOnHold() {
    var capture = ControllerButtonCaptureState()
    #expect(capture.button(0, down: false, now: 0) == (false, nil))
    #expect(capture.button(3, down: true, now: 1) == (true, nil))
    #expect(capture.button(1, down: true, now: 1.1) == (true, nil))
    #expect(capture.button(1, down: false, now: 1.2) == (false, nil))
    #expect(capture.expire(now: 1.5) == nil)
    #expect(capture.button(3, down: false, now: 1.6) == (true, .assign(3)))
    #expect(capture.button(4, down: true, now: 2) == (false, nil))

    var held = ControllerButtonCaptureState()
    _ = held.button(1, down: true, now: 0)
    #expect(held.expire(now: ControllerButtonCaptureState.holdToCancel) == .cancel)
    #expect(held.button(1, down: false, now: 2) == (false, nil))
    #expect(held.expire(now: 3) == nil)

    var late = ControllerButtonCaptureState()
    _ = late.button(5, down: true, now: 0)
    #expect(late.button(5, down: false, now: 1.5) == (true, .cancel))
}

@MainActor
@Test func controllerGlyphsFollowTheControllerFamily() {
    #expect(ControllerGlyphs.button(.south, family: .playStation).symbol == "xmark.circle")
    #expect(String(localized: ControllerGlyphs.button(.south, family: .playStation).name) == "Cross")
    #expect(ControllerGlyphs.button(.south, family: .xbox).symbol == "a.circle")
    #expect(String(localized: ControllerGlyphs.button(.south, family: .xbox).name) == "A")
    #expect(String(localized: ControllerGlyphs.button(.south, family: .nintendo).name) == "B")
    #expect(String(localized: ControllerGlyphs.button(.east, family: .nintendo).name) == "A")
    #expect(String(localized: ControllerGlyphs.button(.north, family: .generic).name) == "North")
    #expect(String(localized: ControllerGlyphs.button(9, family: .xbox).name) == "LB")
    #expect(ControllerGlyphs.button(11, family: .xbox) == ControllerGlyphs.button(11, family: .playStation))
    #expect(String(localized: ControllerGlyphs.button(24, family: .playStation).name) == "Misc 5")
    #expect(String(localized: ControllerGlyphs.button(30, family: .xbox).name) == "Button 31")
    for code in 15...25 {
        #expect(String(localized: ControllerGlyphs.button(code, family: .generic).name)
            == String(localized: BindingRow.buttonName(code)))
    }
}

@Test func consoleActionGlyphsStayPlayStation() {
    #expect(String(localized: ControllerGlyphs.action(.cross).name) == "Cross")
    #expect(ControllerGlyphs.action(.system).symbol == "house.circle")
    #expect(String(localized: ControllerGlyphs.action(.leftTrigger).name) == "L2")
    #expect(ControllerGlyphs.action(.leftStickUp).symbol == nil)
    #expect(String(localized: ControllerGlyphs.action(.leftStickUp).name) == "Left stick up")
}

@MainActor @Test func controllerGlyphSymbolsExist() {
    for family in [ControllerFamily.playStation, .xbox, .nintendo, .generic] {
        for code in 0..<ControllerGlyphs.buttonCount {
            if let symbol = ControllerGlyphs.button(code, family: family).symbol {
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
            }
        }
    }
    for control in PlayStationControl.allCases {
        if let symbol = ControllerGlyphs.action(control).symbol {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
    }
}

@MainActor
@Test func buttonCaptureEndsWhenItsControllerIsReplacedOrRemoved() {
    #expect(ControlsSettingsView.capturedDeviceLeft(previous: 1, current: 2))
    #expect(ControlsSettingsView.capturedDeviceLeft(previous: 1, current: nil))
    #expect(!ControlsSettingsView.capturedDeviceLeft(previous: 1, current: 1))
    #expect(!ControlsSettingsView.capturedDeviceLeft(previous: nil, current: 2))
}

@MainActor @Test func keyboardShoulderBindingsNeverTakeOverMenuNavigationKeys() {
    var configuration = ControlsConfiguration()
    configuration.presets[0].bindings.removeAll {
        $0.source == .macKey && ($0.target == .leftShoulder || $0.target == .rightShoulder)
    }
    configuration.presets[0].bindings += [
        InputBinding(source: .macKey, code: 49, label: "Space", target: .leftShoulder),
        InputBinding(source: .macKey, code: 36, label: "Return", target: .rightShoulder)
    ]
    for code in SDLInputCoordinator.menuNavigationKeyCodes {
        #expect(SDLInputCoordinator.keyboardTabCommand(for: code, configuration: configuration) == nil)
    }
}

@Test func triggersCommitAndShiftOncePerPullOnlyInMenus() {
    var state = ControllerNavigationState()
    state.setRoute(.stream)
    #expect(state.axis(5, value: 32767, now: 0).isEmpty)
    #expect(state.permitsStreamAxis(5))
    state.setRoute(.menu)
    #expect(state.axis(5, value: 32767, now: 1).isEmpty)
    _ = state.axis(5, value: 0, now: 2)
    #expect(state.axis(5, value: 15000, now: 3).isEmpty)
    #expect(state.axis(5, value: 32767, now: 4) == [.commit])
    #expect(state.axis(5, value: 30000, now: 5).isEmpty)
    #expect(state.repeatCommand(now: 6) == nil)
    _ = state.axis(5, value: 0, now: 7)
    #expect(state.axis(5, value: 32767, now: 8) == [.commit])
    #expect(state.axis(4, value: 32767, now: 9) == [.shift])
    #expect(state.axis(4, value: 32767, now: 10).isEmpty)
}

@Test func switchingMenuControllersKeepsTheRouteSoTheFirstPressCounts() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    _ = state.button(12, down: true, now: 0)
    state.switchController()
    #expect(state.route == .menu)
    #expect(state.repeatCommand(now: 1) == nil)
    #expect(state.axis(1, value: 30000, now: 1) == [.down])
    #expect(state.button(11, down: true, now: 2) == [.up])
}

@Test func thePSButtonHandsTheControllerToTheConsoleFromTheMenuOnlyWhileAllowed() {
    var state = ControllerNavigationState()
    state.setRoute(.menu)
    #expect(!state.handsControllerToStream(ControllerNavigationState.systemButton, down: true))
    state.systemButtonReachesStream = true
    #expect(state.handsControllerToStream(ControllerNavigationState.systemButton, down: true))
    #expect(!state.handsControllerToStream(ControllerNavigationState.systemButton, down: false))
    #expect(!state.handsControllerToStream(0, down: true))
    #expect(!state.permitsStreamButton(ControllerNavigationState.systemButton))
    state.systemButtonOpensStreamMenu = true
    #expect(!state.handsControllerToStream(ControllerNavigationState.systemButton, down: true))
    state.systemButtonOpensStreamMenu = false
    state.setRoute(.stream)
    #expect(!state.handsControllerToStream(ControllerNavigationState.systemButton, down: true))
}
