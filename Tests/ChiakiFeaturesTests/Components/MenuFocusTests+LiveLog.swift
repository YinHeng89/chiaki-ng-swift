import ChiakiModels
import ChiakiDiagnostics
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

extension MenuFocusTests {
    @Test func loggingTogglesAreReachableFromTheLoggingTab() async {
        let store = FeatureFocusStores.settingsStore(tab: .developer)
        let harness = MenuFocusHarness(width: 1400, height: 900) { window in
            MenuFocusHostingView(rootView: SettingsView(
                store: store, pageLayoutWidth: 1180, window: window
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(400)
        let before = store.logSettings.showLiveLogButton
        await harness.send([.down, .up, .down])
        await harness.pause(200)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(store.logSettings.showLiveLogButton != before)
    }

    @Test func homeTopRowAndDeveloperLogPanelAreReachable() async {
        let settings = FeatureFocusStores.rootStore()
        let log = liveLogStore()
        let quitRequests = QuitRequestCounter()
        let harness = MenuFocusHarness(width: 1200, height: 800) { _ in
            MenuFocusHostingView(rootView: Color.clear
                .overlay(alignment: .topTrailing) {
                    LiveLogControl(
                        store: log, failure: nil, size: CGSize(width: 1200, height: 800),
                        trailingInset: 114, inStream: false, allowsQuit: true, showsButton: true
                    )
                }
                .modifier(SettingsPanelPresentation(showsQuit: true, root: settings))
                .environment(\.liveLogButtonShown, true)
                .environment(\.requestQuit, quitRequests.action))
        }
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        NotificationCenter.default.post(name: .focusSettingsControl, object: harness.window)
        await harness.pause(200)
        let settingsFrame = harness.focusedFrame
        await harness.send(.left)
        await harness.pause(150)
        #expect(LiveLogFocus.focus(in: harness.window) == .button)
        #expect(harness.focusedFrame.maxX < settingsFrame.minX)
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(log.visible)
        await walkDeveloperLogPanel(harness)
        await harness.send(.back)
        await harness.pause(200)
        #expect(!log.visible)
        #expect(LiveLogFocus.focus(in: harness.window) == .button)
        let baseline = quitRequests.count
        await harness.send(.back)
        #expect(quitRequests.count == baseline + 1)
        await harness.send(.right)
        await harness.pause(150)
        #expect(LiveLogFocus.focus(in: harness.window) == nil)
        #expect(abs(harness.focusedFrame.midX - settingsFrame.midX) < 4)
    }

    @Test func theStreamDockLogItemOpensTheLogAndBackReturnsToIt() async {
        let menu = streamMenuStore()
        let log = liveLogStore()
        let harness = MenuFocusHarness(width: 1200, height: 800) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(store: menu, stopTitle: "Disconnect")
                .overlay(alignment: .topTrailing) {
                    LiveLogControl(
                        store: log, failure: nil, size: CGSize(width: 1200, height: 800),
                        trailingInset: 58, inStream: true, allowsQuit: false, showsButton: false
                    )
                }
                .environment(\.liveLogButtonShown, true))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            _ = testNavigator.inputMode.pointerAction()
            override.restore()
            harness.close()
        }
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(300)
        await moveToTheDockEnd(harness)
        await harness.send(.left)
        await harness.pause(150)
        await harness.send(.confirm)
        await harness.pause(250)
        #expect(log.visible)
        #expect(LiveLogFocus.focus(in: harness.window) == .pauseResume)
        await harness.send(.back)
        await harness.pause(250)
        #expect(!log.visible)
        #expect(LiveLogFocus.focus(in: harness.window) == nil)
        #expect(menu.navigation.level == .panel)
        await harness.send(.confirm)
        await harness.pause(250)
        #expect(log.visible)
    }

    @Test func backOnTheLogButtonOnlyAsksToQuitWhereQuitIsOffered() async {
        let log = liveLogStore()
        let quitRequests = QuitRequestCounter()
        let harness = MenuFocusHarness(width: 900, height: 600) { _ in
            MenuFocusHostingView(rootView: Color.clear.overlay(alignment: .topTrailing) {
                LiveLogControl(
                    store: log, failure: nil, size: CGSize(width: 900, height: 600),
                    trailingInset: 58, inStream: false, allowsQuit: false, showsButton: true
                )
            }
            .environment(\.requestQuit, quitRequests.action))
        }
        defer {
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        NotificationCenter.default.post(name: .focusLiveLogButton, object: harness.window)
        await harness.pause(200)
        #expect(LiveLogFocus.focus(in: harness.window) == .button)
        await harness.send(.back)
        await harness.pause(100)
        #expect(quitRequests.count == 0)
    }

    @Test func closingTheStreamMenuReleasesTheLogPanel() async {
        let menu = streamMenuStore()
        let log = liveLogStore()
        let harness = MenuFocusHarness(width: 1200, height: 800) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(store: menu, stopTitle: "Disconnect")
                .overlay(alignment: .topTrailing) {
                    LiveLogControl(
                        store: log, failure: nil, size: CGSize(width: 1200, height: 800),
                        trailingInset: 58, inStream: true, allowsQuit: false, showsButton: false
                    )
                }
                .environment(\.liveLogButtonShown, true))
        }
        let other = HeadlessWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            _ = testNavigator.inputMode.pointerAction()
            override.restore()
            other.close()
            harness.close()
        }
        _ = testNavigator.inputMode.controllerInput()
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(300)
        await moveToTheDockEnd(harness)
        await harness.send([.left, .confirm])
        await harness.pause(250)
        #expect(LiveLogFocus.focus(in: harness.window) == .pauseResume)
        #expect(LiveLogFocus.focus(in: other) == nil)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(300)
        #expect(LiveLogFocus.focus(in: harness.window) == nil)
        #expect(!testNavigator.hasControlFocus(in: harness.window))
    }
}

@MainActor
private func moveToTheDockEnd(_ harness: MenuFocusHarness) async {
    var previous = harness.focusedFrame
    for _ in 0..<14 {
        await harness.send(.right)
        await harness.pause(120)
        if harness.focusedFrame == previous {
            return
        }
        previous = harness.focusedFrame
    }
}

@MainActor
private func liveLogStore() -> StoreOf<LiveLogReducer> {
    Store(initialState: LiveLogReducer.State()) {
        LiveLogReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.continuousClock = ContinuousClock()
    }
}

@MainActor
private func walkDeveloperLogPanel(_ harness: MenuFocusHarness) async {
    let path: [(MenuCommand, LiveLogFocus)] = [
        (.down, .pauseResume), (.right, .copy), (.right, .close), (.down, .follow),
        (.up, .close), (.up, .button), (.down, .pauseResume)
    ]
    for (command, expected) in path {
        await harness.send(command)
        await harness.pause(120)
        #expect(LiveLogFocus.focus(in: harness.window) == expected, "\(command)")
    }
}

@MainActor
private final class QuitRequestCounter {
    private(set) var count = 0

    var action: RequestQuitAction {
        RequestQuitAction { [weak self] _ in
            self?.count += 1
        }
    }
}

@MainActor
private func streamMenuStore() -> StoreOf<StreamMenuReducer> {
    Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.streamSession.loadTuning = { _ in
            StreamTuningConfiguration(nativeHeight: 1080)
        }
        $0.streamSession.saveTuning = { _, _ in
        }
    }
}
