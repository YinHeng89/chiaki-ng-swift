import ChiakiModels
import Foundation
import Testing

@Test func savedSoundSettingsWithoutAChatVolumeMixChatAtFullLevel() throws {
    let saved = Data(#"{"volume":0.5,"bufferMilliseconds":40}"#.utf8)
    let settings = try JSONDecoder().decode(SoundSettings.self, from: saved)
    #expect(settings.chatVolume == 1.0)
    #expect(settings.volume == 0.5)
}

@Test func theChatVolumeIsKeptInRange() throws {
    var settings = SoundSettings(chatVolume: 1.5)
    #expect(settings.normalized().chatVolume == 1.0)
    settings.chatVolume = -0.2
    #expect(settings.normalized().chatVolume == 0.0)
    #expect(throws: SoundSettingsError.self) {
        try settings.validated()
    }
    let roundTrip = try JSONDecoder().decode(
        SoundSettings.self,
        from: JSONEncoder().encode(SoundSettings(chatVolume: 0.35))
    )
    #expect(roundTrip.chatVolume == 0.35)
}
