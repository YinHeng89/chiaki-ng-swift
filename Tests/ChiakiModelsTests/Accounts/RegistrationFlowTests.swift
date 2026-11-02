import Foundation
import Testing
@testable import ChiakiModels

private let player = RegistrationFlow.Profile(
    id: UUID(),
    name: "Player",
    kind: .npsso,
    accountID: "AAAAAAAAAAE="
)

private let livingRoom = RegistrationFlow.ConsoleTarget(address: "living-room.local", kind: .ps5)

@Test func restoringAccountsKeepsTheSelectionOrSelectsTheFirst() {
    var data = RegistrationFlow()
    data.restoreProfiles([player])
    #expect(data.selectedProfileID == player.id)
    let second = RegistrationFlow.Profile(id: UUID(), name: "Second", kind: .accountID, accountID: nil)
    data.restoreProfiles([player, second])
    #expect(data.selectedProfileID == player.id)
    data.restoreProfiles([player, second], selected: second.id)
    #expect(data.selectedProfileID == second.id)
}

@Test func aPairingIsRecordedForTheSelectedAccountAndSelected() {
    var data = RegistrationFlow()
    let withoutAccount = data.recordPairing(livingRoom)
    #expect(!withoutAccount)
    data.restoreProfiles([player])
    let recorded = data.recordPairing(livingRoom)
    #expect(recorded)
    #expect(data.registrations == [RegistrationFlow.Registration(profileID: player.id, console: livingRoom)])
    #expect(data.selectedConsole == livingRoom)
    #expect(data.linkedConsoles == [livingRoom])
}

@Test func multipleProfilesCanShareConsoleWithoutLosingEmptyProfiles() {
    var data = RegistrationFlow()
    data.restoreProfiles([player])
    data.recordPairing(livingRoom)
    let second = RegistrationFlow.Profile(id: UUID(), name: "Second", kind: .npsso, accountID: "AAAAAAAAAAI=")
    data.restoreProfiles(data.profiles + [second], selected: second.id)
    #expect(data.linkedConsoles.isEmpty)
    data.recordPairing(livingRoom)
    #expect(data.profiles.count == 2)
    #expect(data.registrations.count == 2)
    let selected = data.selectProfile(player.id)
    #expect(selected)
    #expect(data.linkedConsoles.count == 1)
    let unknown = data.selectProfile(UUID())
    #expect(!unknown)
}

@Test func onlyAPairedConsoleOfTheSelectedAccountCanBeSelectedOrStreamed() {
    var data = RegistrationFlow()
    data.restoreProfiles([player])
    let unpairedSelection = data.selectConsole(livingRoom)
    let unpairedStream = data.selectStream(profile: player.id, console: livingRoom)
    #expect(!unpairedSelection && !unpairedStream)
    data.recordPairing(livingRoom)
    data.selectProfile(player.id)
    #expect(data.selectedConsole == nil)
    let selection = data.selectConsole(livingRoom)
    let stream = data.selectStream(profile: player.id, console: livingRoom)
    #expect(selection && stream)
}

@Test func pairingsOfUnknownAccountsAreDroppedAndDeletedAccountsForgetTheirs() {
    var data = RegistrationFlow()
    data.restoreProfiles([player])
    let stranger = RegistrationFlow.Registration(profileID: UUID(), console: livingRoom)
    let own = RegistrationFlow.Registration(profileID: player.id, console: livingRoom)
    data.restoreRegistrations([stranger, own])
    #expect(data.registrations == [own])
    data.removeProfile(player.id)
    #expect(data.registrations.isEmpty)
    #expect(data.selectedProfileID == nil)
}

@Test func aRefreshThatDropsTheSelectedAccountSelectsTheFirst() {
    var data = RegistrationFlow()
    let second = RegistrationFlow.Profile(id: UUID(), name: "Second", kind: .npsso, accountID: nil)
    data.restoreProfiles([player, second], selected: second.id)
    let kept = data.updateProfiles([player, second])
    #expect(!kept)
    let dropped = data.updateProfiles([player])
    #expect(dropped)
    #expect(data.selectedProfileID == player.id)
}

@Test func forgettingARefusedPairingDropsOnlyTheSelectedAccountsPairing() {
    var data = RegistrationFlow()
    data.restoreProfiles([player])
    data.recordPairing(livingRoom)
    data.forgetPairing(livingRoom)
    #expect(data.registrations.isEmpty)
    #expect(data.selectedConsole == nil)
}
