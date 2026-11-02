@testable import ChiakiFeatures
import ChiakiModels
import Testing

@Test func pairingLogLinesNameTheTargetStageAndDecodedCode() throws {
    let uid = try #require(ConsoleDeviceUID(bytes: [UInt8](
        repeating: 0xAB,
        count: ConsoleDeviceUID.byteCount
    )))
    let remote = PairingTarget.overInternet(AccountConsoleTarget(deviceUID: uid, name: "PS5-054", kind: .ps5))
    #expect(
        PairingLog.ended(
            remote,
            .failure(.overInternet(.connecting, code: 403)),
            elapsed: .milliseconds(4100),
            for: "\"Player\""
        )
            == "PSN registration of a PS5 via PSN device abababab… failed after 4100 ms: during console "
            + "connection: HTTP 403 from the PSN service"
    )
    #expect(PairingLog.describe(code: 7) == "console or service reason 7")
    #expect(PairingLog.started(remote, for: "\"Player\"")
        .hasSuffix("for \"Player\" started, console \"PS5-054\""))

    let local = PairingTarget.atHome(address: "192.168.1.20", kind: .ps4)
    #expect(
        PairingLog.ended(local, .failure(.rejected), elapsed: .milliseconds(900), for: "\"Player\"")
            == "PIN registration of a PS4 at 192.168.1.20 failed after 900 ms: the console refused the "
            + "registration or its reply could not be read; a wrong or expired PIN is the usual cause"
    )
    #expect(
        PairingLog.ended(local, .failure(.unreachable), elapsed: .milliseconds(3), for: "\"Player\"")
            == "PIN registration of a PS4 at 192.168.1.20 failed after 3 ms: the console did not answer or its "
            + "address could not be reached"
    )
}
