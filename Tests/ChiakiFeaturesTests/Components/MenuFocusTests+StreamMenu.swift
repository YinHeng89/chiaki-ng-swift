import ChiakiModels
import DesignSystem
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
@testable import ChiakiFeatures
import MenuFocus
import ChiakiTestSupport

@MainActor
private final class StreamMenuProbe {
    var request: StreamMenuControl?
    var focused: StreamMenuFocusTarget?
    var activated = [StreamMenuControl]()
}

private struct StreamMenuPanelHost: View {
    let panel: StreamMenuPanel
    let probe: StreamMenuProbe
    var goHome: (() -> Void)?
    var openSavedData: (() -> Void)?
    @State var configuration: StreamTuningConfiguration
    @State var tick = 0
    @MenuFocusState var focus: StreamMenuFocusTarget?

    var body: some View {
        StreamMenuPanelContent(
            panel: panel,
            configuration: $configuration,
            statistics: RenderStatistics(),
            diagnosticsLevel: .constant(.off),
            diagnosticsGlass: .constant(.regular),
            diagnosticsLayout: .constant(.sheet),
            videoAnalysis: .constant(.off),
            troubleshootTopic: .constant(.wifi),
            frameGenerationEligible: true,
            stopTitle: "Stop",
            stop: {},
            goHome: goHome,
            openSavedData: openSavedData,
            focus: $focus
        )
        .environment(\.streamMenuActivate) { control in
            probe.activated.append(control)
            return true
        }
        .onChange(of: focus) { _, value in
            probe.focused = value
        }
        .task {
            while !Task.isCancelled {
                if let request = probe.request {
                    probe.request = nil
                    focus = .control(request)
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}

extension MenuFocusTests {
    @Test(arguments: [
        (StreamMenuPanel.picture, [StreamMenuControl.pictureGenerated]),
        (StreamMenuPanel.colour, [StreamMenuControl.colourBrightness]),
        (StreamMenuPanel.sound, [StreamMenuControl.soundVolume]),
        (StreamMenuPanel.sound, [StreamMenuControl.soundAudio3D, .soundSpatial])
    ])
    func streamMenuPanelControlsTakeFocusAndActivate(
        panel: StreamMenuPanel,
        controls: [StreamMenuControl]
    ) async {
        let configuration = StreamTuningConfiguration(frameGenerationAvailable: true)
        let probe = StreamMenuProbe()
        let harness = MenuFocusHarness(width: 700, height: 700) { _ in
            MenuFocusHostingView(rootView: StreamMenuPanelHost(
                panel: panel,
                probe: probe,
                configuration: configuration
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        for control in controls {
            probe.request = control
            await harness.pause(150)
            #expect(probe.focused == .control(control), "\(control) did not take focus")
            harness.perform([.confirm], in: harness.window)
            await harness.pause(100)
            #expect(probe.activated.last == control, "\(control) did not activate")
        }
    }

    @Test(arguments: [
        (StreamMenuPanel.picture, StreamMenuControl.pictureOutput,
         StreamTuningConfiguration(nativeHeight: 1080)),
        (StreamMenuPanel.stream, StreamMenuControl.streamResolution,
         StreamTuningConfiguration(launchOptions: .cloud("pscloud")))
    ])
    func streamMenuDropdownTakesControllerFocus(
        panel: StreamMenuPanel,
        control: StreamMenuControl,
        configuration: StreamTuningConfiguration
    ) async {
        let probe = StreamMenuProbe()
        let harness = MenuFocusHarness(width: 700, height: 700) { _ in
            NSHostingView(rootView: StreamMenuPanelHost(
                panel: panel,
                probe: probe,
                configuration: configuration
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        probe.request = control
        await harness.pause(150)
        #expect(probe.focused == .control(control))
        #expect(harness.focusedView != nil)
    }
}

@MainActor
private final class StatisticsChoices {
    var request: StreamMenuControl?
    var focused: StreamMenuFocusTarget?
    var level = StreamDiagnosticsAppearance.Level.off
    var glass = StreamDiagnosticsAppearance.Glass.regular
    var layout = StreamDiagnosticsAppearance.Layout.sheet
    var analysis = StreamVideoAnalysisMode.off
}

private struct StreamStatisticsPanelHost: View {
    let probe: StatisticsChoices
    @State var level = StreamDiagnosticsAppearance.Level.off
    @State var glass = StreamDiagnosticsAppearance.Glass.regular
    @State var layout = StreamDiagnosticsAppearance.Layout.sheet
    @State var analysis = StreamVideoAnalysisMode.off
    @MenuFocusState var focus: StreamMenuFocusTarget?

    var body: some View {
        StreamMenuPanelContent(
            panel: .statistics,
            configuration: .constant(StreamTuningConfiguration()),
            statistics: RenderStatistics(),
            diagnosticsLevel: $level,
            diagnosticsGlass: $glass,
            diagnosticsLayout: $layout,
            videoAnalysis: $analysis,
            troubleshootTopic: .constant(.wifi),
            frameGenerationEligible: false,
            stopTitle: "Stop",
            stop: {},
            focus: $focus
        )
        .environment(\.streamMenuActivate) { _ in
            false
        }
        .onChange(of: focus) { _, value in
            probe.focused = value
        }
        .onChange(of: level) { _, value in
            probe.level = value
        }
        .onChange(of: glass) { _, value in
            probe.glass = value
        }
        .onChange(of: layout) { _, value in
            probe.layout = value
        }
        .onChange(of: analysis) { _, value in
            probe.analysis = value
        }
        .task {
            while !Task.isCancelled {
                if let request = probe.request {
                    probe.request = nil
                    focus = .control(request)
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}

extension MenuFocusTests {
    @Test func dockHandleOpensTheMenuWithOneTapOnTouchAndOnlyWidensTheDockForAPointer() async {
        for touch in [true, false] {
            let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
                StreamMenuReducer()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.streamSession.loadTuning = { _ in
                    StreamTuningConfiguration(nativeHeight: 1080)
                }
                $0.streamSession.saveTuning = { _, _ in
                }
            }
            let layout = ScreenLayout(room: .compact, stature: .short, touch: touch, sideInset: 59)
            let harness = MenuFocusHarness(width: 852, height: 393) { _ in
                MenuFocusHostingView(
                    rootView: StreamMenuOverlay(store: store, stopTitle: "Disconnect")
                        .environment(\.screenLayout, layout)
                )
            }
            await harness.open()
            let override = KeyWindowOverride(harness.window)
            defer {
                override.restore()
                harness.close()
            }
            await harness.pause(300)
            #expect(store.navigation.level == .gameplay)
            let handleHeight = max(32, layout.controlSize)
            click(CGPoint(x: 426, y: 18 + handleHeight / 2), in: harness.window)
            await harness.pause(400)
            #expect(store.navigation.level == (touch
                    ? .panel
                    : .gameplay), "touch \(touch)")
        }
    }

    @Test func statisticsPanelLevelGlassLayoutAndAnalysisRowsTakeFocusAndSelect() async {
        let probe = StatisticsChoices()
        let harness = MenuFocusHarness(width: 760, height: 600) { _ in
            MenuFocusHostingView(rootView: StreamStatisticsPanelHost(probe: probe))
        }
        defer {
            harness.close()
        }
        await harness.open()
        let choices: [StreamMenuControl] = [
            .statisticsOverlay(StreamDiagnosticsAppearance.Level.standard.rawValue),
            .diagnosticsGlass(StreamDiagnosticsAppearance.Glass.clearDimmed.rawValue),
            .diagnosticsLayout(StreamDiagnosticsAppearance.Layout.floating.rawValue),
            .videoAnalysis(StreamVideoAnalysisMode.hdrHeatmap.rawValue)
        ]
        for control in choices {
            probe.request = control
            await harness.pause(150)
            #expect(probe.focused == .control(control), "\(control) did not take focus")
            harness.perform([.confirm], in: harness.window)
            await harness.pause(150)
        }
        #expect(probe.level == .standard)
        #expect(probe.glass == .clearDimmed)
        #expect(probe.layout == .floating)
        #expect(probe.analysis == .hdrHeatmap)
    }

    @Test func sessionPanelHomeButtonTakesControllerFocusAndGoesHome() async {
        let probe = StreamMenuProbe()
        var homeRequests = 0
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            MenuFocusHostingView(rootView: StreamMenuPanelHost(
                panel: .session,
                probe: probe,
                goHome: {
                    homeRequests += 1
                },
                configuration: StreamTuningConfiguration()
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        probe.request = .sessionHome
        await harness.pause(150)
        #expect(probe.focused == .control(.sessionHome))
        harness.perform([.confirm], in: harness.window)
        await harness.pause(100)
        #expect(homeRequests == 1)
        probe.request = .sessionStop
        await harness.pause(150)
        #expect(probe.focused == .control(.sessionStop))
    }

    @Test func sessionPanelSavedDataButtonTakesControllerFocusAndOpensSavedData() async {
        let probe = StreamMenuProbe()
        var savedDataRequests = 0
        let harness = MenuFocusHarness(width: 700, height: 500) { _ in
            MenuFocusHostingView(rootView: StreamMenuPanelHost(
                panel: .session,
                probe: probe,
                openSavedData: {
                    savedDataRequests += 1
                },
                configuration: StreamTuningConfiguration()
            ))
        }
        defer {
            harness.close()
        }
        await harness.open()
        probe.request = .sessionSavedData
        await harness.pause(150)
        #expect(probe.focused == .control(.sessionSavedData))
        harness.perform([.confirm], in: harness.window)
        await harness.pause(100)
        #expect(savedDataRequests == 1)
        probe.request = .sessionStop
        await harness.pause(150)
        #expect(probe.focused == .control(.sessionStop))
    }
}

extension MenuFocusTests {
    @Test func streamChromeHidesWhileStreamingAndReturnsOnControllerFocus() async {
        let store = Store(initialState: StreamChromeReducer.State()) {
            StreamChromeReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        }
        let log = Store(initialState: LiveLogReducer.State()) {
            LiveLogReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = ContinuousClock()
        }
        let harness = MenuFocusHarness(width: 600, height: 400) { _ in
            MenuFocusHostingView(rootView: Color.clear
                .overlay(alignment: .topTrailing) {
                    LiveLogControl(
                        store: log, failure: nil, size: CGSize(width: 600, height: 400),
                        trailingInset: 0, inStream: true, allowsQuit: false, showsButton: true
                    )
                }
                .modifier(StreamChromePresentation(store: store, live: true)))
        }
        defer {
            _ = testNavigator.inputMode.pointerAction()
            harness.close()
        }
        _ = testNavigator.inputMode.pointerAction()
        await harness.open()
        NotificationCenter.default.post(name: .focusLiveLogButton, object: harness.window)
        await waitUntil(harness, attempts: 160) {
            !store.visibleCorners.contains(.topTrailing)
        }
        #expect(!store.visibleCorners.contains(.topTrailing))
        #expect(testNavigator.hasControlFocus(in: harness.window))
        _ = testNavigator.inputMode.controllerInput()
        await waitUntil(harness) {
            store.visibleCorners.contains(.topTrailing)
        }
        #expect(store.visibleCorners.contains(.topTrailing))
    }
}

@MainActor
final class KeyWindowOverride {
    private let method: Method
    private let original: IMP

    init(_ window: PlatformWindow) {
        method = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.keyWindow))!
        original = method_getImplementation(method)
        let block: @convention(block) (NSApplication) -> PlatformWindow? = { [weak window] _ in
            window
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    func restore() {
        method_setImplementation(method, original)
    }
}

extension MenuFocusTests {
    @Test func upFromPictureTabReachesItsControls() async {
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080)
            }
            $0.streamSession.saveTuning = { _, _ in
            }
        }
        let harness = MenuFocusHarness(width: 1000, height: 800) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(store: store, stopTitle: "Disconnect"))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(450)
        await harness.send([.up, .up, .right])
        await harness.pause(150)
        #expect(store.draft.upscaledOutput != .disabled)
    }
}

extension MenuFocusTests {
    @Test func upReachesUpscalerWhenItIsTheLastControl() async {
        let loaded = StreamTuningConfiguration(upscaledOutput: .quadHD, nativeHeight: 1080)
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                loaded
            }
            $0.streamSession.saveTuning = { _, _ in
            }
        }
        let harness = MenuFocusHarness(width: 1000, height: 900) { _ in
            MenuFocusHostingView(rootView: StreamMenuOverlay(store: store, stopTitle: "Disconnect"))
        }
        await harness.open()
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.pause(200)
        testNavigator.commands.send(.streamMenu, to: harness.window)
        await harness.pause(450)
        await harness.send([.up, .up, .right])
        await harness.pause(150)
        #expect(store.draft.upscaler == .advancedSpatial)
    }
}

extension MenuFocusTests {
    @Test func cloudLoadingQueueEstimateKeepsCancelControllerReachable() async {
        var cancelled = false
        let operation = TimedProgress(
            OperationProgress(step: .launch(.allocatingServer),
                              waitTimeEstimateSeconds: 245),
            at: Date()
        )
        let harness = MenuFocusHarness(width: 1000, height: 800) { _ in
            NSHostingView(rootView: StreamLoadingView(
                status: "Allocating a server", activeStep: 1, stepCount: 3,
                operation: operation, cancel: { cancelled = true }
            ))
        }
        let override = KeyWindowOverride(harness.window)
        defer {
            override.restore()
            harness.close()
        }
        await harness.open()
        await harness.pause(150)
        await harness.send(.confirm)
        #expect(cancelled)
    }
}

extension MenuFocusTests {
    @Test func optionsOpensSettingsOverStreamControlsButNotOverAPrompt() async {
        let store = FeatureFocusStores.rootStore()
        let harness = MenuFocusHarness(width: 1200, height: 800) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(SettingsPanelPresentation(root: store)))
        }
        let override = KeyWindowOverride(harness.window)
        let streamControls = UUID()
        let prompt = UUID()
        defer {
            testNavigator.inputGate.presentations.subtract([streamControls, prompt])
            testNavigator.inputGate.prompts.remove(prompt)
            override.restore()
            harness.close()
        }
        await harness.open()
        await harness.pause(200)
        testNavigator.inputGate.presentations.insert(streamControls)
        testNavigator.commands.send(.settings, to: harness.window)
        await harness.pause(200)
        #expect(testNavigator.inputGate.presentations.count == 2)
        testNavigator.commands.send(.settings, to: harness.window)
        await harness.pause(200)
        #expect(testNavigator.inputGate.presentations == [streamControls])
        testNavigator.inputGate.presentations.insert(prompt)
        testNavigator.inputGate.prompts.insert(prompt)
        testNavigator.commands.send(.settings, to: harness.window)
        await harness.pause(200)
        #expect(testNavigator.inputGate.presentations == [streamControls, prompt])
    }
}

extension MenuFocusTests {
    @Test func backOnTheSettingsOrPowerButtonAsksToQuit() async {
        let store = FeatureFocusStores.rootStore()
        let requests = LockIsolated(0)
        let harness = MenuFocusHarness(width: 1200, height: 800) { _ in
            MenuFocusHostingView(rootView: Color.clear.modifier(SettingsPanelPresentation(
                showsQuit: true,
                root: store
            ))
            .environment(\.requestQuit, RequestQuitAction { _ in
                requests.withValue {
                    $0 += 1
                }
            }))
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
        let baseline = requests.value
        await harness.send(.back)
        #expect(requests.value == baseline + 1)
        await harness.send(.right)
        await harness.pause(200)
        await harness.send(.back)
        #expect(requests.value == baseline + 2)
    }
}
