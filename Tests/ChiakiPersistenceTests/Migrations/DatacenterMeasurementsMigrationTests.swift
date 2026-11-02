@testable import ChiakiPersistence
import Foundation
import GRDB
import Testing

@Suite struct DatacenterMeasurementsMigrationTests {
    func measurement(_ name: String, rtt: Int, at milliseconds: Int64,
                     bandwidth: Int? = nil) -> [String: Any] {
        var entry: [String: Any] = [
            "name": name, "rttMs": rtt, "rttsMs": [rtt, rtt + 1], "mtuIn": 1454, "mtuOut": 1454, "port": 2053,
            "publicIP": "198.51.100.7", "maxBandwidth": 30000,
            "measuredAt": LegacyDatabase.referenceSeconds(milliseconds)
        ]
        if let bandwidth {
            entry["bandwidthKbps"] = bandwidth
            entry["bandwidthMeasuredAt"] = LegacyDatabase.referenceSeconds(milliseconds + 5000)
            entry["bandwidthRttMs"] = rtt + 3
        }
        return entry
    }

    func databaseAtThirteen() throws -> LegacyDatabase {
        let legacy = try LegacyDatabase(version: 13)
        let crowded = (0 ..< 70).map {
            measurement("cloud-\($0)", rtt: 100 - $0, at: 1_760_000_000_000)
        }
        let settings: [String: Any] = [
            "psNowChoice": "frankfurt",
            "psCloudChoice": "cloud-3",
            "selectsAtLaunch": false,
            "lastConnection": [
                "name": "frankfurt", "rttMs": 24, "service": "psnow",
                "connectedAt": LegacyDatabase.referenceSeconds(1_760_000_100_000)
            ],
            "psNowMeasurements": [
                measurement("frankfurt", rtt: 24, at: 1_760_000_000_123, bandwidth: 52000),
                measurement("london", rtt: 31, at: 1_760_000_000_456),
                measurement("london", rtt: 40, at: 1_760_000_000_789),
                measurement("Auto", rtt: 5, at: 1_760_000_000_000),
                measurement("", rtt: 5, at: 1_760_000_000_000),
                measurement("bad\u{7}name", rtt: 5, at: 1_760_000_000_000),
                measurement("zero", rtt: 0, at: 1_760_000_000_000)
            ],
            "psCloudMeasurements": crowded
        ]
        let json = try String(bytes: JSONSerialization.data(withJSONObject: settings), encoding: .utf8) ?? ""
        try legacy.execute("INSERT INTO settings(key, value_json) VALUES ('cloud.datacenters.v1', ?)", [json])
        try legacy.execute("INSERT INTO settings(key, value_json) VALUES ('sound.v1', '{\"volume\":1}')")
        return legacy
    }

    @Test func measurementsMoveIntoTheirTableValidatedAndCapped() throws {
        let legacy = try databaseAtThirteen()
        try legacy.migrate(to: 14)
        let psNow = try legacy.rows(
            "SELECT * FROM datacenter_measurements WHERE service = 'psnow' ORDER BY round_trip_ms, name"
        )
        #expect(psNow.map { $0["name"] as String } == ["frankfurt", "london"])
        #expect(psNow.map { $0["round_trip_ms"] as Int } == [24, 31])
        #expect(psNow.map { $0["measured_at"] as Int64 } == [1_760_000_000_123, 1_760_000_000_456])
        #expect(psNow[0]["samples_ms"] as String == "[24,25]")
        #expect(psNow[0]["bandwidth_kbps"] as Int? == 52000)
        #expect(psNow[0]["bandwidth_measured_at"] as Int64? == 1_760_000_005_123)
        #expect(psNow[0]["bandwidth_round_trip_ms"] as Int? == 27)
        #expect(psNow[1]["bandwidth_kbps"] as Int? == nil)
        #expect(psNow[0]["public_address"] as String == "198.51.100.7")
        let cloud = try legacy.rows(
            "SELECT name FROM datacenter_measurements WHERE service = 'pscloud' ORDER BY round_trip_ms"
        )
        #expect(cloud.count == 64)
        #expect(cloud.first?["name"] as String? == "cloud-69")
        #expect(cloud.last?["name"] as String? == "cloud-6")
    }

    @Test func theSettingsKeepOnlyTheUsersChoices() throws {
        let legacy = try databaseAtThirteen()
        try legacy.migrate(to: 14)
        let json: String = try #require(legacy.rows(
            "SELECT value_json FROM settings WHERE key = 'cloud.datacenters.v1'"
        ).first?["value_json"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["psNowMeasurements"] == nil)
        #expect(object["psCloudMeasurements"] == nil)
        #expect(object["psNowChoice"] as? String == "frankfurt")
        #expect(object["psCloudChoice"] as? String == "cloud-3")
        #expect(object["selectsAtLaunch"] as? Bool == false)
        #expect((object["lastConnection"] as? [String: Any])?["name"] as? String == "frankfurt")
        let sound: String? = try legacy.rows("SELECT value_json FROM settings WHERE key = 'sound.v1'")
            .first?["value_json"]
        #expect(sound == "{\"volume\":1}")
    }

    @Test func theTableRefusesWhatTheValidationRefuses() throws {
        let legacy = try databaseAtThirteen()
        try legacy.migrate(to: 14)
        for name in ["", "Auto", "tab\tname", String(repeating: "x", count: 257)] {
            #expect(throws: DatabaseError.self) {
                try legacy.execute(
                    """
                    INSERT INTO datacenter_measurements(service, name, round_trip_ms, measured_at)
                    VALUES ('psnow', ?, 10, 1)
                    """,
                    [name]
                )
            }
        }
        #expect(throws: DatabaseError.self) {
            try legacy.execute(
                """
                INSERT INTO datacenter_measurements(service, name, round_trip_ms, measured_at)
                VALUES ('psnow', 'x', 0, 1)
                """
            )
        }
    }

    @Test func aDatabaseWithoutDatacenterSettingsMigrates() throws {
        let legacy = try LegacyDatabase(version: 13)
        try legacy.migrate(to: 14)
        #expect(try legacy.rows("SELECT * FROM datacenter_measurements").isEmpty)
        #expect(try legacy.version() == 14)
    }
}
