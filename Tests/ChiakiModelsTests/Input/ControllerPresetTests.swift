import ChiakiModels
import Foundation
import Testing

private func gamepad(_ preset: InputPreset, _ target: PlayStationControl) -> [Int] {
    preset.bindings.filter { $0.source == .gamepadButton && $0.target == target }.map(\.code)
}

@Test func standardAdaptsToControllersWithoutATouchpad() {
    let configuration = ControlsConfiguration()
    let dualSense = configuration.preset(for: nil, touchpad: true)
    #expect(dualSense == .standard)
    let xbox = configuration.preset(for: nil, touchpad: false)
    #expect(gamepad(xbox, .touchpad) == [4])
    #expect(gamepad(xbox, .share) == [15])
    #expect(gamepad(xbox, .cross) == [0])
    #expect(xbox.bindings.filter { $0.source == .macKey } == InputPreset.standard.bindings
        .filter { $0.source == .macKey })
}

@Test func aCustomisedPresetOnlyMovesTheTouchpadOffItsMissingButton() {
    var configuration = ControlsConfiguration()
    configuration.presets[0].bindings.removeAll { $0.target == .triangle && $0.source == .gamepadButton }
    let xbox = configuration.preset(for: nil, touchpad: false, gyro: false)
    #expect(gamepad(xbox, .share) == [4])
    #expect(gamepad(xbox, .touchpad) == [15])
    #expect(gamepad(xbox, .gyroHold).isEmpty)
    configuration.presets[0].bindings.removeAll { $0.target == .touchpad && $0.source == .gamepadButton }
    configuration.presets[0].bindings.append(InputBinding(source: .gamepadButton, code: 6, label: "",
                                                          target: .touchpad))
    #expect(gamepad(configuration.preset(for: nil, touchpad: false), .touchpad) == [6])
}

@Test func gyroHoldMayShareAButtonButNothingElseMay() throws {
    let xbox = InputPreset.standard.withoutTouchpad.withoutGyro
    var configuration = ControlsConfiguration()
    configuration.presets[0].bindings = xbox.bindings
    #expect(try configuration.validated() == configuration)
    configuration.presets[0].bindings.append(InputBinding(source: .gamepadButton, code: 8, label: "",
                                                          target: .cross))
    #expect(throws: InputFailure.duplicateBinding) {
        try configuration.validated()
    }
}

@Test func controllersWithoutGyroCanTakeTheirOwnPresetAndSaveIt() throws {
    var configuration = ControlsConfiguration()
    let step1 = configuration.givePreset(to: "xbox", named: "Xbox", touchpad: false, gyro: false)
    #expect(step1)
    #expect(try configuration.validated() == configuration)
}

@Test func assigningAnInputInUseSwapsTheTwoControls() {
    var preset = InputPreset.standard
    let result = preset.assign(InputBinding(source: .gamepadButton, code: 1, label: "", target: .cross))
    #expect(result.displaced == .circle)
    #expect(result.exchanged?.code == 0)
    #expect(gamepad(preset, .cross) == [1])
    #expect(gamepad(preset, .circle) == [0])
    let shared = preset.assign(InputBinding(source: .gamepadButton, code: 8, label: "", target: .gyroHold))
    #expect(shared.displaced == nil)
    #expect(gamepad(preset, .rightStickButton) == [8])
    #expect(gamepad(preset, .gyroHold) == [8])
}

@Test func playersOwnPresetWinsOverTheControllersAndCanBeRemoved() {
    var configuration = ControlsConfiguration()
    let step2 = configuration.givePreset(to: "pad", named: "Pad", touchpad: true)
    #expect(step2)
    let step3 = configuration.givePlayerPreset(1, named: "Player 2")
    #expect(step3)
    let player = configuration.playerPresets[1]
    let preferences = configuration.controllers["pad"]
    #expect(configuration.preset(forPlayer: 1, preferences: preferences, touchpad: true).id == player)
    #expect(configuration.preset(forPlayer: 2, preferences: preferences, touchpad: true).id
        == preferences?.presetID)
    configuration.removePlayerPreset(1)
    #expect(configuration.playerPresets[1] == nil)
    #expect(!configuration.presets.contains { $0.id == player })
}

@Test func rememberedControllersRoundTripAndForgettingRemovesTheirPreset() throws {
    var configuration = ControlsConfiguration()
    let pad = ControllerDevice(id: 2, preferenceKey: "pad", name: "Pad", transport: "USB", individual: true,
                               rumble: true, lights: false, motion: false, touchpad: false, family: .xbox)
    let step5 = configuration.remember([pad], previous: [], at: Date(timeIntervalSince1970: 10))
    #expect(step5)
    let step6 = configuration.remember([pad], previous: [pad], at: Date(timeIntervalSince1970: 20))
    #expect(!step6)
    let step7 = configuration.remember([], previous: [pad], at: Date(timeIntervalSince1970: 30))
    #expect(step7)
    #expect(configuration.remembered["pad"]?.lastSeen == Date(timeIntervalSince1970: 30))
    let step4 = configuration.givePreset(to: "pad", named: "Pad", touchpad: false, gyro: false)
    #expect(step4)
    configuration.selectedControllerKey = "pad"
    let decoded = try JSONDecoder().decode(
        ControlsConfiguration.self,
        from: JSONEncoder().encode(configuration)
    )
    #expect(decoded == configuration)
    configuration.forget("pad")
    #expect(configuration.remembered.isEmpty)
    #expect(configuration.controllers["pad"] == nil)
    #expect(configuration.presets.count == 1)
    #expect(configuration.selectedControllerKey == nil)
}

@Test func controllersGetTheirOwnPresetBeforeAnEditAndKeepIt() throws {
    var configuration = ControlsConfiguration()
    #expect(!configuration.ownsPreset("xbox"))
    let given1 = configuration.givePreset(to: "xbox", named: "Xbox Series X Controller", touchpad: false)
    #expect(given1)
    let id = try #require(configuration.controllers["xbox"]?.presetID)
    #expect(configuration.ownsPreset("xbox"))
    let owned = try #require(configuration.presets.first { $0.id == id })
    #expect(owned.name == "Xbox Series X Controller")
    #expect(gamepad(owned, .touchpad) == [4])
    let given2 = configuration.givePreset(to: "xbox", named: "Xbox Series X Controller", touchpad: false)
    #expect(given2)
    #expect(configuration.presets.count == 2)
    #expect(configuration.preset(for: nil, touchpad: true) == .standard)
    let given3 = configuration.givePreset(to: "second", named: "Xbox Series X Controller", touchpad: false)
    #expect(given3)
    let second = try #require(configuration.presets
        .first { $0.id == configuration.controllers["second"]?.presetID })
    #expect(second.name == "Xbox Series X Controller 2")
}

@Test func aPresetSharedByTwoControllersIsNotOwnedByEither() {
    var configuration = ControlsConfiguration()
    var shared = InputPreset.standard
    shared.id = UUID()
    shared.name = "Shared"
    configuration.presets.append(shared)
    var preferences = ControllerPreferences()
    preferences.presetID = shared.id
    configuration.controllers["a"] = preferences
    configuration.controllers["b"] = preferences
    #expect(!configuration.ownsPreset("a"))
    let given4 = configuration.givePreset(to: "a", named: "A", touchpad: true)
    #expect(given4)
    #expect(configuration.ownsPreset("a"))
    #expect(configuration.ownsPreset("b"))
}

@Test func forkingStopsAtThePresetLimit() {
    var configuration = ControlsConfiguration()
    for index in 1..<ControlsConfiguration.presetLimit {
        var preset = InputPreset.standard
        preset.id = UUID()
        preset.name = "Preset \(index)"
        configuration.presets.append(preset)
    }
    let given5 = configuration.givePreset(to: "xbox", named: "Xbox", touchpad: false)
    #expect(!given5)
    #expect(configuration.controllers["xbox"] == nil)
}
