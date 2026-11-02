import enum ChiakiBridge.chiaki_bridge
@testable import ChiakiCoreBridge
import Foundation
import Testing

@Test func coreBytesCopyEveryByteInOrder() {
    var bytes = chiaki_bridge.Bytes()
    for byte: UInt8 in [0, 1, 127, 128, 255] {
        bytes.push_back(byte)
    }
    #expect(Data(bytes) == Data([0, 1, 127, 128, 255]))
}

@Test func emptyCoreBytesBecomeEmptyData() {
    #expect(Data(chiaki_bridge.Bytes()).isEmpty)
}

@Test func coreBytesOutliveTheVectorTheyCameFrom() {
    var data = Data()
    do {
        var bytes = chiaki_bridge.Bytes()
        bytes.push_back(42)
        data = Data(bytes)
    }
    #expect(data == Data([42]))
}
