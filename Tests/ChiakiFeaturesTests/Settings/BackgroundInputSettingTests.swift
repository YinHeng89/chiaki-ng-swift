import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func backgroundInputIsOffByDefaultAndForSavedSettingsWithoutIt() throws {
    #expect(!ControlsConfiguration().backgroundInput)
    var saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ControlsConfiguration()))
        as? [String: Any] ?? [:]
    saved.removeValue(forKey: "backgroundInput")
    let legacy = try JSONDecoder().decode(
        ControlsConfiguration.self,
        from: JSONSerialization.data(withJSONObject: saved)
    )
    #expect(!legacy.backgroundInput)
    var enabled = ControlsConfiguration()
    enabled.backgroundInput = true
    let decoded = try JSONDecoder().decode(ControlsConfiguration.self, from: JSONEncoder().encode(enabled))
    #expect(decoded.backgroundInput)
}
