import AppKit
import ChiakiTestSupport
import CoreGraphics
@testable import MenuFocus
import PlatformUI
import SwiftUI
import Testing

@MainActor @Suite(.serialized)
struct InputModeTests {
    @Test func controllerInputEntersControllerMode() {
        let center = InputModeCenter()
        #expect(center.mode == .pointer)
        #expect(center.controllerInput())
        #expect(center.mode == .controller)
        #expect(!center.controllerInput())
    }
    @Test func pointerTravelPastTheThresholdEntersPointerMode() {
        let center = InputModeCenter(mode: .controller)
        #expect(!center.pointerMoved(dx: 5, dy: 0, at: 10))
        #expect(center.mode == .controller)
        #expect(center.pointerMoved(dx: 6, dy: 6, at: 10.05))
        #expect(center.mode == .pointer)
    }
    @Test func pointerJitterKeepsControllerMode() {
        let center = InputModeCenter(mode: .controller)
        for step in 0..<40 {
            let sign: CGFloat = step.isMultiple(of: 2)
                ? 1
                : -1
            center.pointerMoved(dx: 3 * sign, dy: 2 * sign, at: Double(step) * 0.5)
        }
        #expect(center.mode == .controller)
        center.pointerMoved(dx: 1, dy: 1, at: 100)
        center.pointerMoved(dx: 1, dy: 0, at: 100.1)
        #expect(center.mode == .controller)
    }
    @Test func clicksAndScrollsEnterPointerMode() throws {
        let center = InputModeCenter(mode: .controller)
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        navigator(center).pointerEvent(click, windows: [])
        #expect(center.mode == .pointer)

        center.controllerInput()
        let scroll = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 4, wheel2: 0, wheel3: 0
        ).flatMap(NSEvent.init(cgEvent:)))
        navigator(center).pointerEvent(scroll, windows: [])
        #expect(center.mode == .pointer)
    }
    @Test func mouseMovedEventsUseTheTravelThreshold() throws {
        let center = InputModeCenter(mode: .controller)
        func moved(_ dx: Int64, at time: UInt64) throws -> NSEvent {
            let event = try #require(CGEvent(
                mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: .zero, mouseButton: .left
            ))
            event.setIntegerValueField(.mouseEventDeltaX, value: dx)
            event.timestamp = time
            return try #require(NSEvent(cgEvent: event))
        }
        navigator(center).pointerEvent(try moved(2, at: 1_000_000_000), windows: [])
        #expect(center.mode == .controller)
        navigator(center).pointerEvent(try moved(40, at: 1_050_000_000), windows: [])
        #expect(center.mode == .pointer)
    }
    @Test func navigationKeysEnterControllerModeButTypingDoesNot() {
        let center = InputModeCenter()
        #expect(!center.keyPressed(0, modifiers: [], editingText: false))
        #expect(!center.keyPressed(53, modifiers: [], editingText: false))
        #expect(!center.keyPressed(123, modifiers: [], editingText: true))
        #expect(!center.keyPressed(125, modifiers: .command, editingText: false))
        #expect(center.mode == .pointer)
        #expect(center.keyPressed(48, modifiers: .shift, editingText: false))
        #expect(center.mode == .controller)
        center.pointerAction()
        for code: UInt16 in [36, 49, 76, 123, 124, 125, 126] {
            #expect(center.keyPressed(code, modifiers: [], editingText: false))
            center.pointerAction()
        }
    }
    @Test(.requiresWindowServer) func pointerModeReleasesFocusAndControllerRestoresIt() async {
        let harness = MenuFocusHarness(width: 400, height: 200) { _ in
            MenuFocusHostingView(rootView: HStack {
                FocusButton("First") {}
                FocusButton("Second") {}
            }.padding())
        }
        defer {
            harness.close()
        }
        await harness.open()
        harness.window.recalculateKeyViewLoop()
        harness.window.selectNextKeyView(nil)
        await harness.settle()
        harness.window.selectNextKeyView(nil)
        await harness.settle()
        #expect(testNavigator.hasControlFocus(in: harness.window))
        let focused = harness.focusedView

        testNavigator.releaseFocus(in: [harness.window])
        await harness.settle()
        #expect(!testNavigator.hasControlFocus(in: harness.window))

        #expect(testNavigator.restoreFocus(in: harness.window))
        await harness.settle()
        #expect(harness.focusedView === focused)
    }
    @Test func connectingAControllerShowsFocusAndDisconnectingHidesIt() {
        let center = InputModeCenter()
        #expect(center.mode == .pointer)
        #expect(center.controllerConnection(true))
        #expect(center.mode == .controller)
        #expect(!center.controllerConnection(true))
        #expect(center.controllerConnection(false))
        #expect(center.mode == .pointer)
        #expect(!center.controllerConnection(false))
    }
    @Test func pointerModeHidesTheButtonHighlight() throws {
        let unfocused = try pixels(highlightProbe(mode: .pointer, focused: false))
        let pointer = try pixels(highlightProbe(mode: .pointer, focused: true))
        let controller = try pixels(highlightProbe(mode: .controller, focused: true))
        #expect(pointer == unfocused)
        #expect(controller != unfocused)
    }
    @Test func nativeControlHighlightMatchesTheBezelForEachSize() {
        #expect(FocusHighlightShape.control.resolved(for: .small) == .roundedRectangle(5))
        #expect(FocusHighlightShape.control.resolved(for: .regular) == .roundedRectangle(6))
        #expect(FocusHighlightShape.control.resolved(for: .large) == .capsule)
        #expect(FocusHighlightShape.circle.resolved(for: .regular) == .circle)
    }
    @Test func focusHighlightFollowsTheControlShape() throws {
        let circle = try pixels(highlightProbe(mode: .controller, focused: true, shape: .circle))
        let capsule = try pixels(highlightProbe(mode: .controller, focused: true, shape: .capsule))
        let square = try pixels(highlightProbe(mode: .controller, focused: true, shape: .standard))
        #expect(alpha(circle, x: 22, y: 22) < alpha(square, x: 22, y: 22))
        #expect(alpha(capsule, x: 22, y: 22) < alpha(square, x: 22, y: 22))
        #expect(alpha(circle, x: 40, y: 40) > 0)
        for buffer in [circle, capsule, square] {
            #expect(alpha(buffer, x: 17, y: 17) == 0)
            #expect(alpha(buffer, x: 66, y: 40) == 0)
        }
    }
    private func highlightProbe(
        mode: InputMode,
        focused: Bool,
        shape: FocusHighlightShape = .standard
    ) -> some View {
        FocusButton {} label: {
            Color.clear.frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .focusHighlightShape(shape)
        .environment(\.menuItemFocused, focused)
        .environment(\.inputMode, mode)
        .frame(width: 80, height: 80)
        .background(Color.black)
    }
    private func pixels(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
    private func alpha(_ buffer: [UInt8], x: Int, y: Int) -> Int {
        let index = (y * 80 + x) * 4
        return Int(buffer[index]) + Int(buffer[index + 1])
    }

    private func navigator(_ center: InputModeCenter) -> AppKitMenuNavigator {
        AppKitMenuNavigator(policy: StandaloneMenuInputPolicy(), inputMode: center)
    }
}
