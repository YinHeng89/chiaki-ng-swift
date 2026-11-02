import ChiakiModels
import Foundation
import Testing

@Test func developerSettingsDefaultToAutomaticTakionEverywhere() throws {
    let settings = DeveloperSettings()
    for target in TakionTarget.allCases {
        #expect(settings[target] == 0)
    }
    let decoded = try JSONDecoder().decode(DeveloperSettings.self, from: Data("{}".utf8))
    #expect(decoded == settings)
    var edited = settings
    edited[.psCloud] = 20
    edited[.localPS4] = 12
    let roundTrip = try JSONDecoder().decode(DeveloperSettings.self, from: JSONEncoder().encode(edited))
    #expect(roundTrip == edited)
    #expect(roundTrip.takionPSCloud == 20 && roundTrip.takionLocalPS4 == 12 && roundTrip.takionLocalPS5 == 0)
}

@Test func developerSettingsSpreadTheLegacySingleVersionAcrossEveryTarget() throws {
    let legacy = try JSONDecoder().decode(DeveloperSettings.self, from: Data(#"{"takionVersion":15}"#.utf8))
    #expect(legacy == DeveloperSettings(allTakion: 15))
    let mixed = try JSONDecoder().decode(
        DeveloperSettings.self, from: Data(#"{"takionVersion":15,"takionPSNow":9}"#.utf8)
    )
    #expect(mixed.takionPSNow == 9 && mixed.takionLocalPS5 == 15)
    let data = try JSONEncoder().encode(legacy)
    #expect(String(bytes: data, encoding: .utf8)?.contains("\"takionVersion\"") == false)
}

@Test func developerSettingsAcceptOnlyImplementedTakionVersionsPerTarget() throws {
    #expect(DeveloperSettings.takionVersions == [9, 12, 15, 19, 20])
    #expect(try DeveloperSettings(allTakion: 20).validated().takionLocalPS5 == 20)
    #expect(try DeveloperSettings().validated() == DeveloperSettings())
    var settings = DeveloperSettings()
    settings[.psNow] = 8
    #expect(throws: DeveloperSettingsError.unknownTakionVersion(8)) {
        try settings.validated()
    }
    #expect(!DeveloperSettings.isValidTakionVersion(18))
    #expect(TakionTarget.localPS4.negotiatedVersion == 9 && TakionTarget.psNow.negotiatedVersion == 9)
    #expect(TakionTarget.localPS5.negotiatedVersion == 15 && TakionTarget.psCloud.negotiatedVersion == 12)
}

@Test func developerSettingsOfferCloudOnlyTakionVersionsToPSCloudOnly() throws {
    #expect(DeveloperSettings.cloudOnlyTakionVersions == [21, 23, 25])
    #expect(DeveloperSettings.takionVersions(for: .psCloud) == [9, 12, 15, 19, 20, 21, 23, 25])
    for target in [TakionTarget.localPS4, .localPS5, .psNow] {
        #expect(DeveloperSettings.takionVersions(for: target) == [9, 12, 15, 19, 20])
        for version: UInt32 in [21, 23, 25] {
            var settings = DeveloperSettings()
            settings[target] = version
            #expect(throws: DeveloperSettingsError.unknownTakionVersion(version)) {
                try settings.validated()
            }
            #expect(!DeveloperSettings.isValidTakionVersion(version, for: target))
        }
    }
    for version: UInt32 in [21, 23, 25] {
        var settings = DeveloperSettings()
        settings[.psCloud] = version
        #expect(try settings.validated().takionPSCloud == version)
    }
    for version: UInt32 in [22, 24, 26] {
        #expect(!DeveloperSettings.isValidTakionVersion(version, for: .psCloud))
        #expect(!DeveloperSettings.isValidTakionVersion(version))
    }
}

@Test func developerSettingsFallBackToAutomaticForPersistedVersionsInvalidForTheTarget() throws {
    let json = #"{"takionLocalPS4":21,"takionLocalPS5":20,"takionPSNow":25,"takionPSCloud":23}"#
    let decoded = try JSONDecoder().decode(DeveloperSettings.self, from: Data(json.utf8))
    #expect(decoded.takionLocalPS4 == 0 && decoded.takionLocalPS5 == 20)
    #expect(decoded.takionPSNow == 0 && decoded.takionPSCloud == 23)
    let legacy = try JSONDecoder().decode(DeveloperSettings.self, from: Data(#"{"takionVersion":21}"#.utf8))
    #expect(legacy.takionPSCloud == 21 && legacy.takionLocalPS4 == 0 && legacy.takionPSNow == 0)
    let unknown = try JSONDecoder().decode(DeveloperSettings.self, from: Data(#"{"takionPSCloud":22}"#.utf8))
    #expect(unknown.takionPSCloud == 0)
}

@Test func developerSettingsNegotiationDefaultsOffAndRoundTripsPerTarget() throws {
    let settings = DeveloperSettings()
    for target in TakionTarget.allCases {
        #expect(!settings[negotiation: target])
    }
    let old = try JSONDecoder().decode(DeveloperSettings.self, from: Data(#"{"takionPSCloud":23}"#.utf8))
    for target in TakionTarget.allCases {
        #expect(!old[negotiation: target])
    }
    var edited = old
    edited[negotiation: .localPS5] = true
    edited[negotiation: .psCloud] = true
    let roundTrip = try JSONDecoder().decode(DeveloperSettings.self, from: JSONEncoder().encode(edited))
    #expect(roundTrip == edited)
    #expect(roundTrip.negotiateLocalPS5 && roundTrip.negotiatePSCloud)
    #expect(!roundTrip.negotiateLocalPS4 && !roundTrip.negotiatePSNow)
    #expect(roundTrip.takionPSCloud == 23)
    #expect(try edited.validated() == edited)
}

@Test func developerSettingsKeepOnlyOfferedLibraryRefreshCooldowns() throws {
    #expect(DeveloperSettings().libraryRefreshCooldownMinutes == 15)
    #expect(DeveloperSettings().libraryRefreshCooldown == .seconds(900))
    let stored = try JSONDecoder().decode(
        DeveloperSettings.self, from: Data(#"{"libraryRefreshCooldownMinutes":5}"#.utf8)
    )
    #expect(stored.libraryRefreshCooldownMinutes == 5)
    let unknown = try JSONDecoder().decode(
        DeveloperSettings.self, from: Data(#"{"libraryRefreshCooldownMinutes":7}"#.utf8)
    )
    #expect(unknown.libraryRefreshCooldownMinutes == 15)
    let roundTrip = try JSONDecoder().decode(DeveloperSettings.self, from: JSONEncoder().encode(stored))
    #expect(roundTrip == stored)
    #expect(throws: DeveloperSettingsError.unknownLibraryRefreshCooldown(7)) {
        try DeveloperSettings(libraryRefreshCooldownMinutes: 7).validated()
    }
    #expect(DeveloperSettings.libraryRefreshCooldownTitle(minutes: 0) == "Off")
    #expect(DeveloperSettings.libraryRefreshCooldownTitle(minutes: 1) == "1 minute")
    #expect(DeveloperSettings.libraryRefreshCooldownTitle(minutes: 15) == "15 minutes")
}
