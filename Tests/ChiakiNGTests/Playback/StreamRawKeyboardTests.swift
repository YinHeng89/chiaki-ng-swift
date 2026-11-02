import AppKit
import Testing
@testable import ChiakiNG

@Test func rawKeyboardTracksHeldKeysModifiersAndCapsLock() {
    var keyboard = StreamRawKeyboard()
    let changed1 = keyboard.press(usage: 0x04, down: true)
    #expect(changed1)
    let changed2 = keyboard.press(usage: 0x05, down: true)
    #expect(changed2)
    let changed3 = keyboard.press(usage: 0x04, down: true)
    #expect(!changed3)
    let changed4 = keyboard.press(usage: 0xE1, down: true)
    #expect(changed4)
    #expect(keyboard.report == .init(modifiers: 0x02, leds: 0, keys: [0x04, 0x05]))
    let changed5 = keyboard.press(usage: 0x04, down: false)
    #expect(changed5)
    let changed6 = keyboard.press(usage: StreamRawKeyboard.capsLock, down: true)
    #expect(changed6)
    let changed7 = keyboard.press(usage: StreamRawKeyboard.capsLock, down: false)
    #expect(!changed7)
    #expect(keyboard.report == .init(modifiers: 0x02, leds: 0x02, keys: [0x05]))
    let changed8 = keyboard.releaseAll()
    #expect(changed8)
    #expect(keyboard.report == .init(modifiers: 0, leds: 0x02, keys: []))
    let changed9 = keyboard.releaseAll()
    #expect(!changed9)
}

@Test func rawKeyboardKeepsAtMostSixteenKeys() {
    var keyboard = StreamRawKeyboard()
    for usage in UInt16(0x04)...UInt16(0x18) {
        _ = keyboard.press(usage: usage, down: true)
    }
    #expect(keyboard.report.keys.count == StreamRawKeyboard.maxKeys)
    #expect(keyboard.report.keys.first == 0x04)
}

@Test func rawKeyboardReadsMacKeyEvents() throws {
    var keyboard = StreamRawKeyboard()
    let down = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
    ))
    #expect(StreamRawKeyboard.handles(down))
    let changed10 = keyboard.apply(down)
    #expect(changed10)
    #expect(keyboard.report.keys == [0x04])
    let shift = try #require(NSEvent.keyEvent(
        with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: 0x20102),
        timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: 56
    ))
    let changed11 = keyboard.apply(shift)
    #expect(changed11)
    #expect(keyboard.report.modifiers == 0x02)
    let unknown = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 200
    ))
    #expect(!StreamRawKeyboard.handles(unknown))
}
