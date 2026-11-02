@testable import ChiakiFeatures
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
import MenuFocus
import ChiakiTestSupport

@MainActor
private final class LightbarProbe {
    var values = [ControllerLightbar?]()
}

private struct LightbarChooserHost: View {
    let probe: LightbarProbe
    @State private var value: ControllerLightbar?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FocusButton("Above") {
            }
            LightbarChooser(value: value, inherited: .fixed(rgb: 0xff2020)) { next in
                probe.values.append(next)
                value = next
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension MenuFocusTests {
    private func settingsHarness(_ store: StoreOf<SettingsFeature>) -> MenuFocusHarness {
        MenuFocusHarness(width: 1300, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: window
            ))
        }
    }

    private func moveToBottom(_ harness: MenuFocusHarness, limit: Int) async -> NSResponder? {
        harness.perform([.down], in: harness.window)
        await harness.pause(200)
        var previous = harness.window.firstResponder
        for _ in 0..<limit {
            await harness.send(.down)
            if harness.window.firstResponder === previous {
                break
            }
            previous = harness.window.firstResponder
        }
        return harness.window.firstResponder
    }

    @Test func lightBarFallbackIsChosenWithTheControllerFromTheControlsTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = settingsHarness(store)
        defer {
            harness.close()
        }
        await harness.open()
        _ = await moveToBottom(harness, limit: 160)
        #expect(store.controls.isEditable)
        await harness.send(.up)
        #expect(store.controls.draft.lightbar == .followGame)
        await harness.send(.left)
        let follow = harness.window.firstResponder
        await harness.send(.right)
        let fixed = harness.window.firstResponder
        #expect(fixed !== follow)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.controls.draft.lightbar == .fixed(rgb: ControllerLightbarSwatch.all[0].rgb))
        #expect(harness.window.firstResponder === fixed)
        await harness.send(.down)
        let swatch = harness.window.firstResponder
        #expect(swatch !== fixed)
        await harness.send(.confirm)
        await harness.pause(150)
        guard case .fixed(let chosen) = store.controls.draft.lightbar else {
            Issue.record("Choosing a swatch left the fixed colour mode")
            return
        }
        await harness.send(.right)
        let next = harness.window.firstResponder
        #expect(next !== swatch)
        await harness.send(.confirm)
        await harness.pause(150)
        guard case .fixed(let changed) = store.controls.draft.lightbar else {
            Issue.record("Choosing a second swatch left the fixed colour mode")
            return
        }
        #expect(changed != chosen)
        #expect(ControllerLightbarSwatch.all.contains { $0.rgb == changed })
        await harness.send(.left)
        #expect(harness.window.firstResponder === swatch)
        await harness.send(.up)
        #expect(harness.window.firstResponder !== swatch)
        await harness.send(.left)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(store.controls.draft.lightbar == .followGame)
    }

    private func chooserHarness(_ probe: LightbarProbe) -> (MenuFocusHarness, MenuHandlerID) {
        let harness = MenuFocusHarness(width: 760, height: 400) { _ in
            MenuFocusHostingView(rootView: LightbarChooserHost(probe: probe))
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

    private func focusFirstStop(_ harness: MenuFocusHarness) async {
        await waitUntil(harness) {
            testNavigator.hasControlFocus(in: harness.window)
        }
        if !testNavigator.hasControlFocus(in: harness.window) {
            harness.window.selectNextKeyView(nil)
            await harness.settle()
        }
    }

    @Test func controllerLightBarOverrideOffersTheSharedSettingAndBackToIt() async {
        let probe = LightbarProbe()
        let (harness, moves) = chooserHarness(probe)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        await harness.open()
        await focusFirstStop(harness)
        let above = harness.window.firstResponder
        let aboveFrame = harness.focusedFrame
        #expect(above is NSView)
        await harness.send(.down)
        let inherited = harness.window.firstResponder
        #expect(inherited !== above)
        await harness.send(.left)
        #expect(harness.window.firstResponder === inherited)
        await harness.send(.right)
        let follow = harness.window.firstResponder
        #expect(follow !== inherited)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .some(.followGame))
        await harness.send(.right)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .some(.fixed(rgb: 0xff2020)))
        await harness.send(.down)
        let swatch = harness.window.firstResponder
        #expect(swatch !== follow)
        await harness.send(.up)
        #expect(harness.window.firstResponder !== swatch)
        await harness.send([.left, .left, .left])
        #expect(harness.window.firstResponder === inherited)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .some(nil))
        await harness.send(.up)
        #expect(harness.focusedFrame == aboveFrame)
    }

    @Test func fixedColourComesBackAfterFollowingTheGame() async {
        let probe = LightbarProbe()
        let (harness, moves) = chooserHarness(probe)
        defer {
            testNavigator.handlers.unregister(moves)
            harness.close()
        }
        await harness.open()
        await focusFirstStop(harness)
        await harness.send([.down, .right, .right])
        await harness.send(.confirm)
        await harness.pause(150)
        await harness.send([.down, .right])
        await harness.send(.confirm)
        await harness.pause(150)
        guard case .some(.fixed(let picked)) = probe.values.last, picked != 0xff2020 else {
            Issue.record("Choosing a swatch did not change the fixed colour")
            return
        }
        await harness.send(.up)
        await harness.send([.left, .left, .left, .right])
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .some(.followGame))
        await harness.send(.right)
        await harness.send(.confirm)
        await harness.pause(150)
        #expect(probe.values.last == .some(.fixed(rgb: picked)))
    }

    @Test func internetConnectionSettingsAreReachedFromTheNetworkTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .network)
        let harness = MenuFocusHarness(width: 1000, height: 1100) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 800, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        let bottom = await moveToBottom(harness, limit: 16)
        #expect(store.internetConnection.isEditable)
        await harness.send([.up, .up, .up, .up])
        let leave = harness.window.firstResponder
        #expect(leave !== bottom)
        await harness.send(.up)
        let slider = harness.window.firstResponder
        #expect(slider !== leave)
        await harness.send(.confirm)
        await harness.send(.right)
        await harness.pause(100)
        #expect(store.internetConnection.draft.portGuessCount
            == InternetConnectionSettings.defaultPortGuessCount + InternetConnectionSettings.portGuessStep)
        #expect(harness.window.firstResponder === slider)
        await harness.send(.up)
        let toggle = harness.window.firstResponder
        #expect(toggle !== slider)
        await harness.send(.confirm)
        await harness.pause(100)
        #expect(store.internetConnection.draft.forcePortGuessing)
        #expect(harness.window.firstResponder === toggle)
        await harness.send(.down)
        #expect(harness.window.firstResponder === slider)
        await harness.send(.down)
        #expect(harness.window.firstResponder !== slider)
    }
}
