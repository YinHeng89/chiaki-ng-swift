@testable import ChiakiClients
@testable import ChiakiClientsLive
import ChiakiModels
import ChiakiTestSupport
import Foundation
import Testing

@MainActor private final class FakeGuestPlayer: KakusanGuestPlayer {
    var codes: [String] = []
    var result = KakusanCommandOutcome.accepted

    func rememberKakusan(_ identity: Data, _ nickname: String,
                         _ replacing: Bool) -> Result<KakusanRememberResult, KakusanError> {
        .failure(.sourceEnded)
    }

    func enterKakusanHostCode(_ code: String) -> KakusanCommandOutcome {
        codes.append(code)
        return result
    }
}

@MainActor @Test func guestCodesGoToTheRunningGuestOnly() {
    let desk = KakusanGuestDesk()
    let player = FakeGuestPlayer()
    let other = FakeGuestPlayer()
    #expect(desk.enterCode(KakusanFixture.code("1111")) == .rejected(.internal))
    desk.open(UUID(), player: player)
    #expect(desk.enterCode(KakusanFixture.code("2468")) == .accepted)
    player.result = .rejected(.sourceEnded)
    #expect(desk.enterCode(KakusanFixture.code("1357")) == .rejected(.sourceEnded))
    desk.close(other)
    player.result = .rejected(.pairingFailed)
    #expect(desk.enterCode(KakusanFixture.code("9999")) == .rejected(.pairingFailed))
    desk.close(player)
    #expect(desk.enterCode(KakusanFixture.code("0000")) == .rejected(.internal))
    #expect(player.codes == ["2468", "1357", "9999"])
    #expect(other.codes.isEmpty)
}

@MainActor @Test func rememberingNeedsARunningGuest() {
    let desk = KakusanGuestDesk()
    let identity = KakusanFixture.key(4).bytes
    #expect(desk.remember(identity, "Den", false) == nil)
    desk.open(UUID(), player: FakeGuestPlayer())
    #expect(desk.remember(identity, "Den", false) == .failure(.sourceEnded))
}
