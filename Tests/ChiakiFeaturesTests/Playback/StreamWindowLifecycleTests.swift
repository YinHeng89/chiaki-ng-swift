@testable import ChiakiFeatures
import ChiakiModels
import Foundation
import Testing

@Test func savedPictureSettingsWithoutTheFullScreenFieldStayWindowed() throws {
    let saved = try JSONEncoder().encode(PictureSettings())
    var object = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
    #expect(object["fullScreenStreams"] as? Bool == false)
    object.removeValue(forKey: "fullScreenStreams")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try !JSONDecoder().decode(PictureSettings.self, from: legacy).fullScreenStreams)
    var fullScreen = PictureSettings()
    fullScreen.fullScreenStreams = true
    let decoded = try JSONDecoder().decode(PictureSettings.self, from: JSONEncoder().encode(fullScreen))
    #expect(decoded.fullScreenStreams)
}
