import ChiakiModels
import Foundation
import Testing

@Test func tappingTheTouchButtonClicksBriefly() {
    var button = TouchButton(surface: .ps5)
    button.press(down: true, at: 1_000)
    #expect(button.capturesRightStick)
    #expect(!button.clicking)
    button.press(down: false, at: 2_000)
    #expect(button.clicking)
    let early = button.tick(at: 2_000 + TouchButton.clickMicroseconds - 1)
    #expect(!early)
    let done = button.tick(at: 2_000 + TouchButton.clickMicroseconds)
    #expect(done)
    #expect(button.phase == .idle)
}

@Test func holdingTheTouchButtonAndMovingTheStickTouchesWithoutClicking() throws {
    var button = TouchButton(surface: .ps5)
    button.press(down: true, at: 0)
    button.stick(x: 0.1, y: 0)
    #expect(button.touch == nil)
    button.stick(x: 1, y: 0)
    let first = try #require(button.touch)
    #expect(first.x == TouchpadSurface.ps5.point(normalizedX: 0.95, normalizedY: 0.5).x)
    button.stick(x: 0, y: -1)
    let moved = try #require(button.touch)
    #expect(moved.id == first.id)
    #expect(moved.y < first.y)
    button.press(down: false, at: 10)
    #expect(button.phase == .idle)
    #expect(!button.clicking)
    button.press(down: true, at: 20)
    button.stick(x: -1, y: 0)
    #expect(try #require(button.touch).id != first.id)
}
