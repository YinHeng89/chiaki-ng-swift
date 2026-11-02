import ChiakiModels
import Foundation
import Testing

@Suite struct HardwareIDTests {
    @Test func storedFormIsLowercaseAndDiscoveryFormIsUppercase() throws {
        let hardware = try #require(HardwareID(bytes: [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0x06]))
        #expect(hardware.hex == "a1b2c3d4e506")
        #expect(hardware.uppercaseHex == "A1B2C3D4E506")
        #expect(hardware.data == Data([0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0x06]))
    }

    @Test func rejectsAnythingButSixBytes() {
        #expect(HardwareID(bytes: [UInt8]()) == nil)
        #expect(HardwareID(bytes: [1, 2, 3, 4, 5]) == nil)
        #expect(HardwareID(bytes: [1, 2, 3, 4, 5, 6, 7]) == nil)
    }

    @Test func readsHexInEitherCaseAndSkipsSeparators() throws {
        let expected = try #require(HardwareID(bytes: [0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0x06]))
        #expect(HardwareID(hex: "a1b2c3d4e506") == expected)
        #expect(HardwareID(hex: "A1B2C3D4E506") == expected)
        #expect(HardwareID(hex: "A1:B2:C3:D4:E5:06") == expected)
        #expect(HardwareID(hex: " a1-b2-c3-d4-e5-06\n") == expected)
    }

    @Test func rejectsHexWithoutExactlyTwelveDigits() {
        #expect(HardwareID(hex: "") == nil)
        #expect(HardwareID(hex: "a1b2c3d4e5") == nil)
        #expect(HardwareID(hex: "a1b2c3d4e5060") == nil)
        #expect(HardwareID(hex: "a1b2c3d4e5060708") == nil)
        #expect(HardwareID(hex: "a1b2c3d4e5\u{FF10}\u{FF11}") == nil)
    }

    @Test func roundTripsThroughBothTextForms() throws {
        let hardware = try #require(HardwareID(bytes: [0, 0x10, 0x7F, 0x80, 0xFE, 0xFF]))
        #expect(HardwareID(hex: hardware.hex) == hardware)
        #expect(HardwareID(hex: hardware.uppercaseHex) == hardware)
    }
}
