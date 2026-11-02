import ChiakiModels
import Foundation
import Testing

private let inviteRows: [[KakusanControl]] = [
    [.close], [.copy], [.expect(nil), .expect("Mika")], [.paste], [.cancel, .connect]
]

private func moved(_ from: KakusanControl, _ step: KakusanGridStep) -> KakusanControl? {
    var grid = KakusanControlGrid(inviteRows, preferred: from)
    grid.move(step)
    return grid.selection
}

@Test func theGridMovesBetweenRowsLikeTheLayout() {
    #expect(moved(.copy, .up) == .close)
    #expect(moved(.close, .down) == .copy)
    #expect(moved(.cancel, .up) == .paste)
    #expect(moved(.paste, .down) == .connect)
    #expect(moved(.close, .up) == .close)
    #expect(moved(.connect, .down) == .connect)
}

@Test func theGridMovesWithinARowAndStopsAtItsEdges() {
    #expect(moved(.cancel, .right) == .connect)
    #expect(moved(.connect, .right) == .connect)
    #expect(moved(.expect(nil), .right) == .expect("Mika"))
    #expect(moved(.expect(nil), .left) == .expect(nil))
    #expect(moved(.copy, .left) == .copy)
}

@Test func theGridStartsOnThePreferredControlOnlyWhenItIsShown() {
    #expect(KakusanControlGrid(inviteRows).selection == .close)
    #expect(KakusanControlGrid(inviteRows, preferred: .paste).selection == .paste)
    #expect(KakusanControlGrid(inviteRows, preferred: .leave).selection == .close)
    #expect(KakusanControlGrid().selection == nil)
}

@Test func newRowsKeepTheSelectionWhileItIsStillShown() {
    var grid = KakusanControlGrid([[.name], [.cancel, .save]], preferred: .save)
    grid.show([[.name], [.cancel, .replace, .save]], preferring: .replace)
    #expect(grid.selection == .save)
    grid.show([[.name], [.cancel]], preferring: .cancel)
    #expect(grid.selection == .cancel)
    grid.select(.save)
    #expect(grid.selection == .cancel)
}

@Test func theGuestCardNeverOffersAControlItDoesNotShow() {
    let summary = KakusanInvitationSummary(
        invitation: KakusanBlock(pasted: "RCP1:eyJib2R5Ijp7ImNhcGFjaXR5Ijo0fSwic2lnIjoiQUFBQSJ9")!,
        preview: KakusanInvitationPreview(
            hostHint: KakusanIdentityHint(Data(repeating: 1, count: KakusanIdentityHint.length))!,
            claimedHostName: nil,
            capacity: 4,
            expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
        )
    )
    let phases: [KakusanGuestPhase] = [
        .idle, .entering(nil), .entering(.invalidBlock), .previewing(UUID()), .previewed(summary),
        .disclosureAccepted(summary), .preparingReply(UUID(), summary), .connecting(UUID()),
        .admitting(UUID()), .readying(UUID(), seat: 2), .leaving(UUID()), .ended(.failed(.noPath))
    ]
    for phase in phases {
        for canRemember in [false, true] {
            let grid = KakusanGuestControls.grid(for: phase, canRemember: canRemember)
            #expect(Set(grid.controls).count == grid.controls.count, "\(phase)")
            if let selection = grid.selection {
                #expect(grid.shows(selection), "\(phase)")
            }
            #expect(grid.shows(.remember) == (canRemember && offersRemembering(phase)), "\(phase)")
        }
    }
}

@Test func backToTheLibraryIsNeverACardControl() {
    let phases: [KakusanGuestPhase] = [
        .entering(nil), .entering(.expired), .ended(.failed(.noPath)), .ended(.closed(.user, byPeer: true))
    ]
    for phase in phases {
        for canRemember in [false, true] {
            var grid = KakusanGuestControls.grid(for: phase, canRemember: canRemember)
            #expect(!grid.shows(.back), "\(phase)")
            for step in [KakusanGridStep.down, .down, .down, .left, .right, .up, .up, .up] {
                grid.move(step)
                #expect(grid.selection != .back, "\(phase) after \(step)")
            }
        }
    }
    #expect(KakusanGuestControls.grid(for: .entering(nil), canRemember: false).rows == [
        [.text],
        [.paste, .connect]
    ])
    #expect(KakusanGuestControls.grid(for: .ended(.failed(.noPath)), canRemember: false)
        .rows == [[.create]])
    #expect(KakusanGuestControls.grid(for: .ended(.failed(.noPath)), canRemember: true).rows == [
        [.remember], [.create]
    ])
}

@Test func theInviteCardShowsCloseOnlyWithAHeaderThatHasOne() {
    #expect(!KakusanInviteControls.grid(
        for: .verifying(.granted, KakusanVerification()),
        expectations: []
    )
    .shows(.close))
    #expect(!KakusanInviteControls.shows(.admitting(.awaitingSeat)))
}

private func offersRemembering(_ phase: KakusanGuestPhase) -> Bool {
    switch phase {
    case .admitting, .readying, .ended:
        true
    default:
        false
    }
}
