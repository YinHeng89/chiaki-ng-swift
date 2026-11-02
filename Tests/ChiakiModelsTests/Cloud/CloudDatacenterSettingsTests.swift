import Foundation
import Testing
@testable import ChiakiModels

private let probes = [
    CloudDatacenterPingRow(
        name: "dc1", rtt: 21, rtts: [21], mtuIn: 1454, mtuOut: 1254, port: 2053,
        publicIP: "192.0.2.1", maxBandwidth: 20000, measured: true
    ),
    CloudDatacenterPingRow(
        name: "dc2", rtt: 999, rtts: [999], mtuIn: 0, mtuOut: 0, port: 0,
        publicIP: "", maxBandwidth: 0, measured: false
    )
]

@Test func recordingKeepsAgesForUnchangedProbesAndIgnoresForcedSessions() {
    let first = Date(timeIntervalSince1970: 1000)
    let later = Date(timeIntervalSince1970: 9000)
    let rows = probes
    let recorded = CloudDatacenterSettings().recording(rows, for: .psNow, forced: false, at: first)
    #expect(recorded.psNowMeasurements.map(\.name) == ["dc1"])
    #expect(recorded.psCloudMeasurements.isEmpty)

    let replayed = recorded.recording(rows, for: .psNow, forced: false, at: later)
    #expect(replayed.psNowMeasurements[0].measuredAt == first)

    var faster = rows[0]
    faster.rtt = 12
    faster.rtts = [12, 13]
    var newcomer = rows[0]
    newcomer.name = "dc3"
    newcomer.rtt = 40
    let refreshed = recorded.recording([faster, newcomer, rows[1]], for: .psNow, forced: false, at: later)
    #expect(refreshed.psNowMeasurements.map(\.name) == ["dc1", "dc3"])
    #expect(refreshed.psNowMeasurements[0].rttMs == 12)
    #expect(refreshed.psNowMeasurements[0].measuredAt == later)

    var dummy = rows[0]
    dummy.rtt = 20
    dummy.rtts = [20]
    #expect(recorded.recording([dummy], for: .psNow, forced: true, at: later) == recorded)
}

@Test func datacenterChoicesRejectInvalidNamesAndPersistAsJSON() throws {
    var settings = CloudDatacenterSettings()
    settings.setChoice("Auto", for: .psCloud)
    #expect(settings.psCloudChoice == nil)
    settings.setChoice("bad\nname", for: .psCloud)
    #expect(settings.psCloudChoice == nil)
    settings.setChoice(String(repeating: "a", count: 257), for: .psNow)
    #expect(settings.psNowChoice == nil)
    settings.setChoice("us-east-1", for: .psCloud)
    #expect(settings.choice(for: .psCloud) == "us-east-1")
    #expect(settings.choice(for: .psNow) == nil)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(CloudDatacenterSettings.self, from: data).validated() == settings)
    #expect(settings.forgettingMeasurements() == CloudDatacenterSettings())
}

@Test func selectAtLaunchDecodesOlderRecordsAndSurvivesForgetting() throws {
    let older = try JSONDecoder().decode(
        CloudDatacenterSettings.self,
        from: Data("{\"psCloudChoice\":\"dc1\",\"psNowMeasurements\":[],\"psCloudMeasurements\":[]}".utf8)
    )
    #expect(older.selectsAtLaunch)
    #expect(older.lastConnection == nil)
    #expect(older.psCloudChoice == "dc1")
    let optedOut = try JSONDecoder().decode(
        CloudDatacenterSettings.self,
        from: Data("{\"psCloudChoice\":\"dc1\",\"selectsAtLaunch\":false}".utf8)
    )
    #expect(!optedOut.selectsAtLaunch)
    #expect(optedOut.psCloudChoice == "dc1")
    let enabled = optedOut.selectingAtLaunch(true)
    let roundTrip = try JSONDecoder().decode(
        CloudDatacenterSettings.self,
        from: JSONEncoder().encode(enabled)
    )
    #expect(roundTrip == enabled && roundTrip.selectsAtLaunch)
    let forgotten = enabled.forgettingMeasurements()
    #expect(forgotten.selectsAtLaunch)
    #expect(forgotten.psCloudChoice == nil)
}

@Test func launchOfferSortsByFreshPingAndMarksHighLatency() {
    let rows = [
        CloudDatacenterPingRow(
            name: "eu-west-1", rtt: 91, rtts: [91], mtuIn: 0, mtuOut: 0, port: 0,
            publicIP: "", maxBandwidth: 0, measured: true
        ),
        CloudDatacenterPingRow(
            name: "ap-north-1", rtt: 999, rtts: [999], mtuIn: 0, mtuOut: 0, port: 0,
            publicIP: "", maxBandwidth: 0, measured: false
        ),
        CloudDatacenterPingRow(
            name: "us-east-1", rtt: 34, rtts: [34], mtuIn: 0, mtuOut: 0, port: 0,
            publicIP: "", maxBandwidth: 0, measured: true
        ),
        CloudDatacenterPingRow(
            name: "us-east-1", rtt: 40, rtts: [40], mtuIn: 0, mtuOut: 0, port: 0,
            publicIP: "", maxBandwidth: 0, measured: true
        ),
        CloudDatacenterPingRow(
            name: "Auto", rtt: 1, rtts: [1], mtuIn: 0, mtuOut: 0, port: 0,
            publicIP: "", maxBandwidth: 0, measured: true
        )
    ]
    let offer = CloudDatacenterLaunchOffer(rows: rows)
    #expect(offer.entries.map(\.name) == ["us-east-1", "eu-west-1", "ap-north-1"])
    #expect(offer.entries.map(\.pingDescription) == ["34 ms", "91 ms", "No reply"])
    #expect(offer.entries.map(\.highLatency) == [false, true, true])
    #expect(offer.lowest?.name == "us-east-1")
    #expect(offer.timeoutSeconds == 15)
    #expect(CloudDatacenterLaunchOffer.pingNote == "Ping is the adjusted value the stream core reports")
    #expect(offer.offers("eu-west-1") && offer.offers("Auto") && !offer.offers("sa-east-1"))
    let unanswered = CloudDatacenterLaunchOffer(rows: [rows[1]])
    #expect(unanswered.lowest == nil)
}

@Test func launchPickSelectionReportsTheFreshPing() {
    let settings = CloudDatacenterSettings()
    let picked = CloudDatacenterSelection.reported(
        name: "eu-west-1", rttMs: 91, forced: true, settings: settings, service: .psCloud, atLaunch: true
    )
    #expect(picked.connectingDescription == "Connecting to eu-west-1 (91 ms)")
    #expect(picked.statisticsDescription == "eu-west-1 at 91 ms, chosen at launch")
    let timedOut = CloudDatacenterSelection.reported(
        name: "us-east-1", rttMs: 34, forced: false, settings: settings, service: .psCloud, atLaunch: true
    )
    #expect(timedOut.automatic && timedOut.statisticsDescription == "us-east-1 at 34 ms, automatic")
}

@Test func lastConnectionRoundTripsSurvivesForgettingAndRejectsInvalidNames() throws {
    let connectedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let settings = CloudDatacenterSettings().connecting(
        to: "us-east-1", rttMs: 34, service: .psCloud, at: connectedAt
    )
    #expect(settings.lastConnection == CloudDatacenterConnection(
        name: "us-east-1", rttMs: 34, service: .psCloud, connectedAt: connectedAt
    ))
    let roundTrip = try JSONDecoder().decode(
        CloudDatacenterSettings.self,
        from: JSONEncoder().encode(settings)
    )
    #expect(roundTrip == settings)
    #expect(
        settings.forgettingMeasurements().lastConnection == settings.lastConnection
    )
    #expect(settings.connecting(to: "Auto", rttMs: 10, service: .psNow, at: connectedAt) == settings)
    let unmeasured = settings.connecting(to: "eu-west-1", rttMs: 0, service: .psNow, at: connectedAt)
    #expect(unmeasured.lastConnection?.rttMs == nil)
    #expect(unmeasured.lastConnection?.service == .psNow)
    let malformed = try JSONDecoder().decode(
        CloudDatacenterSettings.self,
        from: Data("{\"lastConnection\":{\"name\":1}}".utf8)
    )
    #expect(malformed.lastConnection == nil)
    #expect(malformed.selectsAtLaunch)
}

@Test func launchOfferEntriesDescribeTheSavedBandwidth() {
    #expect(CloudDatacenterLaunchOffer.Entry(name: "sjcb", rttMs: 1, bandwidthKbps: 55000)
        .bandwidthDescription == "55 Mbps")
    #expect(CloudDatacenterLaunchOffer.Entry(name: "sjcb", rttMs: 1).bandwidthDescription == nil)
    #expect(CloudDatacenterLaunchOffer.Entry(name: "sjcb", rttMs: 1, bandwidthKbps: 0)
        .bandwidthDescription == nil)
}

@Test func choosingAutomaticallyDropsEveryChoiceAndTheLaunchPickButKeepsMeasurements() {
    let measuredAt = Date(timeIntervalSince1970: 1000)
    var settings = CloudDatacenterSettings().recording(probes, for: .psCloud, forced: false, at: measuredAt)
    settings.setChoice("dc1", for: .psCloud)
    settings.setChoice("dc2", for: .psNow)
    let automatic = settings.choosingAutomatically()
    #expect(automatic.choice(for: .psCloud) == nil)
    #expect(automatic.choice(for: .psNow) == nil)
    #expect(!automatic.selectsAtLaunch)
    #expect(automatic.psCloudMeasurements == settings.psCloudMeasurements)
}
