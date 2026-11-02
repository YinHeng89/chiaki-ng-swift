import ChiakiModels
import Testing

@Suite struct PairingPINTests {
    @Test func acceptsExactlyEightASCIIDigits() {
        let accepted = PairingPIN("12345678") != nil
        #expect(accepted)
        #expect(PairingPIN.accepts("00000000"))
        for text in ["", "1234567", "123456789", "1234567a", "１２３４５６７８", " 12345678"] {
            let refused = PairingPIN(text) == nil
            #expect(refused)
            #expect(!PairingPIN.accepts(text))
        }
    }

    @Test func lendsTheDigitsAsACString() {
        guard let pin = PairingPIN("87654321") else {
            Issue.record("A valid PIN was refused")
            return
        }
        let text = pin.withUnsafeCString {
            String(cString: $0)
        }
        #expect(text == "87654321")
    }
}
