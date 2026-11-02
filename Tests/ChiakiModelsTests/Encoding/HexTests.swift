import ChiakiModels
import Testing

@Suite struct HexTests {
    @Test func encodesTwoDigitsPerByteInTheRequestedCase() {
        #expect(Hex.encode([0x00, 0x0F, 0xA0, 0xFF]) == "000fa0ff")
        #expect(Hex.encode([0x00, 0x0F, 0xA0, 0xFF], letterCase: .upper) == "000FA0FF")
        #expect(Hex.encode([UInt8]()).isEmpty)
    }

    @Test func decodesEitherCase() {
        #expect(Hex.decode("000fa0ff") == [0x00, 0x0F, 0xA0, 0xFF])
        #expect(Hex.decode("000FA0FF") == [0x00, 0x0F, 0xA0, 0xFF])
        #expect(Hex.decode("") == [])
    }

    @Test func rejectsOddLengthsAndForeignCharacters() {
        #expect(Hex.decode("abc") == nil)
        #expect(Hex.decode("0x0f") == nil)
        #expect(Hex.decode("0f 0f") == nil)
        #expect(Hex.decode("zz") == nil)
        #expect(Hex.decode("\u{FF10}\u{FF11}") == nil)
    }

    @Test func roundTripsEveryByte() {
        let bytes = (0 ... 255).map(UInt8.init)
        #expect(Hex.decode(Hex.encode(bytes)) == bytes)
        #expect(Hex.decode(Hex.encode(bytes, letterCase: .upper)) == bytes)
    }

    @Test func recognisesOnlyAsciiHexDigits() {
        #expect("0123456789abcdefABCDEF".utf8.allSatisfy(Hex.isDigit))
        #expect(!"gG:- x".utf8.contains(where: Hex.isDigit))
    }
}
