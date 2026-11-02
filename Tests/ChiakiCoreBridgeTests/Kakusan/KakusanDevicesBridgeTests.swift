import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
@testable import ChiakiCoreBridge
import ChiakiModels
import Foundation
import Testing

@Test func coreRefusalsReadAsTheErrorsTheUserSees() {
    let table: [(libchiaking.kakusan.Refusal.Kind, KakusanError)] = [
        (.invalid_text, .invalidBlock),
        (.invalid_argument, .invalidBlock),
        (.expired, .expired),
        (.unsupported_version, .version),
        (.identity_changed, .identityChanged),
        (.tampered, .transcript),
        (.no_free_seat, .noCapacity),
        (.busy, .sourceJoinFailed),
        (.cannot_be_shared, .sourceFormat),
        (.not_visiting, .sourceEnded),
        (.internal, .internal)
    ]
    for (refused, error) in table {
        #expect(KakusanDevicesBridge.error(refused) == error)
    }
}

#if CHIAKI_KAKUSAN
    @Test func aClosedCoreRefusesDeviceWorkWithoutCrashing() throws {
        let bridge = KakusanDevicesBridge()
        let key = try #require(KakusanPublicKey(Data(repeating: 3, count: 32)))
        #expect(bridge.recognize(key, expecting: nil) == .unknown)
        #expect(!bridge.forget(key))
        #expect(throws: KakusanError.internal) {
            try bridge.rename(key, to: "Sam")
        }
        #expect(bridge.normalisedNickname("  Sam  ") == "Sam")
        #expect(bridge.normalisedNickname("   ") == nil)
    }
#endif

@Test func invitationPreviewsNeedAHintCapacityAndExpiry() {
    let hint = Data(repeating: 2, count: KakusanIdentityHint.length)
    #expect(KakusanDevicesBridge.preview(
        hostHint: hint, claimedHostName: "Sam", capacity: 4, expiresAt: 1_800_000_600
    ) == KakusanInvitationPreview(
        hostHint: KakusanIdentityHint(hint)!,
        claimedHostName: "Sam",
        capacity: 4,
        expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
    ))
    #expect(KakusanDevicesBridge.preview(
        hostHint: hint.prefix(7), claimedHostName: nil, capacity: 4, expiresAt: 1_800_000_600
    ) == nil)
    #expect(KakusanDevicesBridge.preview(
        hostHint: hint, claimedHostName: nil, capacity: 0, expiresAt: 1_800_000_600
    ) == nil)
    #expect(KakusanDevicesBridge.preview(
        hostHint: hint, claimedHostName: nil, capacity: 4, expiresAt: 0
    ) == nil)
}
