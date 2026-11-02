@testable import ChiakiFeatures
import ChiakiModels
import AppKit
import SwiftUI
import Testing
import MenuFocus
import ChiakiTestSupport

@MainActor
private final class LayoutProbe {
    var preferences = ControllerPreferences()
}

private struct LayoutCardHost: View {
    let probe: LayoutProbe
    let device: ControllerDevice
    @State private var preferences = ControllerPreferences()

    var body: some View {
        ControllerSettingsCard(
            device: device, preferences: preferences, preset: .standard,
            update: { next in
                probe.preferences = next
                preferences = next
            },
            test: { _ in
            }
        )
        .toggleStyle(AccentCheckboxToggleStyle())
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func pad(_ family: ControllerFamily) -> ControllerDevice {
    ControllerDevice(
        id: 7, preferenceKey: "unit:7", name: "Pad", transport: "USB", individual: true, rumble: true,
        lights: false, motion: false, touchpad: false, family: family
    )
}

extension MenuFocusTests {
    private func calibrationControl(_ probe: LayoutProbe, family: ControllerFamily, row: Int) async
        -> (MenuFocusHarness, MenuHandlerID) {
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: LayoutCardHost(probe: probe, device: pad(family)))
        }
        let window = harness.window
        let moves = testNavigator.handlers.registerFocusMove { target, direction in
            guard target === window else {
                return false
            }
            return testNavigator.moveGeometric(direction, in: target, allowUnaligned: direction == .up
                || direction == .down)
        }
        await harness.open()
        harness.window.selectNextKeyView(nil)
        await harness.pause(150)
        await harness.pause(900)
        await harness.send(Array(repeating: .down, count: row))
        return (harness, moves)
    }

    @Test func nintendoControllersOfferButtonLabelsBelowTheStickSettings() async {
        let probe = LayoutProbe()
        let (harness, moves) = await calibrationControl(probe, family: .nintendo, row: 4)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.preferences.buttonLayout == .label)
        #expect(!probe.preferences.swapSticks)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.preferences.buttonLayout == .position)
    }

    @Test func otherControllersDoNotShowTheButtonLabelChoice() async {
        let probe = LayoutProbe()
        let (harness, moves) = await calibrationControl(probe, family: .xbox, row: 3)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.preferences.swapSticks)
        #expect(probe.preferences.buttonLayout == .position)
    }

    @Test func downFromSwapSticksReachesTheRightStickGyroSegments() async {
        let probe = LayoutProbe()
        let (harness, moves) = await calibrationControl(probe, family: .xbox, row: 4)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        await harness.send([.right, .right, .confirm])
        await harness.pause(150)
        #expect(probe.preferences.stickGyro == .whileHeld)
        #expect(!probe.preferences.swapSticks)
        await harness.send([.right, .confirm])
        await harness.pause(150)
        #expect(probe.preferences.stickGyro == .always)
    }

    @Test func nintendoControllersReachTheGyroSegmentsBelowTheButtonLabels() async {
        let probe = LayoutProbe()
        let (harness, moves) = await calibrationControl(probe, family: .nintendo, row: 5)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        await harness.send([.right, .right, .confirm])
        await harness.pause(150)
        #expect(probe.preferences.stickGyro == .whileHeld)
        #expect(probe.preferences.buttonLayout == .position)
    }
}
