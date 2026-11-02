import AppKit
import ChiakiTestSupport
import CoreGraphics
import Foundation
@testable import MenuFocus
import PlatformUI
import SwiftUI
import Testing

@MainActor @Suite
struct FocusEngineTests {
    private func window() -> PlatformWindow {
        _ = NSApplication.shared
        let window = HeadlessWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func handlersAreAskedNewestFirstAndStopAtTheFirstThatAnswers() {
        let stack = MenuHandlerStack()
        let target = window()
        var asked = [String]()
        stack.registerBack { _ in
            asked.append("older")
            return true
        }
        let newer = stack.registerBack { _ in
            asked.append("newer")
            return false
        }
        #expect(stack.back(in: target))
        #expect(asked == ["newer", "older"])
        stack.unregister(newer)
        asked.removeAll()
        #expect(stack.back(in: target))
        #expect(asked == ["older"])
    }

    @Test func unregisteringRemovesOnlyTheMatchingKind() {
        let stack = MenuHandlerStack()
        let target = window()
        let move = stack.registerFocusMove { _, _ in
            true
        }
        stack.registerModalActivation { _ in
            true
        }
        #expect(stack.hasModalActivation)
        stack.unregister(move)
        #expect(!stack.performFocusMove(.down, in: target))
        #expect(stack.activateModal(in: target))
        stack.removeAll()
        #expect(!stack.hasModalActivation)
    }

    @Test func routedCommandsCarryTheirWindow() async {
        let router = MenuCommandRouter()
        let target = window()
        var events = router.events().makeAsyncIterator()
        router.send(.next, to: target)
        router.send(.streamMenu, to: nil)
        let first = await events.next()
        let second = await events.next()
        #expect(first?.command == .next)
        #expect(first?.targets(target) == true)
        #expect(second?.command == .streamMenu)
        #expect(second?.targets(target) == false)
        #expect(second?.targets(target, keyWindow: target) == true)
    }

    @Test func navigationCommandsStayInTheEngine() {
        let routed = [
            MenuCommand.alternate,
            .previous,
            .next,
            .streamMenu,
            .focusToolbar,
            .settings,
            .commit,
            .shift
        ]
        let navigation = [MenuCommand.up, .down, .left, .right, .confirm, .back]
        let routedStayOut = routed.allSatisfy { command in
            !command.isNavigation
        }
        let navigationStaysIn = navigation.allSatisfy { command in
            command.isNavigation
        }
        #expect(routedStayOut)
        #expect(navigationStaysIn)
        #expect(MenuCommand.left.direction == .left)
        #expect(MenuCommand.confirm.direction == nil)
    }

    @Test func inputGateTracksPresentationsAndPrompts() {
        let gate = MenuInputGate()
        let panel = UUID()
        let prompt = UUID()
        #expect(!gate.isBlocking)
        gate.block(panel)
        gate.block(prompt, prompt: true)
        #expect(gate.isBlocking)
        #expect(gate.isPrompting)
        #expect(gate.isBlocking(besides: panel))
        gate.release(prompt)
        #expect(!gate.isPrompting)
        #expect(!gate.isBlocking(besides: panel))
        gate.release(panel)
        #expect(!gate.isBlocking)
    }

    @Test func arrowKeysMapBothWays() {
        for direction in MenuMoveDirection.allCases {
            let key = MenuArrowKey(direction)
            #expect(MenuArrowKey(keyCode: key.keyCode) == key)
            #expect(MenuMoveDirection(key.key) == direction)
        }
        #expect(MenuArrowKey(keyCode: 0) == nil)
        #expect(MenuArrowKey(command: .confirm) == nil)
        #expect(MenuArrowKey.keyCodes == [123, 124, 125, 126])
    }

    @Test func geometryChoosesTheAlignedNeighbourInBothOrientations() {
        let origin = CGRect(x: 0, y: 100, width: 100, height: 30)
        let aboveInAppKit = CGRect(x: 0, y: 200, width: 100, height: 30)
        let besideAbove = CGRect(x: 300, y: 150, width: 100, height: 30)
        #expect(FocusGeometry.appKit
            .target(toward: .up, from: origin, among: [besideAbove, aboveInAppKit]) == 1)
        #expect(FocusGeometry.touch
            .target(toward: .down, from: origin, among: [besideAbove, aboveInAppKit]) == 1)
        #expect(FocusGeometry.appKit.target(toward: .up, from: origin, among: [besideAbove]) == nil)
        #expect(
            FocusGeometry.appKit.target(
                toward: .up,
                from: origin,
                among: [besideAbove],
                allowUnaligned: true
            ) == 0
        )
    }

    @Test func readingOrderWrapsAroundForSequentialMoves() {
        let geometry = FocusGeometry.touch
        let frames = [
            CGRect(x: 0, y: 0, width: 20, height: 20),
            CGRect(x: 40, y: 0, width: 20, height: 20),
            CGRect(x: 0, y: 40, width: 20, height: 20)
        ]
        #expect(geometry.sequentialTarget(after: nil, among: frames, backward: false) == 0)
        #expect(geometry
            .sequentialTarget(after: frames[1], among: [frames[0], frames[2]], backward: false) == 1)
        #expect(geometry
            .sequentialTarget(after: frames[2], among: [frames[0], frames[1]], backward: false) == 0)
        #expect(FocusGeometry.nearest(to: frames[2], among: frames) == 2)
        #expect(FocusGeometry.isSameControl(frames[0], frames[0].insetBy(dx: 1, dy: 1)))
    }

    @Test func keyboardLayoutClampsMovesToTheGrid() {
        var layout = ControllerKeyboardLayout()
        #expect(layout.moved(from: .glyph(0, 0), direction: .up) == .glyph(0, 0))
        #expect(layout.moved(from: .glyph(0, 9), direction: .down) == .glyph(1, 8))
        #expect(layout.moved(from: .glyph(2, 0), direction: .down) == .shift)
        #expect(layout.glyph(at: .glyph(0, 0)) == "q")
        layout.toggleShift()
        #expect(layout.glyph(at: .glyph(0, 0)) == "Q")
        layout.numberPad = true
        #expect(layout.moved(from: .glyph(3, 0), direction: .down) == .clear)
    }
}
