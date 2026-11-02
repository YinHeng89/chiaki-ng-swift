import ChiakiModels
import Foundation
import Testing

@Suite struct AccountEntryValidationTests {
    private func count(_ text: String) -> Int? {
        guard let npsso = NPSSO(text) else {
            return nil
        }
        return npsso.count
    }

    private func same(_ first: String, _ second: String) -> Bool {
        guard let lhs = NPSSO(first), let rhs = NPSSO(second) else {
            return false
        }
        return lhs.isEqual(to: rhs)
    }

    private func expirySource(_ expiresAt: Date?) -> NPSSOExpirySource? {
        guard let npsso = NPSSO("token") else {
            return nil
        }
        return SignInCapture(npsso: npsso, expiresAt: expiresAt, expirySource: .cookie).expirySource
    }

    @Test func anNPSSOIsTrimmedAndOnlyCookieSafeTextIsAccepted() {
        #expect(count("  abcDEF123-_.~  \n") == 13)
        #expect(same("  abcDEF123-_.~  \n", "abcDEF123-_.~"))
        #expect(!same("abc", "abd"))
        #expect(count("") == nil)
        #expect(count("   ") == nil)
        #expect(count("has space") == nil)
        #expect(count("semi;colon") == nil)
        #expect(count("quo\"te") == nil)
        #expect(count("comma,") == nil)
        #expect(count("back\\slash") == nil)
        #expect(NPSSO.accepts("token"))
        #expect(!NPSSO.accepts("tok en"))
    }

    @Test func aCaptureWithoutAnExpiryHasNoExpirySource() {
        #expect(expirySource(nil) == .unknown)
        #expect(expirySource(Date(timeIntervalSince1970: 1)) == .cookie)
    }

    @Test func aTypedAccountIDIsTrimmedBase64OfEightBytes() {
        #expect(AccountID(typed: "  AQAAAAAAAAA=\n") == AccountID(value: 1))
        #expect(AccountID(typed: "AQAAAAAAAA==") == nil)
        #expect(AccountID(typed: "invalid") == nil)
        #expect(AccountID(typed: "") == nil)
    }

    @Test func aConsoleAddressIsTrimmedAndHasNoInnerWhitespace() {
        #expect(ConsoleAddress(" 192.0.2.4 ")?.text == "192.0.2.4")
        #expect(ConsoleAddress("living-room.local")?.text == "living-room.local")
        #expect(ConsoleAddress("") == nil)
        #expect(ConsoleAddress("  ") == nil)
        #expect(ConsoleAddress("living room") == nil)
        #expect(ConsoleAddress(String(repeating: "a", count: 253)) != nil)
        #expect(ConsoleAddress(String(repeating: "a", count: 254)) == nil)
    }
}
