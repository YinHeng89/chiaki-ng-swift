import Testing
@testable import ChiakiDiagnostics

@Test func streamFailureDiagnosticsDecodeStageQuitPortAndText() throws {
    let local = try #require(StreamFailureDiagnostics(
        "route=1 stage=3 domain=0 cause=25 subcause=0 result=27 HTTP=0 reason=0x00000000 received=0 cancelled=0 quit=3"
    ))
    #expect(local.stageName == "session init")
    #expect(local.quitName == "the console refused the session request")
    #expect(local.localPort == 9295)
    let cloud = try #require(StreamFailureDiagnostics(
        "route=3 stage=32 domain=9 cause=9 result=1 error_message=\"GAME_NOT_FREE:4.99\""
    ))
    #expect(cloud.localPort == nil)
    #expect(cloud.text("error_message") == "GAME_NOT_FREE:4.99")
    #expect(StreamFailureDiagnostics(nil) == nil)
}

@Test func streamFailureDiagnosticsReadALowercaseHexPrefixWithASign() {
    #expect(StreamFailureDiagnostics("stage=0x20")?.stage == 32)
    #expect(StreamFailureDiagnostics("stage=0x-20")?.stage == -32)
    #expect(StreamFailureDiagnostics("stage=0xAb")?.stage == 171)
    #expect(StreamFailureDiagnostics("stage=0X20")?.stage == nil)
    #expect(StreamFailureDiagnostics("stage=-7")?.stage == -7)
}
