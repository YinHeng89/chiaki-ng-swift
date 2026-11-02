import ChiakiModels
import Foundation
import Testing

@testable import ChiakiNG

@Test func theTokenResponseProvidesItsOwnExpiry() throws {
    let received = Date(timeIntervalSince1970: 1000)
    let credential = try NPSSOCredential.decodeTokenResponse(
        Data(#"{"npsso":"synthetic-secret","expires_in":5105401}"#.utf8), receivedAt: received
    )
    #expect(credential.expiresAt == received.addingTimeInterval(5105401))
    #expect(credential.expirySource == .tokenResponse)
    #expect(!String(reflecting: credential).contains("synthetic-secret"))
    let unknown = try NPSSOCredential.decodeTokenResponse(
        Data(#"{"npsso":"synthetic"}"#.utf8), receivedAt: received
    )
    #expect(unknown.expiresAt == nil)
    #expect(unknown.expirySource == .unknown)
    #expect(throws: SignInFailure.unreadableResponse) {
        try NPSSOCredential.decodeTokenResponse(
            Data(#"{"npsso":"synthetic","expires_in":0}"#.utf8), receivedAt: received
        )
    }
}

private func cookie(_ name: String, _ value: String, expires: Date?) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name, .value: value, .domain: "ca.account.sony.com", .path: "/"
    ]
    properties[.expires] = expires
    return HTTPCookie(properties: properties)!
}

@Test func aBrowserSignInWithoutAStatedLifetimeAdoptsItsCookiesExpiry() throws {
    let now = Date(timeIntervalSince1970: 1000), expiry = Date(timeIntervalSince1970: 5_000_000)
    let silent = try NPSSOCredential.decodeTokenResponse(
        Data(#"{"npsso":"synthetic-secret"}"#.utf8), receivedAt: now
    )
    let adopted = silent.adoptingCookieExpiry(
        from: [
            cookie("other", "synthetic-secret", expires: expiry),
            cookie("npsso", "synthetic-secret", expires: expiry)
        ],
        now: now
    )
    #expect(adopted.value == "synthetic-secret")
    #expect(adopted.expiresAt == expiry && adopted.expirySource == .cookie)
    #expect(silent.adoptingCookieExpiry(from: [], now: now) == silent)
    #expect(silent
        .adoptingCookieExpiry(from: [cookie("npsso", "synthetic-secret", expires: nil)], now: now) == silent)
    #expect(silent
        .adoptingCookieExpiry(from: [cookie("npsso", "another-secret", expires: expiry)], now: now) == silent)
    #expect(silent
        .adoptingCookieExpiry(from: [cookie("npsso", "synthetic-secret", expires: now)], now: now) == silent)
    let stated = try NPSSOCredential.decodeTokenResponse(
        Data(#"{"npsso":"synthetic-secret","expires_in":60}"#.utf8), receivedAt: now
    )
    #expect(
        stated
            .adoptingCookieExpiry(from: [cookie("npsso", "synthetic-secret", expires: expiry)], now: now) ==
            stated
    )
}
