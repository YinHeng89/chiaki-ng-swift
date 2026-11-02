import ChiakiModels
@testable import ChiakiPersistence
import Foundation
import Testing

@Suite struct DatacenterMeasurementRepositoryTests {
    static func measurement(_ name: String, rtt: Int, bandwidth: Bool = false) -> DatacenterMeasurement {
        DatacenterMeasurement(
            name: name,
            roundTripMs: rtt,
            samplesMs: [rtt, rtt + 2],
            mtuIn: 1454,
            mtuOut: 1400,
            port: 2053,
            publicAddress: "198.51.100.7",
            maxBandwidth: 30000,
            measuredAt: Date(timeIntervalSince1970: 1_760_000_000.123),
            bandwidth: bandwidth
                ? DatacenterBandwidth(
                    kbps: 52000,
                    measuredAt: Date(timeIntervalSince1970: 1_760_000_005),
                    roundTripMs: 30
                )
                : nil
        )
    }

    @Test func measurementsPersistPerServiceAcrossReopen() throws {
        let file = TestDatabase.scratchFile()
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        let keys = KeychainKeyStore(source: .memory())
        let first = try DatacenterMeasurementRepository(database: AppDatabase(path: file.path, keys: keys))
        let frankfurt = Self.measurement("frankfurt", rtt: 24, bandwidth: true)
        try first.save([frankfurt], for: .psCloud)
        try first.save([Self.measurement("london", rtt: 31)], for: .psNow)
        let reopened = try DatacenterMeasurementRepository(database: AppDatabase(path: file.path, keys: keys))
        #expect(try reopened.measurements(for: .psCloud) == [frankfurt])
        #expect(try reopened.measurements(for: .psNow).map(\.name) == ["london"])
    }

    @Test func aSaveKeepsOnlyValidNamesAndTheFastestSixtyFour() throws {
        let fixture = try TestDatabase()
        let repository = DatacenterMeasurementRepository(database: fixture.database)
        let many = (0 ..< 70).map {
            Self.measurement("dc-\($0)", rtt: 200 - $0)
        }
        let invalid = ["", "Auto", "bad\u{1}", String(repeating: "x", count: 257)].map {
            Self.measurement($0, rtt: 1)
        }
        try repository.save(
            many + invalid + [Self.measurement("dc-69", rtt: 5), Self.measurement("slow", rtt: 0)],
            for: .psCloud
        )
        let kept = try repository.measurements(for: .psCloud)
        #expect(kept.count == DatacenterMeasurement.maximumPerService)
        #expect(kept.first?.name == "dc-69")
        #expect(kept.first?.roundTripMs == 131)
        #expect(kept.allSatisfy { DatacenterMeasurement.isValidName($0.name) })
    }

    @Test func concurrentWritersNeverLoseEachOthersService() async throws {
        let fixture = try TestDatabase()
        let repository = DatacenterMeasurementRepository(database: fixture.database)
        await withTaskGroup(of: Void.self) { group in
            for round in 0 ..< 40 {
                group.addTask {
                    try? repository.save([Self.measurement("now-\(round)", rtt: 10 + round)], for: .psNow)
                }
                group.addTask {
                    try? repository.save([Self.measurement("cloud-\(round)", rtt: 10 + round)], for: .psCloud)
                }
            }
        }
        #expect(try repository.measurements(for: .psNow).count == 1)
        #expect(try repository.measurements(for: .psCloud).count == 1)
    }

    @Test func forgettingClearsEveryService() throws {
        let fixture = try TestDatabase()
        let repository = DatacenterMeasurementRepository(database: fixture.database)
        try repository.save([Self.measurement("a", rtt: 9)], for: .psNow)
        try repository.save([Self.measurement("b", rtt: 9)], for: .psCloud)
        try repository.forgetAll()
        #expect(try repository.measurements(for: .psNow).isEmpty)
        #expect(try repository.measurements(for: .psCloud).isEmpty)
    }
}
