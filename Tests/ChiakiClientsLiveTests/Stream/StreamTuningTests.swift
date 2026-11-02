@testable import ChiakiClientsLive
import ChiakiClients
import ChiakiModels
import Testing

@Test func streamMenuTuningWritesSpatialAudioIntoSavedSound() {
    let saved = SoundSettings(volume: 0.5, outputDevice: "Studio Display")
    #expect(StreamTuning.sound(
        saved,
        tunedBy: StreamTuningConfiguration(volume: 0.5, spatialAudio: SpatialAudio())
    ) == nil)
    var tuned = StreamTuningConfiguration(volume: 0.5, spatialAudio: saved.spatialAudio)
    tuned.spatialAudio.audio3D = false
    let without3D = StreamTuning.sound(saved, tunedBy: tuned)
    #expect(without3D == SoundSettings(volume: 0.5, outputDevice: "Studio Display", audio3D: false))
    tuned.spatialAudio.appleSpatial = false
    tuned.volume = 0.8
    let plain = StreamTuning.sound(saved, tunedBy: tuned)
    #expect(plain == SoundSettings(
        volume: 0.8, outputDevice: "Studio Display", audio3D: false, appleSpatial: false
    ))
}

@Test func streamMenuTuningWritesPartyChatVolumeOnlyWhenTheStreamHasOne() {
    let saved = SoundSettings(volume: 0.5, chatVolume: 0.6)
    #expect(StreamTuning.sound(
        saved,
        tunedBy: StreamTuningConfiguration(volume: 0.5, chatVolume: nil, spatialAudio: saved.spatialAudio)
    ) == nil)
    let quieter = StreamTuning.sound(
        saved,
        tunedBy: StreamTuningConfiguration(volume: 0.5, chatVolume: 0.2, spatialAudio: saved.spatialAudio)
    )
    #expect(quieter == SoundSettings(volume: 0.5, chatVolume: 0.2))
}
