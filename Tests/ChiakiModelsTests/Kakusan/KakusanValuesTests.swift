@testable import ChiakiModels
import Foundation
import Testing

@Test func kakusanCodesAcceptOnlyFourAsciiDigits() {
    #expect(KakusanCode("0042")?.digits == "0042")
    #expect(KakusanCode("042") == nil)
    #expect(KakusanCode("04210") == nil)
    #expect(KakusanCode("12a4") == nil)
    #expect(KakusanCode("١٢٣٤") == nil)
    #expect(KakusanCode.digitsOnly("12-3 4 5") == "1234")
}

@Test func kakusanSecretsNeverAppearInDescriptions() {
    let code = KakusanCode("4821")!
    let block = KakusanBlock(pasted: "RCP1:c2VjcmV0LWJsb2Nr")!
    for text in [
        String(describing: code), String(reflecting: code), "\(code)",
        String(describing: block), String(reflecting: block), "\(block)"
    ] {
        #expect(text == "[REDACTED]")
    }
    var dumped = ""
    dump(block, to: &dumped)
    dump(code, to: &dumped)
    #expect(!dumped.contains("c2VjcmV0"))
    #expect(!dumped.contains("4821"))
    #expect(!dumped.contains("AAAA"))
    #expect(Mirror(reflecting: block).children.isEmpty)
}

@Test func kakusanBlocksTolerateMessengerWrapping() {
    let wrapped = "\u{00A0}\n  RCP1:abc\n def-\t_ghi\r\n  \u{00A0}"
    #expect(KakusanBlock(pasted: wrapped)?.text == "RCP1:abcdef-_ghi")
    #expect(KakusanBlock(pasted: "RCP1:") == nil)
    #expect(KakusanBlock(pasted: "rcp1:abc") == nil)
    #expect(KakusanBlock(pasted: "Join me RCP1:abc") == nil)
    #expect(KakusanBlock(pasted: "RCP1:abc=") == nil)
    #expect(KakusanBlock(pasted: "RCP1:ab+c") == nil)
    #expect(KakusanBlock(pasted: "RCP1:" + String(repeating: "a", count: KakusanBlock.maximumLength)) ==
        nil)
    #expect(KakusanBlock(
        pasted: String(repeating: " ", count: KakusanBlock.maximumPastedLength) + "RCP1:a"
    ) ==
        nil)
}

@Test func kakusanFingerprintsFormatAsSpacedGroups() {
    let fingerprint = KakusanFingerprint(Data((0 ..< 32).map(UInt8.init)))!
    #expect(fingerprint.groups.count == 16)
    #expect(fingerprint.groups.first == "0001")
    #expect(fingerprint.lines == [
        "0001 0203 0405 0607", "0809 0A0B 0C0D 0E0F", "1011 1213 1415 1617", "1819 1A1B 1C1D 1E1F"
    ])
    #expect(fingerprint.short == "0001 0203 0405 0607")
    for delimiter in [".", "·", "•"] {
        #expect(!fingerprint.description.contains(delimiter))
    }
    #expect(KakusanFingerprint(Data(count: 31)) == nil)
    #expect(KakusanPublicKey(Data(count: 33)) == nil)
    #expect(KakusanGuestID(Data(count: 15)) == nil)
}

@Test func kakusanSettingsValidateStunServers() throws {
    #expect(KakusanSettings().stunServers.isEmpty)
    #expect(KakusanSettings.parse("a.example:3478, b.example:19302\n\n c.example:1") ==
        ["a.example:3478", "b.example:19302", "c.example:1"])
    let cleaned = try KakusanSettings(stunServers: ["STUN.Example.com:3478", "stun.example.com:3478"])
        .validated()
    #expect(cleaned.stunServers == ["stun.example.com:3478"])
    #expect(try KakusanSettings(stunServers: []).validated().stunServers.isEmpty)
    for invalid in [
        "stun.example.com",
        "stun.example.com:0",
        "stun.example.com:70000",
        ":3478",
        "bad host:3478",
        "-host:3478",
        "host_name:3478"
    ] {
        #expect(throws: KakusanSettingsError.invalidServer(invalid)) {
            try KakusanSettings(stunServers: [invalid]).validated()
        }
    }
    #expect(throws: KakusanSettingsError.tooManyServers) {
        try KakusanSettings(stunServers: (1 ... 9).map { "s\($0).example:3478" }).validated()
    }
}

@Test func onlyARecognisedDeviceHasAName() {
    let alex = KakusanPeer(
        publicKey: KakusanPublicKey(Data(repeating: 1, count: 32))!,
        fingerprint: KakusanFingerprint(Data(repeating: 1, count: 32))!,
        nickname: "Alex",
        firstVerifiedAt: Date(timeIntervalSince1970: 0),
        lastSeenAt: Date(timeIntervalSince1970: 0)
    )
    #expect(KakusanRecognition.recognised(alex).name == "Alex")
    #expect(KakusanRecognition.changedKey(alex).name == nil)
}

@Test func kakusanOutcomesCarryShortLabels() {
    for error in KakusanError.allCases {
        #expect(!error.label.isEmpty)
        #expect(!error.label.hasSuffix("."))
        #expect(!error.label.contains("·") && !error.label.contains("•"))
    }
    #expect(KakusanAttemptOutcome(KakusanStateChange(state: .closed, error: .noPath)) ==
        .failed(.noPath))
    #expect(KakusanAttemptOutcome(KakusanStateChange(state: .closed, reason: .timeout, byPeer: true))
        == .closed(.timeout, byPeer: true))
    #expect(KakusanAttemptOutcome(KakusanStateChange(state: .closed)) == .closed(.user, byPeer: false))
    #expect(KakusanAttemptOutcome.closed(.user, byPeer: true).label == "Left the game")
    #expect(KakusanAttemptOutcome.closed(.user, byPeer: false).label == "Removed")
    #expect(KakusanGuestOutcome.closed(.user, byPeer: true).label == "The host removed you")
    #expect(KakusanGuestOutcome.failed(.noCapacity).label == "No free seat")
    #expect(KakusanError.codec
        .hostingLabel == "Use H.264 or H.265 without HDR, at 1080p and 60 fps or lower")
    #expect(KakusanError.version.hostingLabel == "This console connection can’t be shared")
    #expect(KakusanError.noPath.hostingLabel == KakusanError.noPath.label)
    #expect(KakusanSeatSnapshot(capacity: 4, local: 2, remote: 1, reserved: 1).free == 0)
    #expect(KakusanSeatSnapshot(capacity: 4, local: 1, remote: 0, reserved: 0).free == 3)
}

@Test func kakusanBlocksTellAnInvitationFromAReply() {
    let invitation = "RCP1:URAREhMUFRYXGBkaGxwdHh9qwkIYDAS7n0nYr7qQyAA3JFjOL7v7LoFNHOr2O65v"
        + "b3Fkr60BQgOhB7_zzhC-AAEAwAACCsNQ1NyG-A"
    let reply = "RCP1:UlBRUlNUVVZXWFlaW1xdXl9eZjoT_IFeSJe7AZ767-HEL2Q8ZBJCXTsBXfz-OGyZ5ZbapAM-"
        + "nwyqKay64UG8yvAAAQDGM2QUw1Bjn3US"
    #expect(KakusanBlock(pasted: invitation)!.kind == .invitation)
    #expect(KakusanBlock(pasted: reply)!.kind == .reply)
    #expect(KakusanBlock(pasted: "RCP1:QVepgduy")!.kind == .unrecognised)
    #expect(KakusanBlock(pasted: "RCP1:c2VjcmV0LWJsb2Nr")!.kind == .unrecognised)
    #expect(KakusanBlock(pasted: "RCP1:U")!.kind == .unrecognised)
}

@Test func theListOlderVersionsSavedAsTheirDefaultIsNoOverride() throws {
    let former = Data(#"{"stunServers":["stun.l.google.com:19302","stun.cloudflare.com:3478"]}"#.utf8)
    #expect(try JSONDecoder().decode(KakusanSettings.self, from: former).stunServers.isEmpty)
    let chosen = Data(#"{"stunServers":["stun.cloudflare.com:3478"]}"#.utf8)
    #expect(try JSONDecoder().decode(KakusanSettings.self, from: chosen)
        .stunServers == ["stun.cloudflare.com:3478"])
}

@Test func kakusanIdentifiersDescribeTheirFirstFourBytesInLowercaseHex() {
    let bytes = (0 ..< 32).map { UInt8(0xA0 + $0) }
    #expect(KakusanPublicKey(Data(bytes))?.description == "a0a1a2a3")
    #expect(KakusanGuestID(Data(bytes.prefix(16)))?.description == "a0a1a2a3")
    #expect(KakusanIdentityHint(Data(bytes.prefix(8)))?.description == "a0a1a2a3")
    #expect(KakusanIdentityHint(Data([0x00, 0x0F, 0xF0, 0xFF, 1, 2, 3, 4]))?.description == "000ff0ff")
}
