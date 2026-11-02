import Foundation
import Testing
import ChiakiModels
@testable import ChiakiDiagnostics

private let redactor = LogRedactor(salt: Data(repeating: 7, count: 16))

@Test func redactorPatternsAllCompile() {
    #expect(LogRedactor.patternsCompiled)
}

@Test func redactorReplacesNetworkIdentifiersConsistently() {
    let line = "Local play: \"Living room PS5\" MAC 0011223344ff at 192.168.20.111:9295, discovery; "
        + "public 203.0.113.9 link fe80::1c2b:3d4e:5f60:7a8b"
    let redacted = redactor.redact(line)
    #expect(!redacted.contains("Living room"))
    #expect(!redacted.contains("0011223344ff"))
    #expect(!redacted.contains("192.168.20.111"))
    #expect(!redacted.contains("203.0.113.9"))
    #expect(!redacted.contains("fe80::1c2b"))
    #expect(redacted.contains("\"[console#"))
    #expect(redacted.contains("[hex#"))
    #expect(redacted.contains("[lan-ip#"))
    #expect(redacted.contains("]:9295"))
    #expect(redacted.contains("[ip#"))
    #expect(redacted.contains("[ip6#"))
    #expect(redactor.redact("192.168.20.111") == redactor.redact("192.168.20.111"))
    #expect(redactor.redact("192.168.20.111") != redactor.redact("192.168.20.112"))
    #expect(LogRedactor(salt: Data(repeating: 9, count: 16)).redact("10.0.0.2") != redactor
        .redact("10.0.0.2"))
    #expect(redactor.redact(redacted) == redacted)
}

@Test func redactorKeepsTimestampsLoopbackAndShortValues() {
    let line = "1970-01-01T00:00:00.000Z [INFO] [Example.swift:42 connect()] bound 127.0.0.1:9295 and 0.0.0.0, "
        + "stage=2 elapsed=1200 ms, id abcdef12…, seq 00:00:01"
    #expect(redactor.redact(line) == line)
    let mac = "aa:bb:cc:dd:ee:ff"
    #expect(redactor.redact("pad \(mac)").hasPrefix("pad [mac#"))
}

@Test func redactorStripsSecretsTokensAndHomeFolders() {
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    let line = "Authorization: Bearer \(jwt) npsso=abcDEF123 \"refresh_token\": \"zzz\" {\"name\": \"ok\"} "
        + "folder /Users/player/Library/Logs/chiaki-ng account 1234567890123456789 "
        + "session 9b2c4d6e-1f3a-4b5c-8d7e-0f1a2b3c4d5e blob "
        + "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVowMTIzNDU2Nzg5YWJjZGVm"
    let redacted = redactor.redact(line)
    #expect(redacted.contains("Bearer [redacted]"))
    #expect(!redacted.contains("eyJ"))
    #expect(redactor.redact("got \(jwt) back") == "got [token] back")
    #expect(redacted.contains("npsso=[redacted]"))
    #expect(redacted.contains("\"refresh_token\": \"[redacted]\""))
    #expect(redacted.contains("{\"name\": \"ok\"}"))
    #expect(redacted.contains("folder /Users/[user]/Library/Logs/chiaki-ng"))
    #expect(redacted.contains("account [id#"))
    #expect(redacted.contains("session [uuid#"))
    #expect(redacted.contains("blob [blob#"))
    #expect(!redacted.contains("QUJDREVG"))
    #expect(redactor.redact("https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?code=abc&x=1")
        .contains("code=[redacted]&x=1"))
    let path = "/Applications/chiaki-ng.app/Contents/Frameworks/libchiaki-native-core-component.dylib"
    #expect(redactor.redact(path) == path)
}

@Test func redactorTagsAreTheFirstFourSaltedHashBytesInLowercaseHex() {
    #expect(redactor.tag("ip", "192.168.20.111") == "[ip#a5faf4ce]")
}
