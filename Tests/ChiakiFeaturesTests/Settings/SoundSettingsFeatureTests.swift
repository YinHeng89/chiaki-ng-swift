import ChiakiClients
@testable import ChiakiFeatures
import ChiakiModels
import ComposableArchitecture
import Foundation
import Testing

@MainActor @Test func soundSettingsLoadListsConnectedDevicesAndKeepsAMissingChoice() async {
    let saved = SoundSettings(
        volume: 0.4,
        outputDevice: "Studio Display",
        startWithMicrophone: true,
        inputDevice: "USB Headset"
    )
    let devices = SoundDevices(outputs: ["MacBook Pro Speakers"], inputs: ["MacBook Pro Microphone"])
    let store = TestStore(initialState: SoundSettingsFeature.State()) {
        SoundSettingsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = .inMemory([saved])
        $0.settings.soundDevices = {
            devices
        }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.appeared)
    await store.receive(\.listed) {
        $0.devices = devices
        $0.listing = nil
    }
    await store.receive(\.sound.delegate.loaded)
    #expect(store.state.sound.saved == saved)
    #expect(store.state.outputChoices == ["MacBook Pro Speakers", "Studio Display"])
    #expect(store.state.inputChoices == ["MacBook Pro Microphone", "USB Headset"])
}

@MainActor @Test func aStaleDeviceListingIsIgnored() async {
    var initial = SoundSettingsFeature.State()
    initial.listing = OperationID()
    let store = TestStore(initialState: initial) {
        SoundSettingsFeature()
    }
    await store.send(.listed(OperationID(), SoundDevices(outputs: ["Old"])))
}

@MainActor @Test func soundSettingsClampAnEditBeforeSavingIt() async throws {
    let settings = SettingsClient.inMemory()
    var initial = SoundSettingsFeature.State()
    initial.sound.setting = .ready(saved: SoundSettings())
    let store = TestStore(initialState: initial) {
        SoundSettingsFeature()
    } withDependencies: {
        $0.uuid = .incrementing
        $0.settings = settings
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.sound(.edit(SoundSettings(volume: -0.3, audio3D: false))))
    await store.receive(\.sound.delegate.committed)
    let stored = try await settings.load(SoundSettings.self)
    #expect(stored.volume == 0)
    #expect(stored.spatialAudio == SpatialAudio(audio3D: false, appleSpatial: true))
    #expect(store.state.sound.setting == .ready(saved: stored))
}

@Test func soundSettingsDecodeMissingFieldsAsDefaults() throws {
    let decoded = try JSONDecoder().decode(SoundSettings.self, from: Data("{}".utf8))
    #expect(decoded == SoundSettings())
    #expect(decoded.startWithMicrophone == false)
    #expect(decoded.inputDevice == nil)
    #expect(decoded.spatialAudio == SpatialAudio(audio3D: true, appleSpatial: true))
    let microphone = SoundSettings(startWithMicrophone: true, inputDevice: "USB Headset")
    let roundTrip = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(microphone))
    #expect(roundTrip == microphone)
    #expect(SoundSettings(inputDevice: "").normalized().inputDevice == nil)
    #expect(throws: SoundSettingsError.self) {
        try SoundSettings(inputDevice: String(repeating: "m", count: 300)).validated()
    }
    #expect(throws: SoundSettingsError.self) {
        try SoundSettings(volume: 2).validated()
    }
}

@Test func soundSettingsControllerSpeakerRoundTripsAndDecodesMissingAsOff() throws {
    let legacy = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"volume":0.5}"#.utf8))
    #expect(!legacy.controllerSpeaker)
    let changed = SoundSettings(controllerSpeaker: true)
    let roundTrip = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(changed))
    #expect(roundTrip.controllerSpeaker)
    #expect(changed.normalized().controllerSpeaker)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed)) as? [String: Any]
    #expect(encoded?["controllerSpeakerOnCloud"] as? Bool == true)
}

@Test func soundSettingsSpatialSoundRoundTripsAndDecodesMissingAsOn() throws {
    let legacy = try JSONDecoder().decode(
        SoundSettings.self,
        from: Data(#"{"volume":0.5,"startWithMicrophone":true,"audio3D":false,"surround":8}"#.utf8)
    )
    #expect(legacy.spatialAudio == SpatialAudio())
    let changed = SoundSettings(audio3D: false, appleSpatial: false)
    let roundTrip = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(changed))
    #expect(roundTrip.spatialAudio == SpatialAudio(audio3D: false, appleSpatial: false))
    #expect(changed.normalized().spatialAudio == changed.spatialAudio)
    #expect(try changed.validated().spatialAudio == changed.spatialAudio)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed)) as? [String: Any]
    #expect(encoded?["audio3DOnHeadphones"] as? Bool == false)
    #expect(encoded?["appleSpatial"] as? Bool == false)
    #expect(encoded?["surround"] == nil)
    #expect(encoded?["audio3D"] == nil)
}
