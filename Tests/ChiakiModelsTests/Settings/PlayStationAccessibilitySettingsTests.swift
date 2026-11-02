import ChiakiModels
import Foundation
import Testing

@Test func playStationAccessibilityChoicesSurviveAReload() throws {
    var chosen = PlayStationAccessibilitySettings()
    chosen.screenReaderOverride = true
    chosen.screenReaderSpeed = 7
    chosen.screenReaderVolume = 20
    chosen.textSizeOverride = 2
    chosen.boldTextOverride = true
    chosen.higherContrastOverride = true
    let decoded = try JSONDecoder().decode(
        PlayStationAccessibilitySettings.self,
        from: JSONEncoder().encode(chosen)
    )
    #expect(decoded == chosen)
    #expect(PlayStationAccessibilitySettings.settingKey.name == "playstation.accessibility.v1")
}

@Test func playStationAccessibilityUsesDefaultsForUnsetOverrides() throws {
    let settings = try JSONDecoder().decode(PlayStationAccessibilitySettings.self, from: Data("{}".utf8))
    #expect(settings.screenReaderOverride == nil)
    #expect(settings.higherContrastOverride == nil)
    #expect(settings.screenReaderSpeed == 3)
    #expect(settings.screenReaderVolume == 12)
    #expect(settings.textSizeOverride == nil)
    #expect(settings.boldTextOverride == nil)
    #expect(settings == PlayStationAccessibilitySettings())
}

@Test func playStationAccessibilityFollowsDefaultsUntilEachChoiceIsOverridden() {
    var settings = PlayStationAccessibilitySettings()
    let device = PlayStationAccessibilityDefaults(
        screenReader: true, textSize: 1, boldText: true, higherContrast: true
    )
    let following = settings.resolved(using: device)
    #expect(following.screenReader)
    #expect(following.textSize == 1)
    #expect(following.boldText)
    #expect(following.higherContrast)
    settings.screenReaderOverride = false
    settings.textSizeOverride = -1
    settings.boldTextOverride = false
    settings.higherContrastOverride = false
    let resolved = settings.resolved(using: device)
    #expect(!resolved.screenReader)
    #expect(resolved.textSize == -1)
    #expect(!resolved.boldText)
    #expect(!resolved.higherContrast)
    #expect(resolved.screenReaderSpeed == 3 && resolved.screenReaderVolume == 12)
}

@Test func playStationAccessibilityKeepsValuesInRangeAndCarriesOverLargeText() throws {
    let decode = { (json: String) in
        try JSONDecoder().decode(PlayStationAccessibilitySettings.self, from: Data(json.utf8))
    }
    #expect(try decode(#"{"textSizeOverride":-1}"#).textSizeOverride == -1)
    #expect(try decode(#"{"textSizeOverride":3}"#).textSizeOverride == nil)
    #expect(try decode(#"{"largeTextOverride":true}"#).textSizeOverride == 1)
    #expect(try decode(#"{"largeTextOverride":false}"#).textSizeOverride == 0)
    #expect(try decode(#"{"textSizeOverride":2,"largeTextOverride":false}"#).textSizeOverride == 2)
    #expect(try decode(#"{"screenReaderSpeed":9,"screenReaderVolume":25}"#).screenReaderSpeed == 3)
    #expect(try decode(#"{"screenReaderSpeed":9,"screenReaderVolume":25}"#).screenReaderVolume == 12)
    var outOfRange = PlayStationAccessibilitySettings()
    outOfRange.screenReaderSpeed = 12
    outOfRange.screenReaderVolume = -4
    outOfRange.textSizeOverride = 5
    let normalized = outOfRange.normalized()
    #expect(normalized.screenReaderSpeed == 8)
    #expect(normalized.screenReaderVolume == 0)
    #expect(normalized.textSizeOverride == 2)
}
