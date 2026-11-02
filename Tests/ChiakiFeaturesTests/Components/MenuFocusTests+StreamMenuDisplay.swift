@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import PlatformUI
import ComposableArchitecture
import SwiftUI
import Testing
import ChiakiTestSupport
import MenuFocus

extension MenuFocusTests {
    @Test func displayModeRowIsOneStopAndRevealsTheZoomSlider() async {
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(upscaledOutput: .quadHD, nativeHeight: 1080)
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
        await harness.send([.up, .right, .confirm])
        await harness.pause(150)
        #expect(store.draft.videoFit.mode == .zoom)
        await harness.send([.down, .confirm, .right, .right])
        await harness.pause(150)
        #expect(store.draft.videoFit.zoom > 1)
        await harness.send([.up, .up, .right])
        await harness.pause(150)
        #expect(store.draft.upscaler == .advancedSpatial)
        await harness.send([.down, .left, .confirm])
        await harness.pause(150)
        #expect(store.draft.videoFit.mode == .fit)
    }

    @Test func streamPanelReachesCloudLaunchSettingsAndOffersARestart() async {
        let saved = LockIsolated<[Int]>([])
        let store = Store(initialState: StreamMenuReducer.State(context: .cloud("pscloud"))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080, launchOptions: .cloud("pscloud"))
            }
            $0.streamSession.saveTuning = { _, configuration in
                saved.withValue {
                    $0.append(configuration.launch.height)
                }
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
        await harness.send([.right, .right, .right, .up])
        await harness.pause(300)
        await harness.send([.up, .up, .up])
        await harness.send(.right)
        await harness.pause(150)
        #expect(store.draft.launch.height == 1440)
        #expect(store.draft.restartNeeded)
        await harness.send([.down, .down, .down, .down])
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(saved.value == [1440])
        #expect(store.configuration.launch.height == 1440)
    }

    @Test func streamPanelOffersAReconnectAfterAConsoleFrameRateChange() async {
        let saved = LockIsolated<[Int]>([])
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080, launchOptions: .console(ps5: true))
            }
            $0.streamSession.saveTuning = { _, configuration in
                saved.withValue {
                    $0.append(configuration.launch.frameRate)
                }
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
        await harness.send([.right, .right, .right, .up])
        await harness.pause(300)
        await harness.send([.up, .up, .up])
        await harness.send(.right)
        await harness.pause(150)
        #expect(store.draft.launch.frameRate == 30)
        #expect(store.draft.restartNeeded)
        await harness.send([.down, .down, .down, .down])
        await harness.send(.confirm)
        await harness.pause(300)
        #expect(saved.value == [30])
        #expect(store.configuration.launch.frameRate == 30)
    }

    @Test func measureBrightnessLetsTheControllerMoveTheHeatmapMarker() async {
        let marker = MarkerCalls()
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080, launchOptions: .console(ps5: true))
            }
            $0.streamSession.statisticsSamples = {
                AsyncStream { continuation in
                    continuation.yield(StreamStatisticsSample(
                        statistics: RenderStatistics(fixture: ["pq": true]),
                        uptime: 1
                    ))
                }
            }
            $0.streamSession = marker.client(on: $0.streamSession)
            $0.continuousClock = ContinuousClock()
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
        await harness.send([.right, .right, .right, .right, .up])
        await harness.pause(300)
        await harness.send([.right, .right, .up, .left, .confirm])
        await harness.pause(150)
        #expect(store.diagnostics.analysis == .hdrHeatmap)
        await harness.send([.down, .confirm])
        await harness.pause(200)
        #expect(marker.placed.value == [.centre])
        #expect(marker.shown.value == [true])
        await harness.send([.right, .right, .down])
        await harness.pause(150)
        #expect(marker.nudges.value == [.right, .right, .down])
        await harness.send(.back)
        await harness.pause(200)
        #expect(marker.shown.value.last == false)
        await harness.send(.right)
        await harness.pause(150)
        #expect(marker.nudges.value == [.right, .right, .down])
        await harness.send(.confirm)
        await harness.pause(200)
        #expect(marker.placed.value == [.centre, .centre])
        #expect(marker.shown.value.last == true)
        await harness.send(.back)
        await harness.pause(150)
    }

    @Test func soundPanelVolumeIsReachableAndAdjustsWithDirections() async {
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(nativeHeight: 1080, volume: 0.5)
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
        await harness.send([.right, .right, .up, .up, .up])
        await harness.pause(300)
        await harness.send([.confirm, .left, .left])
        await harness.pause(150)
        #expect(abs(store.draft.volume - 0.4) < 0.001)
        await harness.send(Array(repeating: .right, count: 14))
        await harness.pause(150)
        #expect(store.draft.volume == 1)
        await harness.send(.back)
        #expect(abs(store.draft.volume - 0.5) < 0.001)
    }

    @Test func soundPanelTogglesAudio3DAndSpatialAudio() async {
        let cloud = await soundPanelSpatialAudio(context: .cloud("pscloud")) { harness in
            await harness.send([.up, .confirm])
        }
        #expect(cloud == SpatialAudio(audio3D: false))
        let cloudSpatial = await soundPanelSpatialAudio(context: .cloud("pscloud")) { harness in
            await harness.send(.confirm)
        }
        #expect(cloudSpatial == SpatialAudio(appleSpatial: false))
        let console = await soundPanelSpatialAudio(context: .console(.local, ps5: true)) { harness in
            await harness.send([.up, .confirm])
            await harness.pause(150)
            await harness.send([.down, .confirm])
        }
        #expect(console == SpatialAudio(audio3D: false, appleSpatial: false))
    }

    private func soundPanelSpatialAudio(
        context: StreamTuningContext,
        steps: (MenuFocusHarness) async -> Void
    ) async -> SpatialAudio {
        let store = Store(initialState: StreamMenuReducer.State(context: context)) {
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
        await harness.send([.right, .right, .up])
        await harness.pause(300)
        await steps(harness)
        await harness.pause(150)
        return store.draft.spatialAudio
    }

    @Test func soundPanelSkipsAudio3DOnPS4() async {
        let store = Store(initialState: StreamMenuReducer.State(context: .console(.local, ps5: false))) {
            StreamMenuReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.streamSession.loadTuning = { _ in
                StreamTuningConfiguration(
                    nativeHeight: 1080,
                    volume: 0.5,
                    spatialAudio: SpatialAudio(),
                    audio3DAvailable: false
                )
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
        await harness.send([.right, .right, .up, .up])
        await harness.pause(300)
        #expect(harness.focusedFrame != .zero)
        await harness.send([.confirm, .left])
        await harness.pause(150)
        #expect(abs(store.draft.volume - 0.45) < 0.001)
        await harness.send([.down, .up, .confirm, .left])
        await harness.pause(150)
        #expect(abs(store.draft.volume - 0.4) < 0.001)
        #expect(store.draft.spatialAudio == SpatialAudio())
    }
}

/// Records what the stream menu asked of the brightness marker.
private final class MarkerCalls: Sendable {
    /// Where the marker was placed.
    let placed = LockIsolated<[BrightnessMarker]>([])
    /// Each time the marker was shown or hidden.
    let shown = LockIsolated<[Bool]>([])
    /// The steps the marker was nudged.
    let nudges = LockIsolated<[BrightnessMarker.Nudge]>([])

    /// A client that records every marker call and keeps the rest of `base`.
    ///
    /// - Parameter base: The client whose other operations are kept.
    /// - Returns: The client.
    func client(on base: StreamSessionClient) -> StreamSessionClient {
        var client = base
        client.placeMarker = { [placed] point in
            placed.withValue {
                $0.append(point)
            }
        }
        client.showMarker = { [shown] visible in
            shown.withValue {
                $0.append(visible)
            }
        }
        client.nudgeMarker = { [nudges] nudge in
            nudges.withValue {
                $0.append(nudge)
            }
        }
        return client
    }
}
