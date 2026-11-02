import Testing
@testable import ChiakiNG

@MainActor
@Test func signInRandomValuesAreLowercaseHexTwiceTheByteCount() throws {
    let text = try AccountSignInBrowser.randomHex(32)
    #expect(text.count == 64)
    #expect(text.allSatisfy { "0123456789abcdef".contains($0) })
    #expect(try AccountSignInBrowser.randomHex(0).isEmpty)
}
