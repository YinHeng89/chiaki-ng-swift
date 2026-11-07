import ChiakiModels
import Foundation
import Testing
@testable import ChiakiFeatures

@Test func theNewRefusalsHaveTheirOwnLabels() {
    #expect(
        String(localized: RegistrationFailureMessage.text(for: .sessionPlaying)) == "A session is playing"
    )
    #expect(!RegistrationFailure.sessionPlaying.isRemote)
}
