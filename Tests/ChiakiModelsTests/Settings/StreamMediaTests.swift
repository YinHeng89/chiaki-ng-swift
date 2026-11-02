import ChiakiModels
import Foundation
import Testing

@Test func streamMediaSaysWhichHalvesOfTheStreamPlay() {
    #expect(StreamMedia.pictureAndSound.picture && StreamMedia.pictureAndSound.sound)
    #expect(!StreamMedia.soundOnly.picture && StreamMedia.soundOnly.sound)
    #expect(StreamMedia.pictureOnly.picture && !StreamMedia.pictureOnly.sound)
    #expect(!StreamMedia.controlsOnly.picture && !StreamMedia.controlsOnly.sound)
}

@Test func savedSoundSettingsWithoutStreamMediaPlayBoth() throws {
    let legacy = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"volume":0.5}"#.utf8))
    #expect(legacy.media == .pictureAndSound)
    var settings = SoundSettings()
    settings.media = .controlsOnly
    let decoded = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.media == .controlsOnly)
    let unknown = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"media":"hologram"}"#.utf8))
    #expect(unknown.media == .pictureAndSound)
}
