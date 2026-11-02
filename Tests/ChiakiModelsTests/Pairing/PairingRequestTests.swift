import ChiakiModels
import Testing

@Suite struct PairingRequestTests {
    let account = AccountID(value: 0x0102_0304_0506_0708)

    @Test func aHomeRequestNeedsAPINAndAPlainAddress() throws {
        let request = try PairingRequest(
            account: account,
            target: .atHome(address: "192.0.2.4", kind: .ps5),
            pin: PairingPIN("12345678")
        )
        #expect(request.account == account)
        #expect(request.target.kind == .ps5)
        #expect(throws: PairingFailure.invalidInput) {
            _ = try PairingRequest(
                account: account,
                target: .atHome(address: "192.0.2.4", kind: .ps5),
                pin: nil
            )
        }
        for address in ["", "http://console/", "living room", String(repeating: "a", count: 254)] {
            #expect(throws: PairingFailure.invalidInput) {
                _ = try PairingRequest(
                    account: account,
                    target: .atHome(address: address, kind: .ps4),
                    pin: PairingPIN("12345678")
                )
            }
        }
        _ = try PairingRequest(
            account: account,
            target: .atHome(address: "[2001:db8::1]", kind: .ps5),
            pin: PairingPIN("12345678")
        )
    }

    @Test func anInternetRequestTakesNoPIN() throws {
        let device = try #require(ConsoleDeviceUID(bytes: [UInt8](repeating: 1, count: 32)))
        let target = PairingTarget.overInternet(AccountConsoleTarget(
            deviceUID: device,
            name: "PS5",
            kind: .ps5
        ))
        _ = try PairingRequest(account: account, target: target, pin: nil)
        #expect(throws: PairingFailure.invalidInput) {
            _ = try PairingRequest(account: account, target: target, pin: PairingPIN("12345678"))
        }
    }
}
