import ChiakiModels
import Testing
@testable import ChiakiFeatures

@Test func theNewRefusalsHaveTheirOwnLabels() {
    #expect(RegistrationFailureMessage.text(for: .sessionPlaying) == "A session is playing")
    #expect(!RegistrationFailure.sessionPlaying.isRemote)
}
