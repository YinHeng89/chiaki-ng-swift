import Foundation
import Testing
@testable import ChiakiDiagnostics

@Test func identifiersAreShortenedForCorrelation() {
    #expect(LogFormat.hexPrefix(Data([0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6])) == "a1b2c3d4…")
    #expect(LogFormat.hexPrefix(Data([0x01, 0x02])) == "0102")
    #expect(LogFormat.hexPrefix(Data()) == "none")
    #expect(LogFormat.hexPrefix(Data([0x01, 0x02]), bytes: 0) == "01…")
    #expect(LogFormat.hexPrefix(Data([0xAB]), bytes: 0) == "ab…")
    #expect(LogFormat.idPrefix(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!) == "6f9619ff…")
    #expect(LogFormat.textPrefix("abcdefghijkl") == "abcdef…")
    #expect(LogFormat.textPrefix("abc") == "abc")
    #expect(LogFormat.mac(Data([0x78, 0xc8, 0x81, 0xc4, 0x5e, 0xd3])) == "78c881c45ed3")
}

@Test func errorCodesAreDecoded() {
    #expect(LogFormat.errno(-EHOSTUNREACH) == "EHOSTUNREACH (No route to host)")
    #expect(LogFormat.errno(EACCES) == "EACCES (Permission denied)")
    #expect(LogFormat.errno(99).hasPrefix("errno 99 ("))
    #expect(LogFormat.urlError(-1004) == "URL error -1004 (cannot connect to host)")
    #expect(LogFormat.urlError(-42) == "URL error -42 (unrecognised)")
    #expect(LogFormat.urlError(nil) == "non-URL error")
}

@Test func durationsSizesAndExpiriesAreReadable() {
    #expect(LogFormat.milliseconds(.milliseconds(1234)) == 1234)
    #expect(LogFormat.milliseconds(.seconds(2)) == 2000)
    #expect(LogFormat.size(512) == "512 B")
    #expect(LogFormat.size(2048) == "2.0 KB")
    #expect(LogFormat.size(3_145_728) == "3.0 MB")
    #expect(
        LogFormat.expiry(seconds: 3600, now: Date(timeIntervalSince1970: 0))
            == "3600 s (until 1970-01-01T01:00:00Z)"
    )
}

@Test func consecutiveIdenticalLinesCollapseIntoACount() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: folder)
    }
    let sink = FileLogSink(settings: .init(directory: folder.path, level: .info))
    for _ in 0..<5 {
        await sink.record(.diagnostic(.discovery, .info, "same"))
    }
    await sink.record(.diagnostic(.discovery, .info, "different"))
    await sink.record(.diagnostic(.discovery, .info, "different"))
    await sink.record(.diagnostic(.discovery, .info, "last"))
    let lines = await sink.snapshot().entries.map(\.line)
    #expect(lines.count == 5)
    #expect(lines[0].hasSuffix("Discovery: same"))
    #expect(lines[1].hasSuffix("Previous line repeated 4 more times"))
    #expect(lines[2].hasSuffix("Discovery: different"))
    #expect(lines[3].hasSuffix("Previous line repeated 1 more time"))
    #expect(lines[4].hasSuffix("Discovery: last"))
}

@Test func errorsAreNamedWithoutTheirPayload() {
    struct Leaky: Error, CustomStringConvertible {
        var description: String {
            "request to https://example.test/token/synthetic-secret failed"
        }
    }
    enum Refusal: Error {
        case invalidCredentials
        case unexpectedStatus(Int)
    }
    #expect(LogFormat.error(Refusal.invalidCredentials) == "invalidCredentials")
    #expect(LogFormat.error(Refusal.unexpectedStatus(418)) == "unexpectedStatus(418)")
    #expect(!LogFormat.error(Leaky()).contains("synthetic-secret"))
    #expect(LogFormat.error(Leaky()).hasPrefix("Leaky (domain "))
}

@Test func coreDiagnosticLinesDropNoiseAndExplainOverflow() {
    #expect(
        CoreDiagnosticLine
            .format("core attempt=2 sequence=9 elapsed_us=10 dropped=0 local: Ctrl connection started.")
            == "core attempt=2 sequence=9 elapsed_us=10 local: Ctrl connection started."
    )
    let overflow = CoreDiagnosticLine.format(
        "core attempt=2 sequence=40 elapsed_us=99 dropped=17 diagnostics queue overflow or contention"
    )
    #expect(overflow
        .hasPrefix("core attempt=2 sequence=40 elapsed_us=99 the core dropped 17 diagnostic records"))
    #expect(overflow.contains("256-record queue was full"))
    #expect(CoreDiagnosticLine.format("bridge attempt=1 x") == "bridge attempt=1 x")
}
