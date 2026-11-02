@testable import ChiakiFeatures
import ChiakiModels
import AppKit
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

@MainActor
private final class FeedbackProbe {
    var values = [HapticFeedback]()
    var triggers = [TriggerStrength]()
}

private struct FeedbackCardHost: View {
    let probe: FeedbackProbe
    let device: ControllerDevice
    @State private var preferences = ControllerPreferences()

    var body: some View {
        ControllerSettingsCard(
            device: device, preferences: preferences, preset: .standard,
            update: { next in
                probe.values.append(next.hapticFeedback)
                probe.triggers.append(next.triggerStrength)
                preferences = next
            },
            test: { _ in
            }
        )
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension MenuFocusTests {
    private func feedbackHarness(_ probe: FeedbackProbe,
                                 device: ControllerDevice) -> (MenuFocusHarness, MenuHandlerID) {
        let harness = MenuFocusHarness(width: 1300, height: 900) { _ in
            MenuFocusHostingView(rootView: FeedbackCardHost(probe: probe, device: device))
        }
        let window = harness.window
        let moves = testNavigator.handlers.registerFocusMove { target, direction in
            guard target === window else {
                return false
            }
            return testNavigator.moveGeometric(direction, in: target, allowUnaligned: direction == .up
                || direction == .down)
        }
        return (harness, moves)
    }

    private func openFeedbackSection(_ harness: MenuFocusHarness) async -> NSResponder? {
        await harness.open()
        harness.window.selectNextKeyView(nil)
        await harness.pause(150)
        await harness.send(.right)
        await harness.send(.confirm)
        await harness.pause(900)
        return harness.window.firstResponder
    }

    @Test func hapticsChoiceIsReachedAndChangedWithTheController() async {
        let probe = FeedbackProbe()
        let device = ControllerDevice(
            id: 9, preferenceKey: "unit:9", name: "Xbox Wireless Controller", transport: "Wireless",
            individual: true, rumble: true, lights: false, motion: false, touchpad: false, family: .xbox
        )
        let (harness, moves) = feedbackHarness(probe, device: device)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        let section = await openFeedbackSection(harness)
        #expect(section is NSView)
        await harness.send(.down)
        let entered = harness.window.firstResponder
        #expect(entered !== section)
        await harness.send([.left, .left, .left])
        let automatic = harness.window.firstResponder
        await harness.send(.left)
        #expect(harness.window.firstResponder === automatic)
        await harness.send(.right)
        let rumble = harness.window.firstResponder
        #expect(rumble !== automatic)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .rumble)
        #expect(harness.window.firstResponder === rumble)
        await harness.send(.right)
        let off = harness.window.firstResponder
        #expect(off !== rumble)
        #expect(off !== automatic)
        #expect(entered === automatic || entered === rumble || entered === off)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .off)
        await expectHapticsRowLeadsDownAndBack(harness, probe: probe, segments: [automatic, rumble, off])
    }

    @Test func triggerStrengthIsReachedBelowAdaptiveTriggersAndChanged() async {
        let probe = FeedbackProbe()
        let device = ControllerDevice(
            id: 10, preferenceKey: "unit:10", name: "DualSense Wireless Controller", transport: "USB",
            individual: true, rumble: true, lights: true, motion: true, touchpad: true,
            adaptiveTriggers: true, family: .playStation
        )
        let (harness, moves) = feedbackHarness(probe, device: device)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        _ = await openFeedbackSection(harness)
        await harness.send([.down, .down, .down, .down])
        let toggleResponder = harness.window.firstResponder
        let toggle = harness.focusedFrame
        await harness.send(.down)
        let segments = harness.focusedFrame
        #expect(segments.midY < toggle.midY)
        await harness.send([.left, .left, .left, .right])
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.triggers.last == .medium)
        await harness.send(.up)
        #expect(harness.window.firstResponder === toggleResponder)
    }

    private func expectHapticsRowLeadsDownAndBack(_ harness: MenuFocusHarness, probe: FeedbackProbe,
                                                  segments: [NSResponder?]) async {
        let automatic = segments[0]
        let rumble = segments[1]
        let off = segments[2]
        await harness.send(.down)
        let below = harness.window.firstResponder
        #expect(below !== off)
        #expect(below !== rumble)
        #expect(below !== automatic)
        let slider = harness.focusedFrame
        #expect(slider.midX < 650)
        #expect(slider.width > 300)
        #expect(slider.height < 24)
        await harness.send(.up)
        let back = harness.window.firstResponder
        #expect(back === off || back === rumble || back === automatic)
        await harness.send([.left, .left, .left])
        #expect(harness.window.firstResponder === automatic)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .automatic)
        await harness.send(.up)
        let above = harness.window.firstResponder
        #expect(above !== automatic)
        #expect(above !== rumble)
        #expect(above !== off)
    }
}
