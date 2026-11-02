import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
import Testing

@Test func modelConstantsMatchTheBridge() {
    #expect(InternetConnectionSettings.portGuessRange == PlayBridge.portGuessRange)
    #expect(InternetConnectionSettings.defaultPortGuessCount == PlayBridge.defaultPortGuesses)
    #expect(SoundSettings.bufferRange == PlayBridge.audioBufferRange)
    #expect(SoundSettings.defaultBufferMilliseconds == PlayBridge.defaultAudioBufferMilliseconds)
}

@Test func onlyPS5ConsolesAndPS5CloudCarry3DAudio() {
    #expect(SoundTarget.allCases.filter(PlayBridge.supportsAudio3D) == [.ps5, .psCloud])
}

@Test func everyTakionTargetHasABuiltVersionAnswer() {
    for target in TakionTarget.allCases {
        _ = PlayBridge.builtProtocolVersion(target)
    }
}
