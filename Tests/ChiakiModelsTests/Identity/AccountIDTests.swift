import ChiakiModels
import Foundation
import Testing

@Suite struct AccountIDTests {
    @Test func wireFormIsLittleEndian() throws {
        let account = try #require(AccountID(bytes: [1, 2, 3, 4, 5, 6, 7, 8]))
        #expect(account.value == 0x0807_0605_0403_0201)
        #expect(account.bytes == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(account.data == Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    @Test func rejectsAnythingButEightBytes() {
        #expect(AccountID(bytes: [UInt8]()) == nil)
        #expect(AccountID(bytes: [1, 2, 3, 4, 5, 6, 7]) == nil)
        #expect(AccountID(bytes: [1, 2, 3, 4, 5, 6, 7, 8, 9]) == nil)
        #expect(AccountID(bytes: Data(count: 4)) == nil)
    }

    @Test func base64MatchesTheCoreAndRoundTrips() throws {
        let account = try #require(AccountID(base64: "AQIDBAUGBwg="))
        #expect(account.bytes == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(account.base64 == "AQIDBAUGBwg=")
        #expect(AccountID(base64: account.base64) == account)
        #expect(account.base64 == account.data.base64EncodedString())
    }

    @Test func rejectsBase64ThatIsNotEightBytes() {
        #expect(AccountID(base64: "") == nil)
        #expect(AccountID(base64: "not-an-account") == nil)
        #expect(AccountID(base64: "AQIDBAUGBw==") == nil)
        #expect(AccountID(base64: "AQIDBAUGBwgJ") == nil)
        #expect(AccountID(base64: " AQIDBAUGBwg=") == nil)
    }

    @Test func decimalRoundTrips() throws {
        let account = try #require(AccountID(decimal: "578437695752307201"))
        #expect(account.bytes == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(account.decimal == "578437695752307201")
        #expect(AccountID(decimal: "18446744073709551615")?.value == .max)
        #expect(AccountID(decimal: "007")?.value == 7)
    }

    @Test func rejectsDecimalThatIsNotPlainDigits() {
        #expect(AccountID(decimal: "") == nil)
        #expect(AccountID(decimal: "+7") == nil)
        #expect(AccountID(decimal: "-7") == nil)
        #expect(AccountID(decimal: " 7") == nil)
        #expect(AccountID(decimal: "7a") == nil)
        #expect(AccountID(decimal: "18446744073709551616") == nil)
        #expect(AccountID(decimal: "000000000000000000001") == nil)
    }

    @Test func everyFormDescribesTheSameAccount() throws {
        let account = AccountID(value: 0x0102_0304_0506_0708)
        #expect(AccountID(bytes: account.bytes) == account)
        #expect(AccountID(base64: account.base64) == account)
        #expect(AccountID(decimal: account.decimal) == account)
    }
}
