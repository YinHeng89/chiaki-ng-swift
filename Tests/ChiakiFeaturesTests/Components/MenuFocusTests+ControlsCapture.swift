import ChiakiClients
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Synchronization
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    private func controlsHarness(_ store: StoreOf<SettingsFeature>) -> MenuFocusHarness {
        MenuFocusHarness(width: 1300, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: window
            ))
        }
    }

    private func focusDpadBinding(_ harness: MenuFocusHarness) async -> NSView? {
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        for _ in 0..<60 {
            let frame = harness.focusedFrame
            if harness.focusedView != nil,
               (ControlsBoardPlacement.chipHeight - 2...ControlsBoardPlacement.chipHeight + 2)
               .contains(frame.height) {
                return harness.focusedView
            }
            await harness.send(.down)
        }
        return nil
    }

    @Test func controllerBackCancelsKeyCaptureAndReturnsFocusToItsOrigin() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = controlsHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        let dpad = await focusDpadBinding(harness)
        #expect(dpad != nil)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.controls.capture != nil)
        #expect(harness.window.firstResponder !== dpad)
        await harness.send(.back)
        await harness.pause(150)
        #expect(store.controls.capture == nil)
        #expect(harness.window.firstResponder === dpad)
    }

    @Test func choosingAKeyReturnsFocusToTheBindingThatStartedCapture() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = controlsHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        let dpad = await focusDpadBinding(harness)
        await harness.send(.confirm)
        await harness.pause(150)
        guard let target = store.controls.capture?.target else {
            Issue.record("Capture did not start")
            return
        }
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.controls.capture == nil)
        #expect(store.controls.draft.preset().bindings.contains {
            $0.source == .macKey && $0.target == target
        })
        #expect(harness.window.firstResponder === dpad)
    }

    @Test func controllerBackFromSettingsContentReturnsToTheSelectedTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .developer)
        let harness = controlsHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(150)
        let tabFrame = harness.focusedFrame
        harness.perform([.down], in: harness.window)
        await harness.pause(150)
        #expect(harness.focusedFrame.midY < tabFrame.minY)
        await harness.send(.back)
        await harness.pause(150)
        #expect(abs(harness.focusedFrame.midY - tabFrame.midY) <= 2)
        #expect(store.route == .developer)
    }

    @Test func switchingSettingsTabsCancelsAPendingKeyCapture() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = controlsHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        store.send(.controls(.capture(.cross)))
        await harness.settle()
        #expect(store.controls.capture != nil)
        await harness.send(.next)
        await harness.pause(100)
        #expect(store.route != .controls)
        #expect(store.controls.capture == nil)
    }

    @Test func optionsTogglesSettingsAndBackFromTheTabBarClosesIt() async {
        let store = FeatureFocusStores.rootStore(tab: .developer)
        let harness = MenuFocusHarness(width: 1100, height: 760) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: store)
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(800)
        #expect(store.settingsPresented)
        await harness.send(.down)
        await harness.pause(150)
        await harness.send(.back)
        await harness.pause(800)
        #expect(store.settingsPresented)
        await harness.send(.back)
        await harness.pause(1200)
        #expect(!store.settingsPresented)
        await harness.send(.settings)
        await harness.pause(1200)
        #expect(store.settingsPresented)
        await harness.send(.settings)
        await harness.pause(1200)
        #expect(!store.settingsPresented)
    }

    @Test func squareDeletesAndTriangleAddsASpaceOnTheOnScreenKeyboard() async {
        let value = Mutex("")
        let harness = MenuFocusHarness(width: 480, height: 450) { _ in
            MenuFocusHostingView(rootView: TextEntryFixture { updated in
                value.withLock { $0 = updated }
            })
        }
        defer {
            harness.close()
        }
        await harness.open()
        #expect(harness.window.firstResponder is NSTextView)
        await harness.send(.confirm)
        guard let sheet = harness.window.attachedSheet else {
            Issue.record("Keyboard did not open")
            return
        }
        await harness.send(.confirm)
        await harness.settle(sheet.contentView)
        #expect(value.withLock { $0 } == "q")
        await harness.send(.focusToolbar)
        await harness.settle(sheet.contentView)
        #expect(value.withLock { $0 } == "q ")
        await harness.send([.alternate, .alternate])
        await harness.settle(sheet.contentView)
        #expect(value.withLock { $0 }.isEmpty)
    }

    @Test func keyLabelsNameNonPrintingKeys() {
        #expect(KeyCodeLabels.label(for: 122, characters: "\u{F704}") == "F1")
        #expect(KeyCodeLabels.label(for: 82, characters: "0") == "Keypad 0")
        #expect(KeyCodeLabels.label(for: 27, characters: "−") == "-")
        #expect(KeyCodeLabels.label(for: 0, characters: "a") == "A")
        #expect(KeyCodeLabels.label(for: 110, characters: "\u{F726}") == "Key 110")
        #expect(KeyCodeLabels.label(for: 10, characters: nil) == "Key 10")
    }
}

extension MenuFocusTests {
    @Test(arguments: [false, true])
    func swappingControllersKeepsFocusOnTheSameCardControl(focusEscapes: Bool) async {
        await runControllerSwap(
            focusEscapes
                ? .escapesDuringSwap
                : .staysOnCard
        )
    }

    @Test func swappingControllersLeavesADeliberateFocusAlone() async {
        await runControllerSwap(.chosenBeforeSwap)
    }

    private func runControllerSwap(_ scenario: ControllerSwapScenario) async {
        let connected = Mutex([swapPad(1), swapPad(2)])
        let store = swapStore {
            connected.withLock { $0 }
        }
        let harness = MenuFocusHarness(width: 1300, height: 1100) { _ in
            MenuFocusHostingView(rootView: VStack {
                FocusButton("Close") {}
                    .glassControlStyle(.regular)
                ScrollView {
                    ControlsSettingsView(store: store)
                        .padding(24)
                }
                .scrollIndicators(.never)
            })
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        let stops = AppKitKeyViews.navigationStops(in: harness.window)
        let frames = stops.map { $0.convert($0.bounds, to: nil) }
        guard let target = zip(stops, frames)
            .first(where: { $1.height < 120 && $1.midY < 700 && $1.midY > 200 })?.0,
            let close = zip(stops, frames).max(by: { $0.1.midY < $1.1.midY })?.0 else {
            Issue.record("Controls not found")
            return
        }
        harness.window.makeFirstResponder(target)
        await harness.pause(100)
        if scenario == .chosenBeforeSwap {
            harness.window.makeFirstResponder(close)
            await harness.pause(600)
        }
        let before = harness.focusedFrame
        connected.withLock {
            $0 = [swapPad(2)]
        }
        for _ in 0..<100 where store.devices.map(\.id) != [2] {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if scenario == .escapesDuringSwap {
            harness.window.makeFirstResponder(close)
        }
        await harness.pause(600)
        #expect(store.devices.map(\.id) == [2])
        let after = harness.focusedFrame
        #expect(abs(after.midX - before.midX) < 4 && abs(after.midY - before.midY) < 4, "\(before) \(after)")
    }
}

private enum ControllerSwapScenario {
    case staysOnCard, escapesDuringSwap, chosenBeforeSwap
}

@MainActor
private func swapPad(_ id: UInt32) -> ControllerDevice {
    ControllerDevice(
        id: id, preferenceKey: "pad-\(id)", name: "Pad \(id)", transport: "USB",
        individual: true, rumble: true, lights: false, motion: false, touchpad: false
    )
}

@MainActor
private func swapStore(
    _ devices: @escaping @Sendable () -> [ControllerDevice]
) -> StoreOf<ControlsSettingsFeature> {
    var state = ControlsSettingsFeature.State.loaded()
    state.devices = devices()
    return Store(initialState: state) {
        ControlsSettingsFeature()
    } withDependencies: {
        $0.controllers = ControllersClient(
            devices: devices,
            testRumble: { _, _ in },
            showLights: { _ in }
        )
        $0.uuid = .incrementing
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.continuousClock = TestClock()
    }
}
