import ChiakiModels
import Foundation
import Testing

@Test func nintendoLabelsSwapTheFaceButtonsOnlyForNintendoControllers() {
    #expect(ButtonLayout.label.code(0, family: .nintendo) == 1)
    #expect(ButtonLayout.label.code(1, family: .nintendo) == 0)
    #expect(ButtonLayout.label.code(2, family: .nintendo) == 3)
    #expect(ButtonLayout.label.code(3, family: .nintendo) == 2)
    #expect(ButtonLayout.label.code(11, family: .nintendo) == 11)
    #expect(ButtonLayout.label.code(0, family: .xbox) == 0)
    #expect(ButtonLayout.position.code(1, family: .nintendo) == 1)
}

@Test func savedControllerPreferencesWithoutALayoutKeepButtonsByPosition() throws {
    let saved = Data(#"{"nickname":"","deadZone":0.1,"invertRightY":false,"swapSticks":false,"rumbleStrength":1}"#
        .utf8)
    let preferences = try JSONDecoder().decode(ControllerPreferences.self, from: saved)
    #expect(preferences.buttonLayout == .position)
    var labelled = preferences
    labelled.buttonLayout = .label
    let decoded = try JSONDecoder().decode(ControllerPreferences.self, from: JSONEncoder().encode(labelled))
    #expect(decoded.buttonLayout == .label)
}
