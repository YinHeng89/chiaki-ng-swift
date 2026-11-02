import ChiakiModels
import Testing

@Suite struct RevealedSecretTests {
    @Test func aRevealedSecretIsOverwrittenWhenWiped() {
        let secret = Array("Zk4fakeTokenNotReal".utf8).withUnsafeBytes { RevealedSecret(copying: $0) }
        #expect(secret.text == "Zk4fakeTokenNotReal")
        #expect(!secret.isWiped)
        secret.wipe()
        #expect(secret.isWiped)
        #expect(secret.text.isEmpty)
        let empty = RevealedSecret(copying: UnsafeRawBufferPointer(start: nil, count: 0))
        #expect(empty.text.isEmpty)
    }
}
