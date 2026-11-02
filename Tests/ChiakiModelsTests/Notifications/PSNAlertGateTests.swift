import ChiakiModels
import Foundation
import Testing

private let start = Date(timeIntervalSince1970: 1_000_000)

@Test func aFirstAlertFromEachSenderShows() {
    var gate = PSNAlertGate()
    let settings = PSNAlertSettings()
    #expect(gate.admit(sender: "Friend", isInvitation: true, settings: settings, now: start) == .show)
    #expect(gate.admit(sender: "Other", isInvitation: false, settings: settings, now: start) == .show)
}

@Test func aSendersRepeatsAreCountedAndListedQuietlyUntilTheWindowPasses() {
    var gate = PSNAlertGate()
    let settings = PSNAlertSettings()
    #expect(gate.admit(sender: "Spammer", isInvitation: true, settings: settings, now: start) == .show)
    #expect(gate.admit(sender: "Spammer", isInvitation: true, settings: settings, now: start + 10)
        == .quiet(.repeated(count: 2)))
    #expect(gate.admit(sender: "Spammer", isInvitation: true, settings: settings, now: start + 20)
        == .quiet(.repeated(count: 3)))
    #expect(gate.admit(sender: "Spammer", isInvitation: true, settings: settings, now: start + 119)
        == .quiet(.repeated(count: 4)))
    #expect(gate.admit(sender: "Spammer", isInvitation: true, settings: settings, now: start + 121) == .show)
}

@Test func messagesHaveAShorterWindowAndDoNotHoldBackInvitations() {
    var gate = PSNAlertGate()
    let settings = PSNAlertSettings()
    #expect(gate.admit(sender: "Friend", isInvitation: false, settings: settings, now: start) == .show)
    #expect(gate.admit(sender: "Friend", isInvitation: false, settings: settings, now: start + 5)
        == .quiet(.repeated(count: 2)))
    #expect(gate.admit(sender: "Friend", isInvitation: true, settings: settings, now: start + 6) == .show)
    #expect(gate.admit(sender: "Friend", isInvitation: false, settings: settings, now: start + 31) == .show)
}

@Test func switchedOffKindsAndMutedSendersAreOnlyListed() {
    var gate = PSNAlertGate()
    var settings = PSNAlertSettings(invitations: false)
    #expect(gate
        .admit(sender: "Friend", isInvitation: true, settings: settings, now: start) == .quiet(.kindOff))
    #expect(gate.admit(sender: "Friend", isInvitation: false, settings: settings, now: start) == .show)
    settings.setMuted("Pest", true)
    #expect(gate.admit(sender: "Pest", isInvitation: false, settings: settings, now: start) == .quiet(.muted))
}

@Test func aFloodFromManySendersIsCappedPerMinute() {
    var gate = PSNAlertGate()
    let settings = PSNAlertSettings()
    for index in 0..<PSNAlertGate.globalLimit {
        #expect(gate
            .admit(sender: "Sender\(index)", isInvitation: true, settings: settings, now: start) == .show)
    }
    #expect(gate
        .admit(sender: "Late", isInvitation: true, settings: settings, now: start + 30) == .quiet(.busy))
    #expect(gate.admit(sender: "Later", isInvitation: true, settings: settings, now: start + 61) == .show)
}

@Test func mutedSendersStaySortedUniqueAndBounded() throws {
    var settings = PSNAlertSettings(mutedSenders: ["b", "a", "b", ""])
    #expect(settings.mutedSenders == ["a", "b"])
    settings.setMuted("c", true)
    settings.setMuted("a", false)
    #expect(settings.mutedSenders == ["b", "c"])
    let many = PSNAlertSettings(mutedSenders: (0..<300).map { "s\($0)" })
    #expect(many.mutedSenders.count == PSNAlertSettings.mutedLimit)
    let decoded = try JSONDecoder().decode(PSNAlertSettings.self, from: Data(#"{"messages":false}"#.utf8))
    #expect(decoded == PSNAlertSettings(messages: false))
}

@Test func aSummaryRespectsSettingsAndTheCapAndOpensANewWindow() {
    var gate = PSNAlertGate()
    var settings = PSNAlertSettings()
    #expect(gate.admit(sender: "Chatty", isInvitation: false, settings: settings, now: start) == .show)
    #expect(gate.admitSummary(sender: "Chatty", settings: settings, now: start + 30) == .show)
    #expect(gate.admit(sender: "Chatty", isInvitation: false, settings: settings, now: start + 31)
        == .quiet(.repeated(count: 2)))
    settings.setMuted("Chatty", true)
    #expect(gate.admitSummary(sender: "Chatty", settings: settings, now: start + 90) == .quiet(.muted))
}
