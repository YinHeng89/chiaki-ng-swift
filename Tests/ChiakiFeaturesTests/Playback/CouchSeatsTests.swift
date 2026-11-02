@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing

private func pad(
    _ id: UInt32,
    name: String = "DualSense Wireless Controller",
    family: ControllerFamily = .playStation,
    triggers: Bool = true
) -> ControllerDevice {
    ControllerDevice(
        id: id, preferenceKey: "unit:\(id)", name: name, transport: "Bluetooth", individual: true,
        rumble: true, lights: true, motion: true, touchpad: true, adaptiveTriggers: triggers, family: family
    )
}

private func account(_ name: String, _ byte: UInt8) -> AccountProfile {
    AccountProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02X", byte))")!,
        name: name, method: .npsso, accountID: AccountID(value: 0x0101_0101_0101_0101 &* UInt64(byte))
    )
}

@Test func ps4ClaimJoinsImmediatelyAndWaitsForTheTelevisionPicker() {
    var seats = CouchSeats(console: .ps4, primaryDevice: 1)
    let guest = pad(2, name: "Wireless Controller", triggers: false)
    #expect(seats.claim(pad(1)) == CouchOutcome())
    let claimed = seats.claim(guest)
    #expect(claimed.commands == [
        .route(pad: 1, device: guest), .join(pad: 1, controllerType: 2, accountID: nil)
    ])
    #expect(seats[1] == .joining(CouchPlayer(device: guest)))
    #expect(seats.claim(guest) == CouchOutcome())
    #expect(seats.apply(.announced(pad: 1)) == CouchOutcome())
    #expect(seats[1] == .pickingOnConsole(CouchPlayer(device: guest)))
    let ready = seats.apply(.confirmed(pad: 1, color: 0xff0000))
    #expect(seats[1] == .ready(CouchPlayer(device: guest), color: 0xff0000))
    #expect(ready.notice == .joined(pad: 1, player: CouchPlayer(device: guest), color: 0xff0000))
}

@Test func ps4BackingOutOnTheTelevisionFreesTheSeatWithoutAnotherLeave() {
    var seats = CouchSeats(console: .ps4)
    _ = seats.claim(pad(2))
    _ = seats.apply(.announced(pad: 1))
    let dropped = seats.apply(.dropped(pad: 1))
    #expect(dropped.commands == [.route(pad: 1, device: nil)])
    #expect(dropped.notice == .released(pad: 1))
    #expect(seats[1] == .open)
}

@Test func ps5ClaimAsksForAnAccountBeforeContactingTheConsole() {
    let rin = account("Rin", 3)
    var seats = CouchSeats(console: .ps5)
    let guest = pad(2)
    #expect(seats.claim(guest) == CouchOutcome())
    #expect(seats[1] == .choosingAccount(.local(guest)))
    let chosen = seats.chooseAccount(rin, for: 1)
    #expect(chosen.commands == [.join(pad: 1, controllerType: 6, accountID: rin.accountID.data)])
    #expect(seats[1] == .joining(CouchPlayer(device: guest, account: rin)))
    let ready = seats.apply(.confirmed(pad: 1, color: 0x00ff00))
    #expect(ready.commands == [.route(pad: 1, device: guest)])
    #expect(seats[1] == .ready(CouchPlayer(device: guest, account: rin), color: 0x00ff00))
}

@Test func ps5AccountsAreExclusiveAndTheHostCannotBeChosen() {
    let host = account("Host", 1)
    let mika = account("Mika", 2)
    var seats = CouchSeats(console: .ps5, hostAccount: host.id)
    _ = seats.claim(pad(2))
    _ = seats.claim(pad(3))
    #expect(seats.availability(of: host, for: 1) == .host)
    #expect(seats.chooseAccount(host, for: 1) == CouchOutcome())
    _ = seats.chooseAccount(mika, for: 1)
    #expect(seats.availability(of: mika, for: 2) == .seated(1))
    #expect(seats.chooseAccount(mika, for: 2) == CouchOutcome())
    #expect(seats[2] == .choosingAccount(.local(pad(3))))
}

@Test func ps5PasscodePromptsKeepTheSeatUntilTheConsoleDecides() {
    let rin = account("Rin", 3)
    var seats = CouchSeats(console: .ps5)
    _ = seats.claim(pad(2))
    _ = seats.chooseAccount(rin, for: 1)
    let player = CouchPlayer(device: pad(2), account: rin)
    _ = seats.apply(.passcodeRequested(pad: 1, retry: false))
    #expect(seats[1] == .passcode(player, retry: false))
    _ = seats.apply(.passcodeRequested(pad: 1, retry: true))
    #expect(seats[1] == .passcode(player, retry: true))
    let failed = seats.apply(.joinFailed(pad: 1, failure: .passcodeAttempts))
    #expect(failed.notice == .joinFailed(pad: 1, failure: .passcodeAttempts))
    #expect(seats[1] == .open)
}

@Test func ps5UnrecognisedAccountIsSetAsideForTheSession() {
    let sora = account("Sora", 4)
    var seats = CouchSeats(console: .ps5)
    _ = seats.claim(pad(2))
    _ = seats.chooseAccount(sora, for: 1)
    let refused = seats.apply(.accountUnresolvable(pad: 1))
    #expect(refused.notice == .joinFailed(pad: 1, failure: .accountUnresolvable))
    #expect(seats[1] == .open)
    _ = seats.claim(pad(2))
    #expect(seats.availability(of: sora, for: 1) == .unrecognised)
    #expect(seats.chooseAccount(sora, for: 1) == CouchOutcome())
}

@Test func cancellingOnlyWithdrawsSeatsTheConsoleKnowsAbout() {
    var seats = CouchSeats(console: .ps5)
    _ = seats.claim(pad(2))
    #expect(seats.cancel(1) == CouchOutcome())
    #expect(seats[1] == .open)
    _ = seats.claim(pad(2))
    _ = seats.chooseAccount(account("Rin", 3), for: 1)
    #expect(seats.cancel(1).commands == [.remove(pad: 1), .route(pad: 1, device: nil)])
    #expect(seats.cancel(1) == CouchOutcome())
}

@Test func cloudSeatsAreReadyAtOnceAndUnpluggingLeaves() {
    var seats = CouchSeats(console: .cloud)
    let guest = pad(5, name: "Xbox Wireless Controller", family: .xbox, triggers: false)
    let claimed = seats.claim(guest)
    #expect(claimed.commands == [
        .route(pad: 1, device: guest), .join(pad: 1, controllerType: 0, accountID: nil)
    ])
    #expect(seats[1] == .ready(CouchPlayer(device: guest), color: nil))
    let unplugged = seats.apply(.controllerRemoved(5))
    #expect(unplugged.commands == [.remove(pad: 1), .route(pad: 1, device: nil)])
    #expect(unplugged.notice == .disconnected(pad: 1))
    #expect(seats[1] == .open)
}

@Test func seatsFillLowestFirstAndStopAtThree() {
    var seats = CouchSeats(console: .ps4)
    for id in UInt32(2) ... 5 {
        _ = seats.claim(pad(id))
    }
    #expect(seats.pad(for: 2) == 1)
    #expect(seats.pad(for: 4) == 3)
    #expect(seats.pad(for: 5) == nil)
    _ = seats.cancel(2)
    _ = seats.claim(pad(5))
    #expect(seats.pad(for: 5) == 2)
}

@Test func aReadySeatCanHandItsControllerOver() {
    var seats = CouchSeats(console: .cloud, primaryDevice: 1)
    _ = seats.claim(pad(2))
    _ = seats.claim(pad(3))
    #expect(seats.replaceController(1, with: pad(3)) == CouchOutcome())
    #expect(seats.replaceController(1, with: pad(1)) == CouchOutcome())
    #expect(seats.replaceController(1, with: pad(4)).commands == [.route(pad: 1, device: pad(4))])
    #expect(seats[1] == .ready(CouchPlayer(device: pad(4)), color: nil))
    #expect(seats.replaceController(1, with: .keyboard).commands == [.route(pad: 1, device: .keyboard)])
    #expect(seats.pad(for: ControllerDevice.keyboardID) == 1)
    #expect(CouchSeats.controllerType(for: .keyboard) == 0)
}

@Test func seatsDroppedByAReconnectAreSeatedAgainWithTheirAccounts() {
    var seats = CouchSeats(console: .ps5, primaryDevice: 1)
    let guest = pad(2)
    let player = account("Guest", 0x22)
    _ = seats.claim(guest)
    _ = seats.chooseAccount(player, for: 1)
    _ = seats.apply(.confirmed(pad: 1, color: 0x00ff00))
    let seated = seats.seatedLocally
    #expect(seated == [1: CouchPlayer(device: guest, account: player)])
    #expect(seats.reseat(seated) == CouchOutcome())
    _ = seats.apply(.dropped(pad: 1))
    #expect(seats[1] == .open)
    let again = seats.reseat(seated)
    #expect(again.commands == [
        .route(pad: 1, device: guest), .join(pad: 1, controllerType: 6, accountID: player.accountID.data)
    ])
    #expect(seats[1] == .joining(CouchPlayer(device: guest, account: player)))
    #expect(seats.reseat(seated) == CouchOutcome())
}
