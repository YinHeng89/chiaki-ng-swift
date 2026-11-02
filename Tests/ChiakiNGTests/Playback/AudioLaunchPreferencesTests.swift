import ChiakiModels
import Foundation
import Testing
import Video
@testable import ChiakiNG

@Suite(.serialized) @MainActor struct AudioLaunchPreferencesTests {
    @Test func launchAlwaysRequestsStereoAndAppliesOneRendering() throws {
        let player = try NativeStreamPlayer(inputs: TestComposition.scratch.input)
        player.apply(SoundSettings(), audio3DAvailable: true)
        #expect(player.native.requestedAudioChannels == 2)
        #expect(player.native.audio3DEnabled != player.native.audioSpatialEnabled)
        player.apply(SoundSettings(audio3D: false, appleSpatial: false), audio3DAvailable: true)
        #expect(!player.native.audio3DEnabled)
        #expect(!player.native.audioSpatialEnabled)
        #expect(!player.native.controllerSpeakerEnabled)
        player.apply(SoundSettings(controllerSpeaker: true), audio3DAvailable: true)
        #expect(!player.native.controllerSpeakerEnabled)
        player.apply(
            SoundSettings(controllerSpeaker: true),
            audio3DAvailable: true,
            controllerSpeakerAvailable: true
        )
        #expect(player.native.controllerSpeakerEnabled)
        #expect(!player.native.controllerSpeakerWired)
    }

    @Test func streamEditsApplyVolumeAndRenderingLiveAndKeepStereo() throws {
        let player = try NativeStreamPlayer(inputs: TestComposition.scratch.input)
        player.apply(SoundSettings(volume: 0.5), audio3DAvailable: true)
        player.apply(StreamTuningConfiguration(
            volume: 0.8,
            spatialAudio: SpatialAudio(audio3D: false, appleSpatial: false)
        ))
        #expect(player.native.audioVolume == 0.8)
        #expect(!player.native.audio3DEnabled)
        #expect(!player.native.audioSpatialEnabled)
        player.apply(StreamTuningConfiguration(
            volume: 0.8,
            spatialAudio: SpatialAudio(audio3D: false)
        ))
        #expect(player.native.audioSpatialEnabled)
        #expect(player.native.requestedAudioChannels == 2)
    }
}
