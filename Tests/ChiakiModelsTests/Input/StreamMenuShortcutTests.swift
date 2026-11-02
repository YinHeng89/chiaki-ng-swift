import ChiakiModels
import Foundation
import Testing

@Test func streamMenuShortcutsNeedTwoToFourDifferentButtons() {
    #expect(StreamMenuShortcut.standard.isValid)
    #expect(StreamMenuShortcut(buttons: [9, 10, 6, 4]).isValid)
    #expect(!StreamMenuShortcut(buttons: [9]).isValid)
    #expect(!StreamMenuShortcut(buttons: [9, 9]).isValid)
    #expect(!StreamMenuShortcut(buttons: [0, 1, 2, 3, 4]).isValid)
    #expect(!StreamMenuShortcut(buttons: [0, 30]).isValid)
}

@Test func streamMenuAndTouchpadShortcutsMayNotContainEachOther() {
    let touchpad = TouchpadShortcut(key: nil, buttons: [4, 8])
    #expect(!StreamMenuShortcut.standard.overlaps(touchpad))
    #expect(StreamMenuShortcut(buttons: [4, 8]).overlaps(touchpad))
    #expect(StreamMenuShortcut(buttons: [4, 8, 9]).overlaps(touchpad))
    #expect(StreamMenuShortcut(buttons: [4, 9]).overlaps(TouchpadShortcut(key: nil, buttons: [4, 9, 10])))
    #expect(!StreamMenuShortcut(buttons: [4, 9]).overlaps(TouchpadShortcut(key: nil, buttons: [])))
    var configuration = ControlsConfiguration()
    configuration.streamMenuShortcut = StreamMenuShortcut(buttons: [4, 8])
    #expect(throws: InputFailure.self) {
        try configuration.validated()
    }
}

@Test func savedControlsWithoutAStreamMenuShortcutKeepBothStickClicks() throws {
    var configuration = ControlsConfiguration()
    configuration.streamMenuShortcut = StreamMenuShortcut(buttons: [9, 10])
    let encoded = try JSONEncoder().encode(configuration)
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["streamMenuShortcut"] != nil)
    object.removeValue(forKey: "streamMenuShortcut")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(ControlsConfiguration.self, from: legacy)
        .streamMenuShortcut == .standard)
    #expect(try JSONDecoder().decode(ControlsConfiguration.self, from: encoded).streamMenuShortcut
        .buttons == [
            9,
            10
        ])
}
