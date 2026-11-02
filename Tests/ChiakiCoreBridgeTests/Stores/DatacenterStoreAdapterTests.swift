import enum ChiakiBridge.chiaki_bridge
import enum ChiakiBridge.libchiaking
import ChiakiCoreBridge
import ChiakiModels
import ChiakiPersistence
import Foundation
import Testing

extension CoreSessionSuites {
    @Suite struct DatacenterStoreAdapterTests {
        let measuredAtMs: Int64 = 1_760_000_000_500

        func known(_ service: CloudDatacenterService) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: PlayBridge().knownDatacenters(for: service).map {
                ($0.name, $0.roundTripMs)
            })
        }

        @Test func savedMeasurementsReachTheCoreAndForgettingClearsThem() throws {
            let harness = try CoreSessionHarness()
            defer {
                harness.remove()
            }
            let measuredAt = Date(timeIntervalSince1970: TimeInterval(measuredAtMs) / 1000)
            try harness.repositories.datacenters.save(
                [
                    DatacenterMeasurement(name: "eu-west", roundTripMs: 42, measuredAt: measuredAt),
                    DatacenterMeasurement(name: "us-east", roundTripMs: 97, measuredAt: measuredAt)
                ],
                for: .psCloud
            )
            let session = try harness.open()
            defer {
                session.close()
            }
            #expect(known(.psCloud) == ["eu-west": 42, "us-east": 97])
            let measured = PlayBridge().knownDatacenters(for: .psCloud).first { $0.name == "eu-west" }
            #expect(measured?.measuredAt == measuredAt)
            #expect(known(.psNow).isEmpty)
            #expect(PlayBridge().forgetDatacenters(for: .psCloud))
            #expect(try harness.repositories.datacenters.measurements(for: .psCloud).isEmpty)
            #expect(known(.psCloud).isEmpty)
        }
    }
}
