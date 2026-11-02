import ChiakiModels
import Foundation
import Testing

@Suite struct SecretBytesTests {
    private enum Refusal: Error {
        case refused
    }

    @Test func takingFromAnArrayWipesTheArray() {
        var source: [UInt8] = [0x73, 0x65, 0x63, 0x72, 0x65, 0x74]
        let secret = SecretBytes(wiping: &source)
        let count = secret.count
        let bytes = secret.withUnsafeBytes {
            Array($0)
        }
        #expect(source == [0, 0, 0, 0, 0, 0])
        #expect(count == 6)
        #expect(bytes == [0x73, 0x65, 0x63, 0x72, 0x65, 0x74])
    }

    @Test func takingFromDataWipesTheData() {
        var source = Data("npsso-token".utf8)
        let secret = SecretBytes(wiping: &source)
        let bytes = secret.withUnsafeBytes {
            Data($0)
        }
        #expect(source == Data(count: 11))
        #expect(bytes == Data("npsso-token".utf8))
    }

    @Test func aCloneHoldsTheSameBytesInItsOwnBuffer() {
        var source: [UInt8] = [9, 8, 7]
        let secret = SecretBytes(wiping: &source)
        let clone = secret.clone()
        let separate = secret.withUnsafeBytes { mine in
            clone.withUnsafeBytes { theirs in
                mine.baseAddress != theirs.baseAddress
            }
        }
        let same = clone.isEqual(to: secret)
        #expect(same)
        #expect(separate)
    }

    @Test func initialiserWritesStraightIntoTheBuffer() {
        var offered: [UInt8] = []
        let secret = SecretBytes(count: 4) { buffer in
            offered = Array(buffer)
            buffer.copyBytes(from: [1, 2, 3, 4])
        }
        let bytes = secret.withUnsafeBytes {
            Array($0)
        }
        #expect(offered == [0, 0, 0, 0])
        #expect(bytes == [1, 2, 3, 4])
    }

    @Test func initialiserPropagatesItsTypedError() {
        #expect(throws: Refusal.refused) {
            _ = try SecretBytes(count: 4) { (_: UnsafeMutableRawBufferPointer) throws(Refusal) in
                throw Refusal.refused
            }
        }
    }

    @Test func cStringIsTerminatedWithoutACopy() {
        var source = Array("12345678".utf8)
        let pin = SecretBytes(wiping: &source)
        let text = pin.withUnsafeCString {
            String(cString: $0)
        }
        let length = pin.withUnsafeCString {
            strlen($0)
        }
        #expect(text == "12345678")
        #expect(length == 8)
    }

    @Test func emptySecretIsAnEmptyCString() {
        var source: [UInt8] = []
        let secret = SecretBytes(wiping: &source)
        let isEmpty = secret.isEmpty
        let byteCount = secret.withUnsafeBytes {
            $0.count
        }
        let length = secret.withUnsafeCString {
            strlen($0)
        }
        #expect(isEmpty)
        #expect(byteCount == 0)
        #expect(length == 0)
    }

    @Test func descriptionIsRedacted() {
        var source = Array("hunter2".utf8)
        let secret = SecretBytes(wiping: &source)
        let description = secret.description
        #expect(description == "SecretBytes(<redacted>)")
        #expect(!description.contains("hunter2"))
        #expect(!description.contains("7"))
    }

    @Test func comparesByContent() {
        var first = Array("same".utf8)
        var second = Array("same".utf8)
        var third = Array("sama".utf8)
        var fourth = Array("same!".utf8)
        let one = SecretBytes(wiping: &first)
        let two = SecretBytes(wiping: &second)
        let three = SecretBytes(wiping: &third)
        let four = SecretBytes(wiping: &fourth)
        let matchesTwin = one.isEqual(to: two)
        let matchesSameLength = one.isEqual(to: three)
        let matchesLonger = one.isEqual(to: four)
        #expect(matchesTwin)
        #expect(!matchesSameLength)
        #expect(!matchesLonger)
    }

    @Test func wipeZeroesTheWholeBuffer() {
        var bytes: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        bytes.withUnsafeMutableBytes {
            SecretBytes.wipe($0)
        }
        #expect(bytes == [0, 0, 0, 0])
        var empty: [UInt8] = []
        empty.withUnsafeMutableBytes {
            SecretBytes.wipe($0)
        }
        #expect(empty.isEmpty)
    }

    @Test func movesAcrossTasks() async {
        var source = Array("token".utf8)
        let secret = SecretBytes(wiping: &source)
        let length = await Self.count(of: secret)
        #expect(length == 5)
    }

    @concurrent private static func count(of secret: consuming sending SecretBytes) async -> Int {
        secret.count
    }
}
