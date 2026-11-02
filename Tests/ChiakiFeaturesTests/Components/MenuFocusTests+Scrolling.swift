import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    private func controlsPanel(_ root: StoreOf<RootFeature>) -> MenuFocusHarness {
        MenuFocusHarness(width: 1400, height: 800) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: root)
            ))
        }
    }

    @Test(arguments: [CGSize(width: 1512, height: 850), CGSize(width: 1920, height: 1080)])
    func downFromControlsEntersTheControlBelowTheTab(size: CGSize) async {
        let root = FeatureFocusStores.rootStore(tab: .controls)
        let harness = MenuFocusHarness(width: size.width, height: size.height) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: root)
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(900)
        let tab = harness.focusedFrame
        await harness.send(.down)
        await harness.pause(250)
        let selector = harness.focusedView
        let selectorFrame = harness.focusedFrame
        #expect(tab.height < 60 && tab.minY > selectorFrame.maxY)
        let stops = AppKitKeyViews.navigationStops(in: harness.window)
            .map { $0.convert($0.bounds, to: nil) }
            .filter { $0.maxY < tab.minY && $0.height < 120 }
        let firstRow = stops.map(\.midY).max() ?? 0
        let nearest = stops.filter { firstRow - $0.midY < 20 }.min {
            abs($0.midY - tab.midY) + abs($0.midX - tab.midX) < abs($1.midY - tab.midY) +
                abs($1.midX - tab.midX)
        }
        #expect(nearest
            .map { abs($0.midX - selectorFrame.midX) < 4 && abs($0.midY - selectorFrame.midY) < 4 } == true)
        await harness.send(.down)
        await harness.pause(200)
        #expect(harness.focusedFrame.maxY < selectorFrame.minY)
        await harness.send(.up)
        await harness.pause(200)
        #expect(harness.focusedView === selector)
    }

    @Test func navigatingDownKeepsTheFocusedControlOnScreen() async {
        let root = FeatureFocusStores.rootStore(tab: .controls)
        let harness = controlsPanel(root)
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(900)
        let bounds = harness.window.contentView?.bounds ?? .zero
        var lowest = CGFloat.greatestFiniteMagnitude
        for _ in 0..<16 {
            await harness.send(.down)
            await harness.pause(400)
            let frame = harness.focusedFrame
            lowest = min(lowest, frame.minY)
            #expect(bounds.contains(frame), "\(frame)")
        }
        #expect(lowest < bounds.midY)
    }

    @Test(arguments: [false, true]) func focusRevealSkipsSelfManagedScrollViews(managed: Bool) async {
        let harness = MenuFocusHarness(width: 300, height: 300) { _ in
            MenuFocusHostingView(rootView: ScrollView {
                VStack(spacing: 0) {
                    Color.gray.frame(height: 900)
                    FocusButton("Bottom") {}
                        .frame(height: 40)
                }
                .background {
                    if managed {
                        SelfManagedFocusScrolling()
                    }
                }
            }
            .frame(width: 300, height: 300))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(300)
        let stops = AppKitKeyViews.navigationStops(in: harness.window)
        guard let bottom = stops.min(by: {
            $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY
        }) else {
            Issue.record("No stop found")
            return
        }
        harness.window.makeFirstResponder(bottom)
        AppKitScrollReveal.revealFocus(in: harness.window)
        await harness.pause(400)
        let visible = harness.window.contentView?.bounds.contains(harness.focusedFrame) == true
        #expect(visible == !managed)
    }

    @Test func shoulderButtonsSwitchSettingsTabsBeforeThePanelKnowsItsWindow() async {
        let store = FeatureFocusStores.settingsStore(tab: .controls)
        let harness = MenuFocusHarness(width: 1300, height: 800) { _ in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: nil
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        var navigation = ControllerNavigationState()
        navigation.setRoute(.menu)
        harness.perform(navigation.button(10, down: true, now: 0), in: harness.window)
        _ = navigation.button(10, down: false, now: 0.1)
        await harness.pause(200)
        #expect(store.route == .interface)
        harness.perform(navigation.button(9, down: true, now: 1), in: harness.window)
        _ = navigation.button(9, down: false, now: 1.1)
        await harness.pause(200)
        #expect(store.route == .controls)
    }
}
