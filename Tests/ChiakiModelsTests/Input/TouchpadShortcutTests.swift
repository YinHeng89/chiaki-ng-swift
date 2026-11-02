import ChiakiModels
import Foundation
import Testing

@Test func touchpadShortcutDefaultsToCommandShiftT() throws {
    let configuration = try ControlsConfiguration().validated()
    #expect(configuration.touchpadShortcut.key?.title == "⇧⌘T")
    #expect(configuration.touchpadShortcut.key?.matches(keyCode: 17, modifiers: [.command, .shift]) == true)
    #expect(configuration.touchpadShortcut.key?.matches(keyCode: 17, modifiers: .command) == false)
    #expect(configuration.touchpadShortcut.buttons == [4, 8])
}

@Test func savedControlsWithoutATouchpadShortcutDecodeWithTheDefault() throws {
    var legacy = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ControlsConfiguration())
    ) as? [String: Any]
    legacy?.removeValue(forKey: "touchpadShortcut")
    let data = try JSONSerialization.data(withJSONObject: legacy ?? [:])
    let decoded = try JSONDecoder().decode(ControlsConfiguration.self, from: data)
    #expect(decoded == ControlsConfiguration())
}

@Test func customTouchpadShortcutRoundTrips() throws {
    var configuration = ControlsConfiguration()
    configuration.touchpadShortcut = TouchpadShortcut(
        key: KeyChord(keyCode: 9, modifiers: [.control, .option], label: "V"),
        buttons: [9, 10, 0]
    )
    let decoded = try JSONDecoder().decode(
        ControlsConfiguration.self, from: JSONEncoder().encode(configuration)
    )
    #expect(decoded == configuration)
    _ = try decoded.validated()
}

@Test func touchpadShortcutRejectsUnsafeChoices() {
    func invalid(_ shortcut: TouchpadShortcut) -> Bool {
        var configuration = ControlsConfiguration()
        configuration.touchpadShortcut = shortcut
        return (try? configuration.validated()) == nil
    }
    let plain = KeyChord(keyCode: 17, modifiers: [], label: "T")
    let shiftOnly = KeyChord(keyCode: 17, modifiers: .shift, label: "T")
    let quit = KeyChord(keyCode: 12, modifiers: .command, label: "Q")
    let streamMenu = KeyChord(keyCode: 46, modifiers: [.command, .shift], label: "M")
    #expect(invalid(.init(key: plain, buttons: [])))
    #expect(invalid(.init(key: shiftOnly, buttons: [])))
    #expect(invalid(.init(key: quit, buttons: [])))
    #expect(invalid(.init(key: streamMenu, buttons: [])))
    #expect(invalid(.init(key: nil, buttons: [4])))
    #expect(invalid(.init(key: nil, buttons: [4, 4])))
    #expect(invalid(.init(key: nil, buttons: [8, 7])))
    #expect(invalid(.init(key: nil, buttons: [4, 26])))
    #expect(invalid(.init(key: nil, buttons: [0, 1, 2, 3])))
    #expect(!invalid(.init(key: nil, buttons: [])))
}

private func replay(_ chord: inout ButtonChordDetector, _ events: [(Int, Bool)]) -> [Bool] {
    events.map { chord.button($0.0, down: $0.1) }
}

@Test func buttonChordFiresOnceUntilEveryChordButtonIsReleased() {
    var chord = ButtonChordDetector(buttons: [4, 8])
    let opening = replay(&chord, [(4, true), (0, true)])
    #expect(opening == [false, false])
    #expect(chord.suppresses(4) == false)
    let fired = replay(&chord, [(8, true)])
    #expect(fired == [true])
    #expect(chord.suppresses(4))
    #expect(chord.suppresses(8))
    #expect(chord.suppresses(0) == false)
    let held = replay(&chord, [(8, false), (8, true), (4, false), (8, false)])
    #expect(held == [false, false, false, false])
    #expect(chord.phase == .armed)
    let again = replay(&chord, [(8, true), (4, true)])
    #expect(again == [false, true])
}

@Test func emptyButtonChordNeverFires() {
    var chord = ButtonChordDetector(buttons: [])
    let empty = replay(&chord, [(4, true)])
    #expect(empty == [false])
    chord.configure(buttons: [4])
    let single = replay(&chord, [(4, true)])
    #expect(single == [false])
    chord.reset()
    chord.configure(buttons: [4, 5])
    let pair = replay(&chord, [(5, true), (4, true)])
    #expect(pair == [false, true])
}
