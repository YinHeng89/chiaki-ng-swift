import ChiakiModels
import Testing

@Suite struct ConsoleFirmwareTests {
    @Test func everyPS4FamilyStaysDistinctAndBelongsToThePS4() {
        #expect(ConsoleFirmware.allCases.map(\.rawValue) == ["ps4_8", "ps4_9", "ps4_10", "ps5"])
        #expect([ConsoleFirmware.ps4_8, .ps4_9, .ps4_10].allSatisfy { $0.kind == .ps4 })
        #expect(ConsoleFirmware.ps5.kind == .ps5)
    }

    @Test func aConsoleWithNothingKnownAssumesTheNewestFamilyOfItsGeneration() {
        #expect(ConsoleFirmware.assumed(for: .ps4) == .ps4_10)
        #expect(ConsoleFirmware.assumed(for: .ps5) == .ps5)
    }

    @Test func nameSourcesKeepTheCoreOrderAndStoredText() {
        #expect(
            ConsoleNameSource.allCases.map(\.rawValue)
                == ["generation", "account", "pairing", "discovered", "renamed"]
        )
    }
}
