import ChiakiModels
import Foundation
import Testing

@Test func virtualGamepadStartsIdle() {
    let pad = VirtualGamepad()
    #expect(pad.isIdle)
    #expect(pad.state == ControllerState())
}

@Test func virtualGamepadButtonsSetAndClearTheirOwnBit() throws {
    var pad = VirtualGamepad()
    let cross = try #require(PlayStationControl.cross.bit)
    let options = try #require(PlayStationControl.options.bit)
    pad.press(.cross, down: true)
    pad.press(.options, down: true)
    #expect(pad.state.buttons == cross | options)
    #expect(pad.holds(.cross))
    pad.press(.cross, down: false)
    #expect(pad.state.buttons == options)
    #expect(!pad.holds(.cross))
}

@Test func virtualGamepadTriggersAreFullyPressedOrReleased() {
    var pad = VirtualGamepad()
    pad.press(.leftTrigger, down: true)
    #expect(pad.state.leftTrigger == .max)
    #expect(pad.state.rightTrigger == 0)
    #expect(pad.state.buttons == 0)
    pad.press(.rightTrigger, down: true)
    pad.press(.leftTrigger, down: false)
    #expect(pad.state.leftTrigger == 0)
    #expect(pad.state.rightTrigger == .max)
}

@Test func virtualGamepadSticksReachFullDeflectionOnEachAxis() {
    var pad = VirtualGamepad()
    pad.move(.left, x: 1, y: 0)
    #expect(pad.state.leftX == .max)
    #expect(pad.state.leftY == 0)
    pad.move(.right, x: 0, y: -1)
    #expect(pad.state.rightX == 0)
    #expect(pad.state.rightY == -Int16.max)
    #expect(pad.state.leftX == .max)
}

@Test func virtualGamepadSticksStayInsideTheUnitCircle() {
    var pad = VirtualGamepad()
    pad.move(.left, x: 3, y: 4)
    let length = (pow(Double(pad.state.leftX), 2) + pow(Double(pad.state.leftY), 2)).squareRoot()
    #expect(abs(length - Double(Int16.max)) < 2)
    #expect(pad.state.leftX > 0)
    #expect(pad.state.leftY > pad.state.leftX)
}

@Test func virtualGamepadIgnoresValuesThatAreNotNumbers() {
    var pad = VirtualGamepad()
    pad.move(.right, x: .nan, y: .infinity)
    #expect(pad.state.rightX == 0)
    #expect(pad.state.rightY == 0)
}

@Test func virtualGamepadReleasingAStickCentresOnlyThatStick() {
    var pad = VirtualGamepad()
    pad.move(.left, x: 0.5, y: 0.5)
    pad.move(.right, x: -0.5, y: 0.25)
    pad.release(.left)
    #expect(pad.state.leftX == 0)
    #expect(pad.state.leftY == 0)
    #expect(pad.state.rightX < 0)
    #expect(pad.state.rightY > 0)
}

@Test func virtualGamepadReleaseAllReturnsToIdle() {
    var pad = VirtualGamepad()
    pad.press(.triangle, down: true)
    pad.press(.rightTrigger, down: true)
    pad.move(.left, x: 1, y: -1)
    pad.releaseAll()
    #expect(pad.isIdle)
    #expect(!pad.holds(.triangle))
}

@Test func automaticPresenceShowsTheGamepadOnlyWithoutAController() {
    #expect(VirtualGamepadPresence.automatic.isVisible(controllerConnected: false))
    #expect(!VirtualGamepadPresence.automatic.isVisible(controllerConnected: true))
    #expect(VirtualGamepadPresence.shown.isVisible(controllerConnected: true))
    #expect(!VirtualGamepadPresence.hidden.isVisible(controllerConnected: false))
}

@Test func togglingPresenceFlipsWhatIsOnScreen() {
    #expect(VirtualGamepadPresence.automatic.toggled(controllerConnected: false) == .hidden)
    #expect(VirtualGamepadPresence.automatic.toggled(controllerConnected: true) == .shown)
    #expect(VirtualGamepadPresence.hidden.toggled(controllerConnected: true) == .shown)
    #expect(VirtualGamepadPresence.shown.toggled(controllerConnected: false) == .hidden)
}

@Test func virtualGamepadPresenceIsAutomaticUntilChosenAndSurvivesSaving() throws {
    let configuration = ControlsConfiguration()
    #expect(configuration.virtualGamepad == .automatic)
    var chosen = configuration
    chosen.virtualGamepad = .hidden
    let decoded = try JSONDecoder().decode(ControlsConfiguration.self, from: JSONEncoder().encode(chosen))
    #expect(decoded.virtualGamepad == .hidden)
    #expect(try decoded.validated() == decoded)
}

@Test func aConfigurationSavedBeforeTheVirtualGamepadChoiceDecodesAsAutomatic() throws {
    var saved = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(ControlsConfiguration())) as? [String: Any]
    )
    saved.removeValue(forKey: "virtualGamepad")
    let decoded = try JSONDecoder().decode(
        ControlsConfiguration.self,
        from: JSONSerialization.data(withJSONObject: saved)
    )
    #expect(decoded.virtualGamepad == .automatic)
}
