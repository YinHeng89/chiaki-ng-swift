import ChiakiModels
import Foundation
import Testing

@Test func audioBufferSnapsToTenMillisecondStepsWithinRange() throws {
    #expect(SoundSettings().bufferMilliseconds == 40)
    #expect(SoundSettings(bufferMilliseconds: 64).normalized().bufferMilliseconds == 60)
    #expect(SoundSettings(bufferMilliseconds: 2).normalized().bufferMilliseconds == 20)
    #expect(SoundSettings(bufferMilliseconds: 500).normalized().bufferMilliseconds == 100)
    #expect(throws: SoundSettingsError.self) {
        try SoundSettings(bufferMilliseconds: 10).validated()
    }
    let saved = Data(#"{"volume":0.5}"#.utf8)
    let decoded = try JSONDecoder().decode(SoundSettings.self, from: saved)
    #expect(decoded.volume == 0.5 && decoded.bufferMilliseconds == 40)
}

@Test func consolePowerSettingsDefaultToAskingAndKeepUnknownValuesSafe() throws {
    #expect(ConsolePowerSettings() == ConsolePowerSettings(
        leaveAction: .ask,
        restOnMacSleep: false,
        resumeAfterWake: true,
        reconnectAfterDrop: true
    ))
    let value = ConsolePowerSettings(leaveAction: .restMode, restOnMacSleep: true)
    let round = try JSONDecoder().decode(ConsolePowerSettings.self, from: JSONEncoder().encode(value))
    #expect(round == value)
    let unknown = Data(#"{"leaveAction":"hibernate","restOnMacSleep":true}"#.utf8)
    let decoded = try JSONDecoder().decode(ConsolePowerSettings.self, from: unknown)
    #expect(decoded.leaveAction == .ask && decoded.restOnMacSleep && decoded.resumeAfterWake)
    #expect(decoded.reconnectAfterDrop)
    let off = ConsolePowerSettings(reconnectAfterDrop: false)
    #expect(try JSONDecoder().decode(ConsolePowerSettings.self, from: JSONEncoder().encode(off)) == off)
}
