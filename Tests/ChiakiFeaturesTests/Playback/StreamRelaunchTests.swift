@testable import ChiakiFeatures
import ChiakiClients
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

private let account = UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!
private let console = RegistrationFlow.ConsoleTarget(
    address: "127.0.0.1",
    kind: .ps5,
    id: UUID(uuidString: "00000000-0000-0000-0000-00000000BBBB")!
)
private let firstSession = StreamSessionID(uuid: UUID(0))

@MainActor @Test func aRelaunchClosesThePlayingStreamAndStartsTheSameConsoleAgain() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.menu(.delegate(.restartRequested))) {
        $0.session = .relaunching(firstSession)
    }
    #expect(store.state.isPresented)
    #expect(store.state.status == .connecting)
    await store.receive(.relaunchClosed(firstSession))
    #expect(calls.left.value == [firstSession])
    #expect(calls.exits.value == [.disconnect])
    #expect(calls.started.value.count == 2)
    let second = calls.started.value[1]
    #expect(second != firstSession)
    #expect(store.state.session.id == second)
    #expect(store.state.session.isStarting)
    #expect(store.state.target?.route == .local)
    await store.send(.event(firstSession, .firstFrame))
    #expect(store.state.session.isStarting)
    await store.send(.event(second, .firstFrame))
    #expect(store.state.status == .playing)
    await store.send(.stop)
    await store.receive(.stopped(second, .left))
}

@MainActor @Test func aRelaunchIsIgnoredUntilTheStreamIsPlaying() async {
    let calls = StreamSessionCalls()
    let store = calls.store()
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.menu(.delegate(.restartRequested)))
    #expect(store.state.session.isStarting)
    #expect(calls.left.value.isEmpty)
    await store.send(.stop)
    await store.receive(.stopped(firstSession, .left))
}

@MainActor @Test func aRelaunchKeepsTheStreamWindowAsItIs() async {
    let calls = StreamSessionCalls()
    let window = LockIsolated<[String]>([])
    let store = calls.store {
        $0.platform.enterFullScreen = {
            window.withValue {
                $0.append("full")
            }
        }
        $0.platform.restoreWindow = {
            window.withValue {
                $0.append("restore")
            }
        }
    }
    await store.send(.startConsole(account: account, console: console, route: .local))
    await store.send(.event(firstSession, .firstFrame))
    await store.send(.menu(.delegate(.restartRequested)))
    await store.receive(.relaunchClosed(firstSession))
    await store.send(.event(calls.started.value[1], .firstFrame))
    await store.skipInFlightEffects()
    #expect(!window.value.contains("restore"))
    await store.send(.stop)
    await store.skipReceivedActions()
}

@Test func consoleLaunchSettingsRoundTripThroughTheRouteProfile() {
    var settings = PictureSettings()
    settings.remote = StreamProfile(height: 720, fps: 60, bitrateMbps: 15, automaticBitrate: true)
    var launch = StreamLaunchSettings.console(settings, route: .remote, ps5: true)
    #expect(launch == StreamLaunchSettings(
        height: 720,
        frameRate: 60,
        codec: .hevc,
        hdr: true,
        bitrateMbps: 15
    ))
    launch.height = 1080
    launch.frameRate = 30
    launch.codec = .h264
    launch.hdr = false
    launch.automaticBitrate = false
    launch.bitrateMbps = 25
    let saved = launch.applied(to: settings, route: .remote, ps5: true)
    #expect(saved.remote.height == 1080)
    #expect(saved.remote.fps == 30)
    #expect(!saved.remote.automaticBitrate)
    #expect(saved.remote.bitrateMbps == 25)
    #expect(saved.remotePS5Codec == .h264)
    #expect(!saved.remotePS5HDR)
    #expect(saved.local == settings.local)
    #expect(StreamLaunchSettings.console(saved, route: .remote, ps5: true) == launch)
}

@Test func aPS4LaunchLeavesTheSharedResolutionAndCodecAlone() {
    let settings = PictureSettings()
    var launch = StreamLaunchSettings.console(settings, route: .local, ps5: false)
    #expect(launch.height == PictureSettings.ps4Height)
    launch.frameRate = 30
    let saved = launch.applied(to: settings, route: .local, ps5: false)
    #expect(saved.local.height == settings.local.height)
    #expect(saved.local.fps == 30)
    #expect(saved.localPS5Codec == settings.localPS5Codec)
    #expect(StreamLaunchOptions.console(ps5: false).heights.isEmpty)
}

@Test func cloudLaunchSettingsWriteOnlyTheirOwnService() {
    let settings = CloudPictureSettings()
    var launch = StreamLaunchSettings.cloud(settings, service: "psnow")
    launch.height = 720
    launch.hdr = false
    launch.quality = .stable
    launch.automaticBitrate = false
    launch.bitrateMbps = 12
    let saved = launch.applied(to: settings, service: "psnow")
    #expect(saved.psNowHeight == 720)
    #expect(!saved.psNowAutomaticBitrate)
    #expect(saved.psNowBitrateMbps == 12)
    #expect(saved.psCloudHeight == settings.psCloudHeight)
    #expect(saved.hdr == settings.hdr)
    #expect(saved.psCloudQuality == settings.psCloudQuality)
    var psCloud = StreamLaunchSettings.cloud(settings, service: "pscloud")
    psCloud.quality = .stable
    psCloud.hdr = false
    let cloudSaved = psCloud.applied(to: settings, service: "pscloud")
    #expect(cloudSaved.psCloudQuality == .stable)
    #expect(!cloudSaved.hdr)
    #expect(StreamLaunchOptions.cloud("psnow").hdr == false)
    #expect(StreamLaunchOptions.cloud("pscloud").relaunch == .restart)
}

@Test func onlyAChangedLaunchSettingAsksForARelaunch() {
    var configuration = StreamTuningConfiguration(nativeHeight: 1080, launchOptions: .console(ps5: true))
    #expect(!configuration.restartNeeded)
    configuration.upscaler = .advancedSpatial
    #expect(!configuration.restartNeeded)
    configuration.launch.codec = .h264
    #expect(configuration.restartNeeded)
    var guest = StreamTuningConfiguration()
    guest.launch.height = 720
    #expect(!guest.restartNeeded)
}
