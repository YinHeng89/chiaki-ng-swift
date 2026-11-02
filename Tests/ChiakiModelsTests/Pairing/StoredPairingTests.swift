import ChiakiModels
import Testing

@Suite struct PairingCredentialsTests {
    func key(_ byte: UInt8, count: Int = PairingCredentials.keyLength) -> SecretBytes {
        var bytes = [UInt8](repeating: byte, count: count)
        return SecretBytes(wiping: &bytes)
    }

    struct Keys {
        let registration: UInt8
        let remotePlay: UInt8
        let type: UInt32

        init(_ registration: UInt8, _ remotePlay: UInt8, _ type: UInt32) {
            self.registration = registration
            self.remotePlay = remotePlay
            self.type = type
        }
    }

    func matches(_ first: Keys, _ second: Keys) -> Bool? {
        guard let lhs = PairingCredentials(
            registrationKey: key(first.registration), remotePlayKey: key(first.remotePlay),
            keyType: first.type
        ),
            let rhs = PairingCredentials(
                registrationKey: key(second.registration), remotePlayKey: key(second.remotePlay),
                keyType: second.type
            )
        else {
            return nil
        }
        return lhs.isEqual(to: rhs)
    }

    @Test func refusesKeysOfTheWrongLength() {
        let short = PairingCredentials(registrationKey: key(1, count: 15), remotePlayKey: key(2), keyType: 1)
        let long = PairingCredentials(registrationKey: key(1), remotePlayKey: key(2, count: 17), keyType: 1)
        let refused = short == nil && long == nil
        #expect(refused)
    }

    @Test func comparesEveryKeyAndTheKeyType() {
        #expect(matches(Keys(1, 2, 2), Keys(1, 2, 2)) == true)
        #expect(matches(Keys(1, 2, 2), Keys(1, 2, 1)) == false)
        #expect(matches(Keys(1, 2, 2), Keys(1, 3, 2)) == false)
        #expect(matches(Keys(1, 2, 2), Keys(4, 2, 2)) == false)
    }
}
