import Testing
@testable import ChiakiNG

@Test func bluetoothAddressSerialsShareOneCanonicalForm() {
    #expect(SDLControllerBackend.canonicalSerial("D0:BC:C1:4F:E0:E3") == "d0-bc-c1-4f-e0-e3")
    #expect(SDLControllerBackend.canonicalSerial("d0-bc-c1-4f-e0-e3") == "d0-bc-c1-4f-e0-e3")
}

@Test func otherSerialsAreKeptAsReported() {
    #expect(SDLControllerBackend.canonicalSerial("") == "")
    #expect(SDLControllerBackend.canonicalSerial("XB1-0042") == "XB1-0042")
    #expect(SDLControllerBackend.canonicalSerial("0123456789abcdef") == "0123456789abcdef")
    #expect(SDLControllerBackend.canonicalSerial("D0BCC14FE0E3") == "D0BCC14FE0E3")
    #expect(SDLControllerBackend.canonicalSerial("D0:BC:C1:4F:E0") == "D0:BC:C1:4F:E0")
}

@Test func controllerIdentitiesHashToLowercaseSHA256Hex() {
    #expect(SDLControllerBackend.identityHash("1356:3302:d0-bc-c1-4f-e0-e3")
        == "769ccf3177cc139f876ba5101d8c65e1b09859f103d238401d804ed64c02925a")
}
