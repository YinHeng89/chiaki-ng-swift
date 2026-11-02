import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiModels
import Testing

@Suite struct ConsolesClientTests {
    let account = AccountID(value: 42)

    @Test func aHomeTargetWithoutAValidPINIsRefusedBeforeTheCoreIsAsked() async {
        let target = PairingTarget.atHome(address: "192.0.2.9", kind: .ps5)
        for pin in [nil, "1234", "１２３４５６７８", "abcdefgh"] {
            let result = await ConsolesClient
                .pairThroughCore(account: account, target: target, pin: pin) { _ in
                    Issue.record("Nothing should be attempted")
                }
            #expect(result == .failure(.invalidInput))
        }
    }

    @Test func anInternetTargetWithAPINIsRefused() async throws {
        let uid = try #require(ConsoleDeviceUID(bytes: [UInt8](
            repeating: 7,
            count: ConsoleDeviceUID.byteCount
        )))
        let target = PairingTarget.overInternet(AccountConsoleTarget(deviceUID: uid, name: "Den", kind: .ps5))
        let result = await ConsolesClient
            .pairThroughCore(account: account, target: target, pin: "12345678") { _ in
                Issue.record("Nothing should be attempted")
            }
        #expect(result == .failure(.invalidInput))
    }

    @Test func anAddressNoHostCouldHaveIsRefused() async {
        let target = PairingTarget.atHome(address: "192.0.2.9; rm", kind: .ps4)
        let result = await ConsolesClient
            .pairThroughCore(account: account, target: target, pin: "12345678") { _ in
                Issue.record("Nothing should be attempted")
            }
        #expect(result == .failure(.invalidInput))
    }
}
