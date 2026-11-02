import ChiakiDiagnostics
import ChiakiModels
@testable import ChiakiFeatures
import DesignSystem
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Synchronization
import Testing
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func nativeSettingsControlsParticipateInKeyViewLoop() async {
        _ = NSApplication.shared
        let probe = FocusProbe()
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: ControlsFocusFixture(probe: probe))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        var visited = Set<Int>()
        for _ in 0..<12 {
            testNavigator.move(backward: false, in: window)
            await settle(host)
            if let focus = probe.focus {
                visited.insert(focus)
            }
        }
        #expect(visited == [0, 1, 2, 3, 4])
    }

    @Test func settingsButtonsShowTheirFocusedHighlight() async {
        _ = NSApplication.shared
        let probe = FocusProbe()
        let host = MenuFocusHostingView(rootView: VStack {
            FocusButton {} label: {
                FocusHighlightLabel(index: 0, probe: probe)
            }
            FocusButton {} label: {
                FocusHighlightLabel(index: 1, probe: probe)
            }
        }.environment(\.settingsMenuFocus, true))
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 260),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        window.makeFirstResponder(nil)
        testNavigator.move(backward: false, in: window)
        await settle(host)
        #expect(probe.highlighted == [0])
        testNavigator.move(backward: false, in: window)
        await settle(host)
        #expect(probe.highlighted == [1])
    }

    @Test func settingsTabsRespondToDirectionalAndShoulderNavigation() async {
        _ = NSApplication.shared
        var state = SettingsFeature.State()
        state.psnReach = .signedIn
        state.route = .developer
        let store = Store(initialState: state) { SettingsFeature() } withDependencies: {
            $0.logSettings = .testValue
            $0.controllers = .testValue
            $0.uuid = .incrementing
            $0.kakusan.identity = {
                throw KakusanError.internal
            }
            $0.kakusan.peers = {
                []
            }
            $0.kakusan.loadSettings = {
                KakusanSettings()
            }
        }
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: SettingsView(
            store: store,
            pageLayoutWidth: 700,
            window: window
        ))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)

        let beforeDeveloper: SettingsRoute = KakusanBuild.included
            ? .remotePlayers
            : .network
        testNavigator.perform(.left, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.route == .developer)

        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.route == beforeDeveloper)

        testNavigator.perform(.right, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.route == beforeDeveloper)

        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.route == .developer)

        testNavigator.perform(.previous, in: window)
        await settle(host)
        #expect(store.route == beforeDeveloper)

        testNavigator.perform(.next, in: window)
        await settle(host)
        #expect(store.route == .developer)
    }

    @Test func settingsTabsSkipPSNOnlyTabsWithoutASignedInAccount() async {
        _ = NSApplication.shared
        let store = FeatureFocusStores.settingsStore(tab: .developer, reach: .localOnly)
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: SettingsView(
            store: store,
            pageLayoutWidth: 700,
            window: window
        ))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)

        testNavigator.perform(.next, in: window)
        await settle(host)
        #expect(store.route == .caches)

        testNavigator.perform(.next, in: window)
        await settle(host)
        #expect(store.route == .requests)

        testNavigator.perform(.next, in: window)
        await settle(host)
        #expect(store.route == .about)

        testNavigator.perform(.next, in: window)
        await settle(host)
        #expect(store.route == .picture)

        testNavigator.perform(.previous, in: window)
        await settle(host)
        #expect(store.route == .about)
    }

    @Test func narrowSettingsTabsFallBackToSymbolsAndStayNavigable() async {
        _ = NSApplication.shared
        let store = FeatureFocusStores.settingsStore(tab: .developer, reach: .signedIn)
        let compact = ScreenLayout(room: .compact, stature: .short, touch: true)
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 380),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: SettingsView(
            store: store,
            pageLayoutWidth: 560,
            window: window
        ).environment(\.screenLayout, compact))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        try? await Task.sleep(for: .milliseconds(200))
        await settle(host)

        let tabs = store.tabs
        let tabFrame = AppKitKeyViews.focusFrame(window.firstResponder) ?? .zero
        #expect(stopsInRow(of: tabFrame, in: window).count == tabs.count)
        #expect(tabFrame.height >= ScreenLayout.touchTarget)
        #expect(tabFrame.maxX <= 560)

        let index = tabs.firstIndex(of: .developer) ?? 0
        let before = tabs[(index + tabs.count - 1) % tabs.count]
        testNavigator.perform(.left, in: window) { window.sendEvent($0) }
        await settle(host)
        testNavigator.perform(.confirm, in: window) { window.sendEvent($0) }
        await settle(host)
        #expect(store.route == before)

        testNavigator.perform(.next, in: window)
        await settle(host)
        #expect(store.route == .developer)
        testNavigator.perform(.previous, in: window)
        await settle(host)
        #expect(store.route == before)
        let movedFrame = AppKitKeyViews.focusFrame(window.firstResponder) ?? .zero
        #expect(abs(movedFrame.midY - tabFrame.midY) <= 2)
    }

    @Test func settingsRowStacksItsControlUnderTheLabelWhenNarrow() async {
        let compact = ScreenLayout(room: .compact, stature: .tall, touch: true)
        let row = SettingsRow("A title too long to sit beside its control", detail: "Says more.") {
            FocusButton("Choose") {}.glassControlStyle()
        }
        let wide = MenuFocusHarness(width: 700, height: 200) { _ in
            MenuFocusHostingView(rootView: row.padding().environment(\.screenLayout, compact))
        }
        let narrow = MenuFocusHarness(width: 360, height: 200) { _ in
            MenuFocusHostingView(rootView: row.padding().environment(\.screenLayout, compact))
        }
        defer {
            wide.close()
            narrow.close()
        }
        await wide.open()
        wide.window.recalculateKeyViewLoop()
        wide.window.selectNextKeyView(nil)
        await wide.settle()
        let sideBySide = wide.focusedFrame
        #expect(sideBySide.minX > 350)

        await narrow.open()
        narrow.window.recalculateKeyViewLoop()
        narrow.window.selectNextKeyView(nil)
        await narrow.settle()
        let stacked = narrow.focusedFrame
        #expect(stacked.width > 0)
        #expect(stacked.minX < 60)
        #expect(stacked.minY != sideBySide.minY || stacked.minX != sideBySide.minX)
    }

    @Test func settingsPanelFocusesTheCurrentTabBeforeTraversingItsControls() async {
        let root = FeatureFocusStores.rootStore()
        let harness = MenuFocusHarness(width: 900, height: 650) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: root)
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(800)
        harness.perform([.down], in: window)
        await harness.pause(150)
        let entryFrame = harness.focusedFrame
        #expect(harness.focusedView.map(AppKitKeyViews.isNavigationStop) == true)
        expectFirstControlBelowTabs(entryFrame, tabs: root.settings.tabs.count, in: window)

        var frames = [entryFrame]
        for _ in 0..<8 {
            testNavigator.move(backward: false, in: window)
            await harness.settle()
            #expect(!(harness.focusedView is KeyBindingCapture.CaptureView))
            let frame = harness.focusedFrame
            if let last = frames.last {
                #expect(abs(frame.midX - last.midX) > 2 || abs(frame.midY - last.midY) > 2)
            }
            frames.append(frame)
        }

        for _ in 0..<frames.count - 1 {
            testNavigator.move(backward: true, in: window)
            await harness.settle()
        }
        let backFrame = harness.focusedFrame
        #expect(abs(backFrame.midX - entryFrame.midX) <= 2)
        #expect(abs(backFrame.midY - entryFrame.midY) <= 2)
    }

    @Test func aPressWhileSettingsSlidesInFocusesTheCurrentTab() async {
        let root = FeatureFocusStores.rootStore()
        let harness = MenuFocusHarness(width: 900, height: 650) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: root)
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        harness.perform([.down], in: window)
        var settled = CGRect.null
        await waitUntil(harness, attempts: 100) {
            let frame = harness.focusedFrame
            defer {
                settled = frame
            }
            return frame == settled && stopsInRow(of: frame, in: window).count == root.settings.tabs.count
        }
        let tabFrame = harness.focusedFrame
        #expect(stopsInRow(of: tabFrame, in: window).count == root.settings.tabs.count)

        harness.perform([.down], in: window)
        settled = .null
        await waitUntil(harness, attempts: 100) {
            let frame = harness.focusedFrame
            defer {
                settled = frame
            }
            return frame == settled && frame != tabFrame
                && harness.focusedView.map(AppKitKeyViews.isNavigationStop) == true
        }
        let entryFrame = harness.focusedFrame
        #expect(harness.focusedView.map(AppKitKeyViews.isNavigationStop) == true)
        expectFirstControlBelowTabs(entryFrame, tabs: root.settings.tabs.count, in: window)
    }

    @Test func switchingToAndFromPictureKeepsThePanelSizeAndTabFocus() async {
        let root = FeatureFocusStores.rootStore(tab: .sound)
        let harness = MenuFocusHarness(width: 1300, height: 800) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: root)
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(800)
        let soundTab = harness.focusedFrame
        #expect(stopsInRow(of: soundTab, in: window).count == root.settings.tabs.count)

        await harness.send(.left)
        let pictureTab = harness.focusedFrame
        #expect(pictureTab.maxX <= soundTab.minX)
        harness.perform([.confirm], in: window)
        await harness.pause(400)
        #expect(root.settings.route == .picture)
        #expect(harness.focusedFrame == pictureTab)
        #expect(stopsInRow(of: pictureTab, in: window).count == root.settings.tabs.count)

        harness.perform([.next], in: window)
        await harness.pause(400)
        #expect(root.settings.route == .sound)
        #expect(harness.focusedFrame == soundTab)
    }

    @Test func upFromSettingsTabsReachesCloseAndSwitchingTabsKeepsTabFocus() async {
        let root = FeatureFocusStores.rootStore(tab: .developer)
        let harness = MenuFocusHarness(width: 1100, height: 800) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(
                SettingsPanelPresentation(startsPresented: true, root: root)
            ))
        }
        let window = harness.window
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(800)
        let developerTab = harness.focusedFrame
        #expect(stopsInRow(of: developerTab, in: window).count == root.settings.tabs.count)

        await harness.send(.up)
        let close = harness.focusedFrame
        #expect(close.minY > developerTab.maxY)
        #expect(close.width < 60)
        #expect(root.settings.route == .developer)

        await harness.send(.down)
        #expect(harness.focusedFrame == developerTab)
        await harness.send(.left)
        let tabFrame = harness.focusedFrame
        harness.perform([.confirm], in: window)
        await harness.pause(400)
        let tabs = root.settings.tabs
        let developerIndex = tabs.firstIndex(of: .developer) ?? tabs.endIndex
        #expect(root.settings.route == tabs[developerIndex - 1])
        let entryFrame = harness.focusedFrame
        #expect(abs(entryFrame.midY - tabFrame.midY) <= 2)
        #expect(entryFrame.height < 120)

        harness.perform([.previous], in: window)
        await harness.pause(400)
        #expect(root.settings.route == tabs[developerIndex - 2])
        let shoulderFrame = harness.focusedFrame
        #expect(abs(shoulderFrame.midY - tabFrame.midY) <= 2)
        #expect(shoulderFrame.height < 120)
    }

    @Test func verticalNavigationStaysInTheCurrentColumn() async {
        _ = NSApplication.shared
        let probe = GridFocusProbe()
        let window = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = MenuFocusHostingView(rootView: ColumnsFixture(probe: probe))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        await settle(host)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(probe.focus == "right1")

        #expect(testNavigator.moveGeometric(.down, in: window))
        await settle(host)
        #expect(probe.focus == "right2")
        #expect(testNavigator.moveGeometric(.down, in: window))
        await settle(host)
        #expect(probe.focus == "right3")
        #expect(!testNavigator.moveGeometric(.down, in: window))
        #expect(testNavigator.moveGeometric(.up, in: window))
        await settle(host)
        #expect(probe.focus == "right2")
    }

    private func stopsInRow(of frame: CGRect, in window: PlatformWindow) -> [CGRect] {
        AppKitKeyViews.navigationStops(in: window).compactMap {
            AppKitKeyViews.focusFrame($0)
        }.filter {
            abs($0.midY - frame.midY) <= 2
        }
    }

    private func expectFirstControlBelowTabs(_ entryFrame: CGRect, tabs: Int, in window: PlatformWindow) {
        let rows = Dictionary(grouping: AppKitKeyViews.navigationStops(in: window).compactMap {
            AppKitKeyViews.focusFrame($0)
        }) {
            Int($0.midY.rounded())
        }
        let tabRow = rows.keys.filter { row in
            rows.filter {
                abs($0.key - row) <= 2
            }.values.map(\.count).reduce(0, +) == tabs
        }.max() ?? 0
        #expect(entryFrame.maxY <= CGFloat(tabRow))
        #expect(!rows.keys.contains {
            $0 > Int(entryFrame.midY) + 4 && $0 < tabRow - 4
        })
    }
}
