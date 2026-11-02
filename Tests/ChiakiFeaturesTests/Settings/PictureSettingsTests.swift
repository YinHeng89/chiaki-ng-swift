@testable import ChiakiFeatures
import ChiakiModels
import ChiakiClients
import Foundation
import Testing
import ComposableArchitecture

@Test func existingPictureSettingsDefaultToMetalFX() throws {
    let console = Data(#"{"height":1080,"fps":60,"bitrateMbps":30,"codec":"H.264"}"#.utf8)
    let cloud = Data(
        #"{"psCloudHeight":1080,"psCloudBitrateMbps":20,"psNowHeight":720,"psNowBitrateMbps":15}"#.utf8
    )
    #expect(try JSONDecoder().decode(PictureSettings.self, from: console).upscaler == .metalFX)
    #expect(try JSONDecoder().decode(CloudPictureSettings.self, from: cloud).upscaler == .metalFX)
    #expect(
        try JSONDecoder().decode(PictureSettings.self, from: console).presentationFrameRate == .source
    )
    #expect(try JSONDecoder().decode(CloudPictureSettings.self, from: cloud).presentationFrameRate == .source)
}

@Test func generatedFramesFollowThirtyAndSixtyFPSStreams() {
    var settings = PictureSettings()
    settings.presentationFrameRate = .generated120
    #expect(settings.usesGenerated120(for: .local))
    settings.local.fps = 30
    #expect(settings.usesGenerated120(for: .local))
    settings.local.fps = 60
    settings.local.upscaledOutput = .fourK
    settings.local.height = 720
    #expect(settings.usesGenerated120(for: .local))
    #expect(settings.usesGenerated120(for: .remote))
}

@Test func cloudGeneratedFramesSupportHDAndFullHD() {
    var settings = CloudPictureSettings()
    settings.presentationFrameRate = .generated120
    settings.psCloudHeight = 1080
    settings.psNowHeight = 720
    #expect(settings.usesGenerated120(for: "pscloud"))
    #expect(settings.usesGenerated120(for: "psnow"))
}

@Test func storedSpatial3DSettingsAreIgnoredOnDecode() throws {
    let spatial = #""spatial3D":{"enabled":true,"output":"sideBySide","depthStrength":0.2}"#
    let console = Data(
        (#"{"local":{"height":1080,"fps":60,"bitrateMbps":30},"upscaler":"advancedSpatial","#
            + spatial + #","videoFit":{"mode":"zoom","zoom":1.5}}"#).utf8
    )
    let cloud = Data(
        (#"{"psCloudHeight":720,"upscaledOutput":"fullHD","presentationFrameRate":"generated120","#
            + spatial + "}").utf8
    )
    let picture = try JSONDecoder().decode(PictureSettings.self, from: console)
    #expect(picture.upscaler == .advancedSpatial)
    #expect(picture.local.height == 1080)
    #expect(picture.videoFit == VideoFit(mode: .zoom, zoom: 1.5))
    #expect(try picture.validated() == picture)
    let cloudPicture = try JSONDecoder().decode(CloudPictureSettings.self, from: cloud)
    #expect(cloudPicture.psCloudHeight == 720)
    #expect(cloudPicture.upscaledOutput == .fullHD)
    #expect(cloudPicture.presentationFrameRate == .generated120)
    #expect(try cloudPicture.validated() == cloudPicture)
}

private func delayedConsolePower(_ clock: TestClock<Duration>) -> SettingsClient {
    SettingsClient(
        read: { type in
            try? await clock.sleep(for: .seconds(1))
            return type.defaultSetting
        },
        write: { _ in
        }
    )
}

@MainActor @Test func streamMenuLoadsPreviewsAndPersistsTuning() async {
    let id = UUID()
    let clock = TestClock()
    let loaded = StreamTuningConfiguration(
        presentationFrameRate: .source, upscaledOutput: .fourK, upscaler: .metalFX, nativeHeight: 1080,
        frameGenerationAvailable: true
    )
    var edited = loaded
    edited.presentationFrameRate = .generated120
    edited.upscaler = .advancedSpatial
    let expected = edited
    let store = TestStore(initialState: StreamMenuReducer.State(context: .console(.local))) {
        StreamMenuReducer()
    } withDependencies: {
        $0.uuid = .constant(id)
        $0.streamSession.loadTuning = { context in
            #expect(context == .console(.local))
            return loaded
        }
        $0.streamSession.saveTuning = { context, value in
            #expect(context == .console(.local))
            #expect(value == expected)
        }
        $0.settings = delayedConsolePower(clock)
    }
    await store.send(.load) {
        $0.phase = .loading(id)
        $0.leaveLoad = id
    }
    await store.receive(.loaded(id, loaded)) {
        $0.phase = .ready
        $0.configuration = loaded
        $0.draft = loaded
        $0.hasLoaded = true
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.leaveActionLoaded(id, .ask)) {
        $0.leaveLoad = nil
    }
    await store.send(.edit(edited)) {
        $0.draft = edited
    }
    await store.send(.save) {
        $0.phase = .saving(id)
    }
    await store.receive(.saved(id, edited)) {
        $0.phase = .ready
        $0.configuration = edited
    }
}

@Test func disabledLegacyUpscalerMigratesToDisabledOutput() throws {
    let saved = Data(
        #"{"height":1080,"fps":60,"bitrateMbps":30,"codec":"H.264","upscaler":"disabled"}"#.utf8
    )
    let decoded = try JSONDecoder().decode(PictureSettings.self, from: saved)
    #expect(decoded.local.upscaledOutput == .disabled)
    #expect(decoded.remote.upscaledOutput == .disabled)
    #expect(decoded.upscaler == .metalFX)
}

@Test func disabledUpscalingPreservesSelectedStreamResolution() {
    var settings = PictureSettings()
    settings.local.height = 720
    settings.local.upscaledOutput = .disabled
    #expect(settings.profile(for: .local).height == 720)
    #expect(settings.local.upscaledOutput.height(source: 720) == 720)
}

@Test func upscaleTargetsRespectSourceResolution() throws {
    #expect(UpscaledOutput.available(for: 720) == [.disabled, .fullHD])
    #expect(UpscaledOutput.available(for: 1080) == [.disabled, .quadHD, .fourK])
    #expect(UpscaledOutput.quadHD.height(source: 1080) == 1440)
    #expect(UpscaledOutput.fourK.height(source: 1080) == 2160)
    var settings = PictureSettings()
    settings.local.height = 720
    #expect(throws: PictureSettingsError.self) {
        try settings.validated()
    }
    settings = settings.normalized()
    #expect(settings.local.upscaledOutput == .fullHD)
    #expect(try settings.validated() == settings)
    settings.local.height = 1080
    #expect(settings.normalized().local.upscaledOutput == .quadHD)
}

@Test func legacyPictureValuesMigrateWithinApprovedLimits() throws {
    let data = Data(#"{"height":720,"bitrateMbps":150,"upscaledOutput":"fourK"}"#.utf8)
    let decoded = try JSONDecoder().decode(PictureSettings.self, from: data)
    #expect(decoded.local.bitrateMbps == 100)
    #expect(decoded.local.automaticBitrate)
    #expect(decoded.local.upscaledOutput == .fullHD)
    #expect(decoded.remote == decoded.local)
    #expect(try decoded.validated() == decoded)
}

@Test func consoleCodecFollowsGenerationRegardlessOfLegacyPreference() throws {
    for legacy in ["H.264", "HEVC"] {
        let data = Data("{\"codec\":\"\(legacy)\"}".utf8)
        let settings = try JSONDecoder().decode(PictureSettings.self, from: data)
        #expect(settings.codec(forPS5: true, route: .local) == .hevc)
        #expect(settings.codec(forPS5: true, route: .remote) == .hevc)
        #expect(settings.codec(forPS5: false, route: .local) == .h264)
        let encoded = try JSONEncoder().encode(settings)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(object?["codec"] == nil)
    }
}

@Test func ps4StreamsDefaultTo720pUntilTheCoreDowngradesByServerType() throws {
    var settings = PictureSettings()
    settings.local.upscaledOutput = .fourK
    let ps4 = settings.profile(for: .local, ps5: false)
    #expect(ps4.height == 720)
    #expect(ps4.upscaledOutput == .fullHD)
    #expect(try ps4.validated() == ps4)
    #expect(settings.profile(for: .local, ps5: true) == settings.local)
    settings.local.height = 720
    #expect(settings.profile(for: .local, ps5: false) == settings.local.normalized())
}

@Test func consoleCodecDefaultsToHEVCWithAutomaticHDR() throws {
    let defaults = PictureSettings()
    #expect(defaults.localPS5Codec == .hevc)
    #expect(defaults.remotePS5Codec == .hevc)
    #expect(defaults.localPS5HDR)
    #expect(defaults.remotePS5HDR)
    let legacy = try JSONDecoder().decode(PictureSettings.self, from: Data("{\"height\":1080}".utf8))
    #expect(legacy.localPS5Codec == .hevc)
    #expect(legacy.remotePS5Codec == .hevc)
    #expect(legacy.localPS5HDR)
    #expect(legacy.remotePS5HDR)
    #expect(PictureSettings.Codec.choices.map(\.title) == ["H.264", "HEVC"])
}

@Test func savedHEVCHDRBecomesHEVCWithHDROn() throws {
    let saved = Data(#"{"localPS5Codec":"h265_hdr","remotePS5Codec":"h264"}"#.utf8)
    let settings = try JSONDecoder().decode(PictureSettings.self, from: saved)
    #expect(settings.localPS5Codec == .hevc)
    #expect(settings.localPS5HDR)
    #expect(settings.remotePS5Codec == .h264)
}

@Test func consoleCodecSelectionSendsTheReferenceCodecValues() {
    var settings = PictureSettings()
    settings.localPS5Codec = .hevcHDR
    settings.remotePS5Codec = .h264
    #expect(settings.codec(forPS5: true, route: .local) == .hevc)
    #expect(settings.launchCodec(forPS5: true, route: .local, displaySupportsHDR: true) == .hevcHDR)
    #expect(settings.codec(forPS5: true, route: .remote) == .h264)
    settings.localPS5Codec = .hevc
    #expect(settings.codec(forPS5: true, route: .local) == .hevc)
    for codec in PictureSettings.Codec.allCases {
        settings.localPS5Codec = codec
        settings.remotePS5Codec = codec
        #expect(settings.codec(forPS5: false, route: .local) == .h264)
        #expect(settings.codec(forPS5: false, route: .remote) == .h264)
    }
}

@Test func consoleCodecPersistsWithReferenceNames() throws {
    var settings = PictureSettings()
    settings.localPS5Codec = .hevc
    settings.remotePS5Codec = .h264
    settings.remotePS5HDR = false
    let encoded = try JSONEncoder().encode(settings)
    let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    #expect(object?["localPS5Codec"] as? String == "h265")
    #expect(object?["remotePS5Codec"] as? String == "h264")
    #expect(object?["remotePS5HDR"] as? Bool == false)
    #expect(try JSONDecoder().decode(PictureSettings.self, from: encoded) == settings)
}

@Test func savedSingleProfileBecomesBothHomeAndInternetProfiles() throws {
    let saved = Data(#"{"height":720,"fps":30,"bitrateMbps":12,"upscaledOutput":"fourK"}"#.utf8)
    let decoded = try JSONDecoder().decode(PictureSettings.self, from: saved)
    let expected = StreamProfile(height: 720, fps: 30, bitrateMbps: 12, upscaledOutput: .fullHD)
    #expect(decoded.local == expected)
    #expect(decoded.remote == expected)
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
    #expect(object?["height"] == nil)
    #expect(object?["local"] != nil && object?["remote"] != nil)
    #expect(try JSONDecoder().decode(PictureSettings.self, from: JSONEncoder().encode(decoded)) == decoded)
}

@Test func homeAndInternetProfilesAreIndependent() throws {
    var settings = PictureSettings()
    #expect(settings.local == StreamProfile())
    #expect(settings.remote.height == 720)
    settings[.remote].bitrateMbps = 10
    settings[.remote].height = 1080
    #expect(settings.local == StreamProfile())
    #expect(settings.profile(for: .remote).bitrateMbps == 10)
    #expect(settings.profile(for: .remote).upscaledOutput == .quadHD)
    #expect(settings.profile(for: .remote, ps5: false).height == 720)
    settings[.local].bitrateMbps = 101
    #expect(throws: PictureSettingsError.self) {
        try settings.validated()
    }
}

@Test func automaticBitrateFollowsTheResolution() throws {
    var profile = StreamProfile(height: 720, bitrateMbps: 40)
    #expect(profile.automaticBitrate)
    #expect(profile.effectiveBitrateMbps == 10)
    profile.height = 1080
    #expect(profile.effectiveBitrateMbps == 15)
    profile.automaticBitrate = false
    #expect(profile.effectiveBitrateMbps == 40)
    let saved = Data(#"{"height":1080,"fps":60,"bitrateMbps":25,"automaticBitrate":false}"#.utf8)
    #expect(try JSONDecoder().decode(StreamProfile.self, from: saved).effectiveBitrateMbps == 25)
}

@Test func cloudBitrateIsAutomaticUnlessOverridden() throws {
    var settings = CloudPictureSettings()
    #expect(settings.psCloudHeight == 2160)
    #expect(try settings.validated() == settings)
    #expect(settings.bitrateMbps(for: "pscloud") == 50)
    settings.psCloudHeight = 1440
    settings = settings.normalized()
    #expect(settings.bitrateMbps(for: "pscloud") == 35)
    settings.psCloudAutomaticBitrate = false
    settings.psCloudBitrateMbps = 80
    #expect(settings.bitrateMbps(for: "pscloud") == 80)
    #expect(try settings.validated() == settings)
    #expect(settings.bitrateMbps(for: "psnow") == 15)
    let legacy = Data(#"{"psCloudHeight":1080,"psCloudBitrateMbps":150}"#.utf8)
    let decoded = try JSONDecoder().decode(CloudPictureSettings.self, from: legacy)
    #expect(decoded.psCloudBitrateMbps == 100)
    #expect(decoded.psCloudAutomaticBitrate)
    #expect(decoded.hdr)
}

@Test func cloudHDRNeedsAnHDRDisplayAndMoreThan1080p() {
    var settings = CloudPictureSettings()
    #expect(settings.requestsHDR(for: "pscloud", displaySupportsHDR: true))
    #expect(!settings.requestsHDR(for: "pscloud", displaySupportsHDR: false))
    #expect(!settings.requestsHDR(for: "psnow", displaySupportsHDR: true))
    settings.psCloudHeight = 1080
    #expect(!settings.requestsHDR(for: "pscloud", displaySupportsHDR: true))
    settings.psCloudHeight = 1440
    settings.hdr = false
    #expect(!settings.requestsHDR(for: "pscloud", displaySupportsHDR: true))
}

@Test func consoleHEVCRequestsHDROnlyOnAnHDRScreenWithTheSettingOn() {
    var settings = PictureSettings()
    #expect(settings.launchCodec(forPS5: true, route: .local, displaySupportsHDR: true) == .hevcHDR)
    #expect(settings.launchCodec(forPS5: true, route: .local, displaySupportsHDR: false) == .hevc)
    #expect(settings.launchCodec(forPS5: false, route: .local, displaySupportsHDR: true) == .h264)
    settings.localPS5HDR = false
    #expect(settings.launchCodec(forPS5: true, route: .local, displaySupportsHDR: true) == .hevc)
    #expect(settings.launchCodec(forPS5: true, route: .remote, displaySupportsHDR: true) == .hevcHDR)
    settings.localPS5HDR = true
    settings.localPS5Codec = .h264
    #expect(settings.launchCodec(forPS5: true, route: .local, displaySupportsHDR: true) == .h264)
}

@Test func onlyAutomaticPS5CloudBitrateMeasuresTheConnection() {
    var settings = CloudPictureSettings()
    #expect(settings.measuresBandwidth(for: "pscloud"))
    #expect(!settings.measuresBandwidth(for: "psnow"))
    settings.psCloudAutomaticBitrate = false
    #expect(!settings.measuresBandwidth(for: "pscloud"))
}

@Test func theLatestSavedBandwidthIsDescribedWithItsAge() {
    let measuredAt = Date(timeIntervalSince1970: 10000)
    var settings = CloudDatacenterSettings()
    settings.setMeasurements([
        CloudDatacenterMeasurement(
            name: "older", rttMs: 30, measuredAt: measuredAt, bandwidthKbps: 32000,
            bandwidthMeasuredAt: measuredAt.addingTimeInterval(-600), bandwidthRttMs: 30
        ),
        CloudDatacenterMeasurement(
            name: "newer", rttMs: 21, measuredAt: measuredAt, bandwidthKbps: 55000,
            bandwidthMeasuredAt: measuredAt, bandwidthRttMs: 21
        ),
        CloudDatacenterMeasurement(name: "unmeasured", rttMs: 40, measuredAt: measuredAt)
    ], for: .psCloud)
    let latest = settings.latestBandwidth(for: .psCloud)
    #expect(latest == CloudSavedBandwidth(kbps: 55000, measuredAt: measuredAt))
    #expect(settings.latestBandwidth(for: .psNow) == nil)
    #expect(latest?.caption(now: measuredAt.addingTimeInterval(30))
        ==
        "Measured your connection at 55 Mbps moments ago. Measures again at launch when that is out of date.")
    #expect(latest?.caption(now: measuredAt.addingTimeInterval(720))
        ==
        "Measured your connection at 55 Mbps 12 min ago. Measures again at launch when that is out of date.")
    #expect(latest?.caption(now: measuredAt.addingTimeInterval(7200))
        == "Measured your connection at 55 Mbps 2 h ago. Measures again at launch when that is out of date.")
}

@Test func aChosenCaptureFoldersBookmarkIsKeptWithItsPath() throws {
    var settings = CloudPictureSettings()
    settings.captureFolder = "/tmp/captures"
    settings.captureFolderBookmark = Data([4, 5, 6])
    let decoded = try JSONDecoder().decode(CloudPictureSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.captureFolder == "/tmp/captures")
    #expect(decoded.captureFolderBookmark == Data([4, 5, 6]))
    let older = Data(#"{"captureFolder":"/tmp/captures"}"#.utf8)
    #expect(try JSONDecoder().decode(CloudPictureSettings.self, from: older).captureFolderBookmark == nil)
}
